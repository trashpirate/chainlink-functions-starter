// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IFunctionsRouter} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/interfaces/IFunctionsRouter.sol";
import {IFunctionsCoordinator} from
    "@chainlink/contracts/src/v0.8/functions/v1_0_0/interfaces/IFunctionsCoordinator.sol";
import {IFunctionsSubscriptions} from
    "@chainlink/contracts/src/v0.8/functions/v1_0_0/interfaces/IFunctionsSubscriptions.sol";
import {FunctionsResponse} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsResponse.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract FunctionsRouterMock is ConfirmedOwner {
    using SafeERC20 for IERC20;
    using FunctionsResponse for FunctionsResponse.RequestMeta;
    using FunctionsResponse for FunctionsResponse.Commitment;
    using FunctionsResponse for FunctionsResponse.FulfillResult;

    string public constant typeAndVersion = "Functions Router v1.0.0";

    // We limit return data to a selector plus 4 words. This is to avoid
    // malicious contracts from returning large amounts of data and causing
    // repeated out-of-gas scenarios.
    uint16 public constant MAX_CALLBACK_RETURN_BYTES = 4 + 4 * 32;
    uint8 private constant MAX_CALLBACK_GAS_LIMIT_FLAGS_INDEX = 0;

    event RequestStart(
        bytes32 indexed requestId,
        bytes32 indexed donId,
        uint64 indexed subscriptionId,
        address subscriptionOwner,
        address requestingContract,
        address requestInitiator,
        bytes data,
        uint16 dataVersion,
        uint32 callbackGasLimit,
        uint96 estimatedTotalCostJuels
    );

    event RequestProcessed(
        bytes32 indexed requestId,
        uint64 indexed subscriptionId,
        uint96 totalCostJuels,
        address transmitter,
        FunctionsResponse.FulfillResult resultCode,
        bytes response,
        bytes err,
        bytes callbackReturnData
    );

    event RequestNotProcessed(
        bytes32 indexed requestId, address coordinator, address transmitter, FunctionsResponse.FulfillResult resultCode
    );

    error EmptyRequestData();
    error OnlyCallableFromCoordinator();
    error SenderMustAcceptTermsOfService(address sender);
    error InvalidGasFlagValue(uint8 value);
    error GasLimitTooBig(uint32 limit);
    error DuplicateRequestId(bytes32 requestId);

    struct CallbackResult {
        bool success; // ══════╸ Whether the callback succeeded or not
        uint256 gasUsed; // ═══╸ The amount of gas consumed during the callback
        bytes returnData; // ══╸ The return of the callback function
    }

    // ================================================================
    // |                         Balance state                        |
    // ================================================================
    // link token address
    IERC20 internal immutable i_linkToken;

    // s_totalLinkBalance tracks the total LINK sent to/from
    // this contract through onTokenTransfer, cancelSubscription and oracleWithdraw.
    // A discrepancy with this contract's LINK balance indicates that someone
    // sent tokens using transfer and so we may need to use recoverFunds.
    uint96 private s_totalLinkBalance;

    /// @dev NOP balances are held as a single amount. The breakdown is held by the Coordinator.
    mapping(address coordinator => uint96 balanceJuelsLink) private s_withdrawableTokens;

    // ================================================================
    // |                      Subscription state                      |
    // ================================================================

    struct Subscription {
        uint96 balance; // ═════════╗ Common LINK balance that is controlled by the Router to be used for all consumer requests.
        address owner; // ══════════╝ The owner can fund/withdraw/cancel the subscription.
        uint96 blockedBalance; // ══╗ LINK balance that is reserved to pay for pending consumer requests.
        address proposedOwner; // ══╝ For safely transferring sub ownership.
        address[] consumers; // ════╸ Client contracts that can use the subscription
        bytes32 flags; // ══════════╸ Per-subscription flags
    }

    struct Consumer {
        bool allowed; // ══════════════╗ Owner can fund/withdraw/cancel the sub.
        uint64 initiatedRequests; //   ║ The number of requests that have been started
        uint64 completedRequests; // ══╝ The number of requests that have successfully completed or timed out
    }

    // Keep a count of the number of subscriptions so that its possible to
    // loop through all the current subscriptions via .getSubscription().
    uint64 private s_currentSubscriptionId;

    mapping(uint64 subscriptionId => Subscription) private s_subscriptions;

    // Maintains the list of keys in s_consumers.
    // We do this for 2 reasons:
    // 1. To be able to clean up all keys from s_consumers when canceling a subscription.
    // 2. To be able to return the list of all consumers in getSubscription.
    // Note that we need the s_consumers map to be able to directly check if a
    // consumer is valid without reading all the consumers from storage.
    mapping(address consumer => mapping(uint64 subscriptionId => Consumer)) private s_consumers;

    event SubscriptionCreated(uint64 indexed subscriptionId, address owner);
    event SubscriptionFunded(uint64 indexed subscriptionId, uint256 oldBalance, uint256 newBalance);
    event SubscriptionConsumerAdded(uint64 indexed subscriptionId, address consumer);
    event SubscriptionConsumerRemoved(uint64 indexed subscriptionId, address consumer);
    event SubscriptionCanceled(uint64 indexed subscriptionId, address fundsRecipient, uint256 fundsAmount);
    event SubscriptionOwnerTransferRequested(uint64 indexed subscriptionId, address from, address to);
    event SubscriptionOwnerTransferred(uint64 indexed subscriptionId, address from, address to);

    error TooManyConsumers(uint16 maximumConsumers);
    error InsufficientBalance(uint96 currentBalanceJuels);
    error InvalidConsumer();
    error CannotRemoveWithPendingRequests();
    error InvalidSubscription();
    error OnlyCallableFromLink();
    error InvalidCalldata();
    error MustBeSubscriptionOwner();
    error TimeoutNotExceeded();
    error MustBeProposedOwner(address proposedOwner);

    event FundsRecovered(address to, uint256 amount);

    // ================================================================
    // |                    Route state                       |
    // ================================================================

    mapping(bytes32 id => address routableContract) private s_route;

    error RouteNotFound(bytes32 id);

    // Identifier for the route to the Terms of Service Allow List
    bytes32 private s_allowListId;

    // ================================================================
    // |                    Configuration state                       |
    // ================================================================
    struct Config {
        uint16 maxConsumersPerSubscription; // ═════════╗ Maximum number of consumers which can be added to a single subscription. This bound ensures we are able to loop over all subscription consumers as needed, without exceeding gas limits. Should a user require more consumers, they can use multiple subscriptions.
        uint72 adminFee; //                             ║ Flat fee (in Juels of LINK) that will be paid to the Router owner for operation of the network
        bytes4 handleOracleFulfillmentSelector; //      ║ The function selector that is used when calling back to the Client contract
        uint16 gasForCallExactCheck; // ════════════════╝ Used during calling back to the client. Ensures we have at least enough gas to be able to revert if gasAmount >  63//64*gas available.
        uint32[] maxCallbackGasLimits; // ══════════════╸ List of max callback gas limits used by flag with GAS_FLAG_INDEX
        uint16 subscriptionDepositMinimumRequests; //═══╗ Amount of requests that must be completed before the full subscription balance will be released when closing a subscription account.
        uint72 subscriptionDepositJuels; // ════════════╝ Amount of subscription funds that are held as a deposit until Config.subscriptionDepositMinimumRequests are made using the subscription.
    }

    Config private s_config;

    event ConfigUpdated(Config);

    // ================================================================
    // |                         Proposal state                       |
    // ================================================================

    uint8 private constant MAX_PROPOSAL_SET_LENGTH = 8;

    struct ContractProposalSet {
        bytes32[] ids; // ══╸ The IDs that key into the routes that will be modified if the update is applied
        address[] to; // ═══╸ The address of the contracts that the route will point to if the updated is applied
    }

    ContractProposalSet private s_proposedContractSet;

    event ContractProposed(
        bytes32 proposedContractSetId, address proposedContractSetFromAddress, address proposedContractSetToAddress
    );

    event ContractUpdated(bytes32 id, address from, address to);

    error InvalidProposal();
    error IdentifierIsReserved(bytes32 id);

    // ================================================================
    // |                       Request state                          |
    // ================================================================

    uint256 private s_nextRequestId = 1;
    mapping(bytes32 requestId => bytes32 commitmentHash) internal s_requestCommitments;
    mapping(bytes32 requestId => FunctionsResponse.Commitment commitment) internal s_commitments;

    struct Receipt {
        uint96 callbackGasCostJuels;
        uint96 totalCostJuels;
    }

    event RequestTimedOut(bytes32 indexed requestId);

    // ================================================================
    // |                       Initialization                         |
    // ================================================================

    constructor(address linkToken, Config memory config) ConfirmedOwner(msg.sender) {
        i_linkToken = IERC20(linkToken);
        // Set the intial configuration
        updateConfig(config);
    }

    // ================================================================
    // |                        Configuration                         |
    // ================================================================

    /// @notice The identifier of the route to retrieve the address of the access control contract
    // The access control contract controls which accounts can manage subscriptions
    /// @return id - bytes32 id that can be passed to the "getContractById" of the Router
    function getConfig() external view returns (Config memory) {
        return s_config;
    }

    /// @notice The router configuration
    function updateConfig(Config memory config) public onlyOwner {
        s_config = config;
        emit ConfigUpdated(config);
    }

    function isValidCallbackGasLimit(uint64 subscriptionId, uint32 callbackGasLimit) public view {
        uint8 callbackGasLimitsIndexSelector = uint8(getFlags(subscriptionId)[MAX_CALLBACK_GAS_LIMIT_FLAGS_INDEX]);
        if (callbackGasLimitsIndexSelector >= s_config.maxCallbackGasLimits.length) {
            revert InvalidGasFlagValue(callbackGasLimitsIndexSelector);
        }
        uint32 maxCallbackGasLimit = s_config.maxCallbackGasLimits[callbackGasLimitsIndexSelector];
        if (callbackGasLimit > maxCallbackGasLimit) {
            revert GasLimitTooBig(maxCallbackGasLimit);
        }
    }

    function getAdminFee() external view returns (uint72) {
        return s_config.adminFee;
    }

    function getAllowListId() external view returns (bytes32) {
        return s_allowListId;
    }

    function setAllowListId(bytes32 allowListId) external onlyOwner {
        s_allowListId = allowListId;
    }

    /// @dev Used within FunctionsSubscriptions.sol
    function _getMaxConsumers() internal view returns (uint16) {
        return s_config.maxConsumersPerSubscription;
    }

    /// @dev Used within FunctionsSubscriptions.sol
    function _getSubscriptionDepositDetails() internal view returns (uint16, uint72) {
        return (s_config.subscriptionDepositMinimumRequests, s_config.subscriptionDepositJuels);
    }

    // ================================================================
    // |                      Request/Response                        |
    // ================================================================

    /// @notice Sets a request as in-flight
    /// @dev Only callable within the Router
    function _markRequestInFlight(address client, uint64 subscriptionId, uint96 estimatedTotalCostJuels) internal {
        // Earmark subscription funds
        s_subscriptions[subscriptionId].blockedBalance += estimatedTotalCostJuels;

        // Increment sent requests
        s_consumers[client][subscriptionId].initiatedRequests += 1;
    }

    /// @notice Moves funds from one subscription account to another.
    /// @dev Only callable by the Coordinator contract that is saved in the request commitment
    function _pay(uint64 subscriptionId, address client) internal returns (Receipt memory) {
        uint96 adminFee = 0.16 ether;
        uint96 callbackGasCostJuels = 0.0825 ether;
        uint96 totalCostJuels = 0.2425 ether;

        if (s_subscriptions[subscriptionId].balance < totalCostJuels) {
            revert InsufficientBalance(s_subscriptions[subscriptionId].balance);
        }

        // Charge the subscription
        s_subscriptions[subscriptionId].balance -= totalCostJuels;

        // Pay the DON's fees and gas reimbursement
        s_withdrawableTokens[msg.sender] += callbackGasCostJuels;

        // Pay out the administration fee
        s_withdrawableTokens[address(this)] += adminFee;

        // Increment finished requests
        s_consumers[client][subscriptionId].completedRequests += 1;

        return Receipt({callbackGasCostJuels: callbackGasCostJuels, totalCostJuels: totalCostJuels});
    }

    // ================================================================
    // |                           Requests                           |
    // ================================================================

    function sendRequest(
        uint64 subscriptionId,
        bytes calldata data,
        uint16 dataVersion,
        uint32 callbackGasLimit,
        bytes32 donId
    ) external returns (bytes32) {
        IFunctionsCoordinator coordinator = IFunctionsCoordinator(getContractById(donId));
        return _sendRequest(donId, coordinator, subscriptionId, data, dataVersion, callbackGasLimit);
    }

    function sendRequestToProposed(
        uint64 subscriptionId,
        bytes calldata data,
        uint16 dataVersion,
        uint32 callbackGasLimit,
        bytes32 donId
    ) external returns (bytes32) {
        return _sendRequest(
            donId, IFunctionsCoordinator(address(uint160(1234))), subscriptionId, data, dataVersion, callbackGasLimit
        );
    }

    function _sendRequest(
        bytes32 donId,
        IFunctionsCoordinator coordinator,
        uint64 subscriptionId,
        bytes memory data,
        uint16 dataVersion,
        uint32 callbackGasLimit
    ) private returns (bytes32) {
        _isExistingSubscription(subscriptionId);
        _isAllowedConsumer(msg.sender, subscriptionId);
        isValidCallbackGasLimit(subscriptionId, callbackGasLimit);

        if (data.length == 0) {
            revert EmptyRequestData();
        }

        Subscription memory subscription = getSubscription(subscriptionId);
        Consumer memory consumer = getConsumer(msg.sender, subscriptionId);
        consumer.initiatedRequests++;

        uint72 adminFee = s_config.adminFee;

        bytes32 requestId = bytes32(s_nextRequestId++);

        // // Forward request to DON
        // FunctionsResponse.Commitment memory commitment = coordinator.startRequest(
        //     FunctionsResponse.RequestMeta({
        //         requestingContract: msg.sender,
        //         data: data,
        //         subscriptionId: subscriptionId,
        //         dataVersion: dataVersion,
        //         flags: getFlags(subscriptionId),
        //         callbackGasLimit: callbackGasLimit,
        //         adminFee: adminFee,
        //         initiatedRequests: consumer.initiatedRequests,
        //         completedRequests: consumer.completedRequests,
        //         availableBalance: subscription.balance - subscription.blockedBalance,
        //         subscriptionOwner: subscription.owner
        //     })
        // );

        // Do not allow setting a comittment for a requestId that already exists
        if (s_requestCommitments[requestId] != bytes32(0)) {
            revert DuplicateRequestId(requestId);
        }

        FunctionsResponse.Commitment memory commitment = FunctionsResponse.Commitment({
            adminFee: adminFee,
            coordinator: address(coordinator),
            client: msg.sender,
            subscriptionId: subscriptionId,
            callbackGasLimit: callbackGasLimit,
            estimatedTotalCostJuels: 0,
            timeoutTimestamp: 0,
            requestId: requestId,
            donFee: 0,
            gasOverheadBeforeCallback: 0,
            gasOverheadAfterCallback: 0
        });

        // Store a commitment about the request
        s_requestCommitments[requestId] = keccak256(abi.encode(commitment));
        s_commitments[requestId] = commitment;

        emit RequestStart({
            requestId: requestId,
            donId: donId,
            subscriptionId: subscriptionId,
            subscriptionOwner: subscription.owner,
            requestingContract: msg.sender,
            requestInitiator: tx.origin,
            data: data,
            dataVersion: dataVersion,
            callbackGasLimit: callbackGasLimit,
            estimatedTotalCostJuels: 0
        });

        return requestId;
    }

    // ================================================================
    // |                           Responses                          |
    // ================================================================

    function fulfill() external returns (FunctionsResponse.FulfillResult resultCode, uint96) {
        _whenNotPaused();

        // mock, anyone can call
        // if (msg.sender != commitment.coordinator) {
        //     revert OnlyCallableFromCoordinator();
        // }

        bytes memory response = "";
        bytes memory err = "";
        address transmitter = msg.sender;

        bytes32 requestId = bytes32(s_nextRequestId);
        FunctionsResponse.Commitment memory commitment = s_commitments[requestId];

        if (requestId == commitment.requestId) {
            revert("Inconsistent RequestId");
        }

        {
            bytes32 commitmentHash = s_requestCommitments[commitment.requestId];

            if (commitmentHash == bytes32(0)) {
                resultCode = FunctionsResponse.FulfillResult.INVALID_REQUEST_ID;
                emit RequestNotProcessed(commitment.requestId, commitment.coordinator, transmitter, resultCode);
                return (resultCode, 0);
            }

            if (keccak256(abi.encode(commitment)) != commitmentHash) {
                resultCode = FunctionsResponse.FulfillResult.INVALID_COMMITMENT;
                emit RequestNotProcessed(commitment.requestId, commitment.coordinator, transmitter, resultCode);
                return (resultCode, 0);
            }
        }

        delete s_requestCommitments[commitment.requestId];

        CallbackResult memory result =
            _callback(commitment.requestId, response, err, commitment.callbackGasLimit, commitment.client);

        resultCode = result.success
            ? FunctionsResponse.FulfillResult.FULFILLED
            : FunctionsResponse.FulfillResult.USER_CALLBACK_ERROR;

        Receipt memory receipt = _pay(commitment.subscriptionId, commitment.client);

        emit RequestProcessed({
            requestId: commitment.requestId,
            subscriptionId: commitment.subscriptionId,
            totalCostJuels: receipt.totalCostJuels,
            transmitter: transmitter,
            resultCode: resultCode,
            response: response,
            err: err,
            callbackReturnData: result.returnData
        });

        delete s_commitments[requestId];
        return (resultCode, receipt.callbackGasCostJuels);
    }

    function _callback(
        bytes32 requestId,
        bytes memory response,
        bytes memory err,
        uint32 callbackGasLimit,
        address client
    ) internal virtual returns (CallbackResult memory) {
        bool destinationNoLongerExists;
        assembly {
            // solidity calls check that a contract actually exists at the destination, so we do the same
            destinationNoLongerExists := iszero(extcodesize(client))
        }
        if (destinationNoLongerExists) {
            // Return without attempting callback
            // The subscription will still be charged to reimburse transmitter's gas overhead
            return CallbackResult({success: false, gasUsed: 0, returnData: new bytes(0)});
        }

        bytes memory encodedCallback =
            abi.encodeWithSelector(s_config.handleOracleFulfillmentSelector, requestId, response, err);

        bool success;

        // allocate return data memory ahead of time
        bytes memory returnData = new bytes(MAX_CALLBACK_RETURN_BYTES);

        assembly {
            success := call(callbackGasLimit, client, 0, add(encodedCallback, 0x20), mload(encodedCallback), 0, 0)

            // limit our copy to MAX_CALLBACK_RETURN_BYTES bytes
            let toCopy := returndatasize()
            if gt(toCopy, MAX_CALLBACK_RETURN_BYTES) { toCopy := MAX_CALLBACK_RETURN_BYTES }
            // Store the length of the copied bytes
            mstore(returnData, toCopy)
            // copy the bytes from returnData[0:_toCopy]
            returndatacopy(add(returnData, 0x20), 0, toCopy)
        }

        return CallbackResult({success: success, gasUsed: 1000, returnData: returnData});
    }

    // ================================================================
    // |                        Route methods                         |
    // ================================================================

    function getContractById(bytes32 id) public view returns (address) {
        address currentImplementation = s_route[id];
        if (currentImplementation == address(0)) {
            revert RouteNotFound(id);
        }
        return currentImplementation;
    }

    function getProposedContractById(bytes32 id) public view returns (address) {
        // Iterations will not exceed MAX_PROPOSAL_SET_LENGTH
        for (uint8 i = 0; i < s_proposedContractSet.ids.length; ++i) {
            if (id == s_proposedContractSet.ids[i]) {
                return s_proposedContractSet.to[i];
            }
        }
        revert RouteNotFound(id);
    }

    // ================================================================
    // |                 Contract Proposal methods                    |
    // ================================================================

    function getProposedContractSet() external view returns (bytes32[] memory, address[] memory) {
        return (s_proposedContractSet.ids, s_proposedContractSet.to);
    }

    function proposeContractsUpdate(
        bytes32[] memory proposedContractSetIds,
        address[] memory proposedContractSetAddresses
    ) external onlyOwner {
        // IDs and addresses arrays must be of equal length and must not exceed the max proposal length
        uint256 idsArrayLength = proposedContractSetIds.length;
        if (idsArrayLength != proposedContractSetAddresses.length || idsArrayLength > MAX_PROPOSAL_SET_LENGTH) {
            revert InvalidProposal();
        }

        // NOTE: iterations of this loop will not exceed MAX_PROPOSAL_SET_LENGTH
        for (uint256 i = 0; i < idsArrayLength; ++i) {
            bytes32 id = proposedContractSetIds[i];
            address proposedContract = proposedContractSetAddresses[i];
            if (
                proposedContract == address(0) // The Proposed address must be a valid address
                    || s_route[id] == proposedContract // The Proposed address must point to a different address than what is currently set
            ) {
                revert InvalidProposal();
            }

            emit ContractProposed({
                proposedContractSetId: id,
                proposedContractSetFromAddress: s_route[id],
                proposedContractSetToAddress: proposedContract
            });
        }

        s_proposedContractSet = ContractProposalSet({ids: proposedContractSetIds, to: proposedContractSetAddresses});
    }

    function updateContracts() external onlyOwner {
        // Iterations will not exceed MAX_PROPOSAL_SET_LENGTH
        for (uint256 i = 0; i < s_proposedContractSet.ids.length; ++i) {
            bytes32 id = s_proposedContractSet.ids[i];
            address to = s_proposedContractSet.to[i];
            emit ContractUpdated({id: id, from: s_route[id], to: to});
            s_route[id] = to;
        }

        delete s_proposedContractSet;
    }

    // ================================================================
    // |                           Modifiers                          |
    // ================================================================
    // Favoring internal functions over actual modifiers to reduce contract size

    /// @dev Used within FunctionsSubscriptions.sol
    function _whenNotPaused() internal pure {}

    /// @dev Used within FunctionsSubscriptions.sol
    function _onlyRouterOwner() internal view {
        _validateOwnership();
    }

    /// @dev Used within FunctionsSubscriptions.sol
    function _onlySenderThatAcceptedToS() internal pure {}

    //
    // function pause() external  onlyOwner {
    //     _pause();
    // }

    //
    // function unpause() external  onlyOwner {
    //     _unpause();
    // }

    // ================================================================
    // |                      Owner methods                           |
    // ================================================================

    function ownerCancelSubscription(uint64 subscriptionId) external {
        _onlyRouterOwner();
        _isExistingSubscription(subscriptionId);
        _cancelSubscriptionHelper(subscriptionId, s_subscriptions[subscriptionId].owner, false);
    }

    function recoverFunds(address to) external {
        _onlyRouterOwner();
        uint256 externalBalance = i_linkToken.balanceOf(address(this));
        uint256 internalBalance = uint256(s_totalLinkBalance);
        if (internalBalance < externalBalance) {
            uint256 amount = externalBalance - internalBalance;
            i_linkToken.safeTransfer(to, amount);
            emit FundsRecovered(to, amount);
        }
        // If the balances are equal, nothing to be done.
    }

    // ================================================================
    // |                      Fund withdrawal                         |
    // ================================================================

    function oracleWithdraw(address recipient, uint96 amount) external {
        _whenNotPaused();

        if (amount == 0) {
            revert InvalidCalldata();
        }
        uint96 currentBalance = s_withdrawableTokens[msg.sender];
        if (currentBalance < amount) {
            revert InsufficientBalance(currentBalance);
        }
        s_withdrawableTokens[msg.sender] -= amount;
        s_totalLinkBalance -= amount;
        i_linkToken.safeTransfer(recipient, amount);
    }

    /// @notice Owner withdraw LINK earned through admin fees
    /// @notice If amount is 0 the full balance will be withdrawn
    /// @param recipient where to send the funds
    /// @param amount amount to withdraw
    function ownerWithdraw(address recipient, uint96 amount) external {
        _onlyRouterOwner();
        if (amount == 0) {
            amount = s_withdrawableTokens[address(this)];
        }
        uint96 currentBalance = s_withdrawableTokens[address(this)];
        if (currentBalance < amount) {
            revert InsufficientBalance(currentBalance);
        }
        s_withdrawableTokens[address(this)] -= amount;
        s_totalLinkBalance -= amount;

        i_linkToken.safeTransfer(recipient, amount);
    }

    // ================================================================
    // |                TransferAndCall Deposit helper                |
    // ================================================================

    // This function is to be invoked when using LINK.transferAndCall
    /// @dev Note to fund the subscription, use transferAndCall. For example
    /// @dev  LINKTOKEN.transferAndCall(
    /// @dev    address(ROUTER),
    /// @dev    amount,
    /// @dev    abi.encode(subscriptionId));
    function onTokenTransfer(address, /* sender */ uint256 amount, bytes calldata data) external {
        _whenNotPaused();
        if (msg.sender != address(i_linkToken)) {
            revert OnlyCallableFromLink();
        }
        if (data.length != 32) {
            revert InvalidCalldata();
        }
        uint64 subscriptionId = abi.decode(data, (uint64));
        if (s_subscriptions[subscriptionId].owner == address(0)) {
            revert InvalidSubscription();
        }
        // We do not check that the msg.sender is the subscription owner,
        // anyone can fund a subscription.
        uint256 oldBalance = s_subscriptions[subscriptionId].balance;
        s_subscriptions[subscriptionId].balance += uint96(amount);
        s_totalLinkBalance += uint96(amount);
        emit SubscriptionFunded(subscriptionId, oldBalance, oldBalance + amount);
    }

    // ================================================================
    // |                   Subscription management                   |
    // ================================================================

    function getTotalBalance() external view returns (uint96) {
        return s_totalLinkBalance;
    }

    function getSubscriptionCount() external view returns (uint64) {
        return s_currentSubscriptionId;
    }

    function getSubscription(uint64 subscriptionId) public view returns (Subscription memory) {
        _isExistingSubscription(subscriptionId);
        return s_subscriptions[subscriptionId];
    }

    function getSubscriptionsInRange(uint64 subscriptionIdStart, uint64 subscriptionIdEnd)
        external
        view
        returns (Subscription[] memory subscriptions)
    {
        if (
            subscriptionIdStart > subscriptionIdEnd || subscriptionIdEnd > s_currentSubscriptionId
                || s_currentSubscriptionId == 0
        ) {
            revert InvalidCalldata();
        }

        subscriptions = new Subscription[]((subscriptionIdEnd - subscriptionIdStart) + 1);
        for (uint256 i = 0; i <= subscriptionIdEnd - subscriptionIdStart; ++i) {
            subscriptions[i] = s_subscriptions[uint64(subscriptionIdStart + i)];
        }

        return subscriptions;
    }

    function getConsumer(address client, uint64 subscriptionId) public view returns (Consumer memory) {
        return s_consumers[client][subscriptionId];
    }

    /// @dev Used within this file & FunctionsRouter.sol
    function _isExistingSubscription(uint64 subscriptionId) internal view {
        if (s_subscriptions[subscriptionId].owner == address(0)) {
            revert InvalidSubscription();
        }
    }

    /// @dev Used within FunctionsRouter.sol
    function _isAllowedConsumer(address client, uint64 subscriptionId) internal view {
        if (!s_consumers[client][subscriptionId].allowed) {
            revert InvalidConsumer();
        }
    }

    /**
     * @notice fundSubscription allows funding a subscription with an arbitrary amount for testing.
     *
     * @param subscriptionId the subscription to fund
     * @param amount the amount to fund
     */
    function fundSubscription(uint64 subscriptionId, uint96 amount) public {
        if (s_subscriptions[subscriptionId].owner == address(0)) {
            revert InvalidSubscription();
        }

        // We do not check that the msg.sender is the subscription owner,
        // anyone can fund a subscription.
        uint256 oldBalance = s_subscriptions[subscriptionId].balance;
        s_subscriptions[subscriptionId].balance += uint96(amount);
        s_totalLinkBalance += uint96(amount);
        emit SubscriptionFunded(subscriptionId, oldBalance, oldBalance + amount);
    }

    function createSubscription() external returns (uint64 subscriptionId) {
        _whenNotPaused();
        _onlySenderThatAcceptedToS();

        subscriptionId = ++s_currentSubscriptionId;
        s_subscriptions[subscriptionId] = Subscription({
            balance: 0,
            blockedBalance: 0,
            owner: msg.sender,
            proposedOwner: address(0),
            consumers: new address[](0),
            flags: bytes32(0)
        });

        emit SubscriptionCreated(subscriptionId, msg.sender);

        return subscriptionId;
    }

    function createSubscriptionWithConsumer(address consumer) external returns (uint64 subscriptionId) {
        _whenNotPaused();
        _onlySenderThatAcceptedToS();

        subscriptionId = ++s_currentSubscriptionId;
        s_subscriptions[subscriptionId] = Subscription({
            balance: 0,
            blockedBalance: 0,
            owner: msg.sender,
            proposedOwner: address(0),
            consumers: new address[](0),
            flags: bytes32(0)
        });

        s_subscriptions[subscriptionId].consumers.push(consumer);
        s_consumers[consumer][subscriptionId].allowed = true;

        emit SubscriptionCreated(subscriptionId, msg.sender);
        emit SubscriptionConsumerAdded(subscriptionId, consumer);

        return subscriptionId;
    }

    function proposeSubscriptionOwnerTransfer(uint64 subscriptionId, address newOwner) external {
        _whenNotPaused();
        _onlySubscriptionOwner(subscriptionId);
        _onlySenderThatAcceptedToS();

        if (newOwner == address(0) || s_subscriptions[subscriptionId].proposedOwner == newOwner) {
            revert InvalidCalldata();
        }

        s_subscriptions[subscriptionId].proposedOwner = newOwner;
        emit SubscriptionOwnerTransferRequested(subscriptionId, msg.sender, newOwner);
    }

    function acceptSubscriptionOwnerTransfer(uint64 subscriptionId) external {
        _whenNotPaused();
        _onlySenderThatAcceptedToS();

        address previousOwner = s_subscriptions[subscriptionId].owner;
        address proposedOwner = s_subscriptions[subscriptionId].proposedOwner;
        if (proposedOwner != msg.sender) {
            revert MustBeProposedOwner(proposedOwner);
        }
        s_subscriptions[subscriptionId].owner = msg.sender;
        s_subscriptions[subscriptionId].proposedOwner = address(0);
        emit SubscriptionOwnerTransferred(subscriptionId, previousOwner, msg.sender);
    }

    function removeConsumer(uint64 subscriptionId, address consumer) external {
        _whenNotPaused();
        _onlySubscriptionOwner(subscriptionId);
        _onlySenderThatAcceptedToS();

        // Note bounded by config.maxConsumers
        address[] memory consumers = s_subscriptions[subscriptionId].consumers;
        for (uint256 i = 0; i < consumers.length; ++i) {
            if (consumers[i] == consumer) {
                // Storage write to preserve last element
                s_subscriptions[subscriptionId].consumers[i] = consumers[consumers.length - 1];
                // Storage remove last element
                s_subscriptions[subscriptionId].consumers.pop();
                break;
            }
        }
        delete s_consumers[consumer][subscriptionId];
        emit SubscriptionConsumerRemoved(subscriptionId, consumer);
    }

    function addConsumer(uint64 subscriptionId, address consumer) external {
        _whenNotPaused();
        _onlySubscriptionOwner(subscriptionId);
        _onlySenderThatAcceptedToS();

        // Already maxed, cannot add any more consumers.
        uint16 maximumConsumers = _getMaxConsumers();
        if (s_subscriptions[subscriptionId].consumers.length >= maximumConsumers) {
            revert TooManyConsumers(maximumConsumers);
        }
        if (s_consumers[consumer][subscriptionId].allowed) {
            // Idempotence - do nothing if already added.
            // Ensures uniqueness in s_subscriptions[subscriptionId].consumers.
            return;
        }

        s_consumers[consumer][subscriptionId].allowed = true;
        s_subscriptions[subscriptionId].consumers.push(consumer);

        emit SubscriptionConsumerAdded(subscriptionId, consumer);
    }

    function _cancelSubscriptionHelper(uint64 subscriptionId, address toAddress, bool checkDepositRefundability)
        private
    {
        Subscription memory subscription = s_subscriptions[subscriptionId];
        uint96 balance = subscription.balance;
        uint64 completedRequests = 0;

        // NOTE: loop iterations are bounded by config.maxConsumers
        // If no consumers, does nothing.
        for (uint256 i = 0; i < subscription.consumers.length; ++i) {
            address consumer = subscription.consumers[i];
            completedRequests += s_consumers[consumer][subscriptionId].completedRequests;
            delete s_consumers[consumer][subscriptionId];
        }
        delete s_subscriptions[subscriptionId];

        emit SubscriptionCanceled(subscriptionId, toAddress, balance);
    }

    function cancelSubscription(uint64 subscriptionId, address to) external {
        _whenNotPaused();
        _onlySubscriptionOwner(subscriptionId);
        _onlySenderThatAcceptedToS();

        _cancelSubscriptionHelper(subscriptionId, to, true);
    }

    function pendingRequestExists(uint64 subscriptionId) public pure returns (bool) {
        // mock has no pending requests
        return false;
    }

    function setFlags(uint64 subscriptionId, bytes32 flags) external {
        _onlyRouterOwner();
        _isExistingSubscription(subscriptionId);
        s_subscriptions[subscriptionId].flags = flags;
    }

    function getFlags(uint64 subscriptionId) public view returns (bytes32) {
        return s_subscriptions[subscriptionId].flags;
    }

    // ================================================================
    // |                        Request Timeout                       |
    // ================================================================

    function timeoutRequests(FunctionsResponse.Commitment[] calldata requestsToTimeoutByCommitment) external {}

    // ================================================================
    // |                         Modifiers                            |
    // ================================================================

    function _onlySubscriptionOwner(uint64 subscriptionId) internal view {
        address owner = s_subscriptions[subscriptionId].owner;
        if (owner == address(0)) {
            revert InvalidSubscription();
        }
        if (msg.sender != owner) {
            revert MustBeSubscriptionOwner();
        }
    }

    /// @dev Overriden in FunctionsRouter.sol
    // function _onlySenderThatAcceptedToS() internal virtual;

    /// @dev Overriden in FunctionsRouter.sol
    // function _onlyRouterOwner() internal virtual;

    /// @dev Overriden in FunctionsRouter.sol
    // function _whenNotPaused() internal virtual;

    function unpause() external {}

    function pause() external {}
}
