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

/// @title Mock Functions Router for Local Testing
/// @notice Simplified version of FunctionsRouter for Foundry testing with identical interface
contract FunctionsRouterMock is IFunctionsRouter, IFunctionsSubscriptions, ConfirmedOwner {
    using FunctionsResponse for FunctionsResponse.RequestMeta;
    using FunctionsResponse for FunctionsResponse.Commitment;

    uint96 public immutable GAS_PRICE_LINK;
    uint16 public immutable MAX_CONSUMERS = 100;

    error DuplicateRequestId(bytes32 requestId);
    error InvalidSubscription();
    error InsufficientBalance();
    error MustBeSubOwner(address owner);
    error TooManyConsumers();
    error InvalidConsumer();
    error InvalidRandomWords();
    error Reentrant();

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

    event RequestNotProcessed(
        bytes32 indexed requestId, address coordinator, address transmitter, FunctionsResponse.FulfillResult resultCode
    );

    event SubscriptionCreated(uint64 indexed subId, address owner);
    event SubscriptionFunded(uint64 indexed subId, uint256 oldBalance, uint256 newBalance);
    event SubscriptionCanceled(uint64 indexed subId, address to, uint256 amount);
    event ConsumerAdded(uint64 indexed subId, address consumer);
    event ConsumerRemoved(uint64 indexed subId, address consumer);
    event ConfigSet();

    IERC20 public immutable linkToken; // LINK token address

    // Config state (stored but mostly unused in mock)
    struct Config {
        uint16 maxConsumersPerSubscription;
        uint72 adminFee;
        bytes4 handleOracleFulfillmentSelector;
        uint16 gasForCallExactCheck;
        uint32[] maxCallbackGasLimits;
        uint16 subscriptionDepositMinimumRequests;
        uint72 subscriptionDepositJuels;
    }

    Config private s_config;
    uint64 internal s_currentSubId; // Tracks subscription IDs
    uint256 internal s_nextRequestId = 1;

    // Subscription state
    // struct Subscription {
    //     uint96 balance; // ═════════╗ Common LINK balance that is controlled by the Router to be used for all consumer requests.
    //     address owner; // ══════════╝ The owner can fund/withdraw/cancel the subscription.
    //     uint96 blockedBalance; // ══╗ LINK balance that is reserved to pay for pending consumer requests.
    //     address proposedOwner; // ══╝ For safely transferring sub ownership.
    //     address[] consumers; // ════╸ Client contracts that can use the subscription
    //     bytes32 flags; // ══════════╸ Per-subscription flags
    // }
    mapping(uint64 => Subscription) internal s_subscriptions;
    mapping(address consumer => mapping(uint64 subscriptionId => Consumer)) private s_consumers;
    mapping(bytes32 requestId => bytes32 commitmentHash) internal s_requestCommitments;
    // Route state
    mapping(bytes32 => address) private s_route; // DON ID to coordinator address
    bytes32 private s_allowListId; // Mocked allow list ID (unused)

    modifier _onlySubscriptionOwner(uint64 _subId) {
        address owner = s_subscriptions[_subId].owner;
        if (owner == address(0)) {
            revert InvalidSubscription();
        }
        if (msg.sender != owner) {
            revert MustBeSubOwner(owner);
        }
        _;
    }

    constructor(address _linkToken, Config memory config) ConfirmedOwner(msg.sender) {
        linkToken = IERC20(_linkToken);
        setConfig(config);
        s_currentSubId = 0; // Start at 0, first subscription will be 1
    }

    /**
     * @notice Sets the configuration of the vrfv2 mock coordinator
     */
    function setConfig(Config memory config) public onlyOwner {
        s_config = config;
        emit ConfigSet();
    }

    // Subscription Management
    function createSubscription() public returns (uint64) {
        s_currentSubId++;
        uint64 subId = s_currentSubId;

        s_subscriptions[subId] = Subscription({
            balance: 0,
            owner: msg.sender,
            blockedBalance: 0,
            proposedOwner: msg.sender,
            consumers: new address[](0),
            flags: ""
        });
        emit SubscriptionCreated(s_currentSubId, msg.sender);
        return subId;
    }

    function createSubscriptionWithConsumer(address consumer) external returns (uint64 subscriptionId) {
        subscriptionId = createSubscription();
        addConsumer(subscriptionId, consumer);
        return subscriptionId;
    }

    function fundSubscription(uint64 _subId, uint256 _amount) external {
        if (s_subscriptions[_subId].owner == address(0)) {
            revert InvalidSubscription();
        }
        uint96 oldBalance = s_subscriptions[_subId].balance;
        s_subscriptions[_subId].balance += uint96(_amount);
        emit SubscriptionFunded(_subId, oldBalance, oldBalance + _amount);
    }

    function ownerCancelSubscription(uint64 _subId, address _to) external _onlySubscriptionOwner(_subId) {
        emit SubscriptionCanceled(_subId, _to, s_subscriptions[_subId].balance);
        delete (s_subscriptions[_subId]);
    }

    function ownerCancelSubscription(uint64 subscriptionId) external _onlySubscriptionOwner(subscriptionId) {
        emit SubscriptionCanceled(subscriptionId, address(0), s_subscriptions[subscriptionId].balance);
        delete s_subscriptions[subscriptionId];
    }

    function cancelSubscription(uint64 _subId, address _to) external override _onlySubscriptionOwner(_subId) {
        emit SubscriptionCanceled(_subId, _to, s_subscriptions[_subId].balance);
        delete (s_subscriptions[_subId]);
    }

    function proposeSubscriptionOwnerTransfer(uint64 subscriptionId, address newOwner) external override {
        s_subscriptions[subscriptionId].proposedOwner = newOwner;
    }

    function acceptSubscriptionOwnerTransfer(uint64 subscriptionId) external {
        Subscription storage sub = s_subscriptions[subscriptionId];
        require(sub.proposedOwner == msg.sender, "MustBeProposedOwner");
        sub.owner = msg.sender;
        sub.proposedOwner = address(0);
    }

    function getSubscriptionsInRange(uint64 subscriptionIdStart, uint64 subscriptionIdEnd)
        external
        view
        returns (Subscription[] memory)
    {}

    function getSubscriptionCount() external view returns (uint64) {
        return s_currentSubId;
    }

    function getSubscription(uint64 subscriptionId) external view returns (Subscription memory) {
        Subscription storage sub = s_subscriptions[subscriptionId];
        return sub;
    }

    function getFlags(uint64 subscriptionId) external view returns (bytes32) {
        Subscription memory sub = s_subscriptions[subscriptionId];
        return sub.flags;
    }

    function getConsumer(address client, uint64 subscriptionId) external view returns (Consumer memory) {
        return s_consumers[client][subscriptionId];
    }

    function addConsumer(uint64 _subId, address _consumer) public _onlySubscriptionOwner(_subId) {
        Subscription storage sub = s_subscriptions[_subId];

        if (sub.consumers.length == s_config.maxConsumersPerSubscription) {
            revert TooManyConsumers();
        }

        if (s_consumers[_consumer][_subId].allowed) {
            // Idempotence - do nothing if already added.
            // Ensures uniqueness in s_subscriptions[subscriptionId].consumers.
            return;
        }

        sub.consumers.push(_consumer);
        emit ConsumerAdded(_subId, _consumer);
    }

    function removeConsumer(uint64 _subId, address _consumer) external override _onlySubscriptionOwner(_subId) {
        Consumer memory consumerData = s_consumers[_consumer][_subId];
        _isAllowedConsumer(_consumer, _subId);

        Subscription storage sub = s_subscriptions[_subId];
        address[] storage consumers = sub.consumers;
        for (uint256 i = 0; i < consumers.length; i++) {
            if (consumers[i] == _consumer) {
                address last = consumers[consumers.length - 1];
                consumers[i] = last;
                consumers.pop();
                break;
            }
        }
        delete s_consumers[_consumer][_subId];
        emit ConsumerRemoved(_subId, _consumer);
    }

    // Router Functions
    function sendRequest(
        uint64 subscriptionId,
        bytes calldata data,
        uint16 dataVersion,
        uint32 callbackGasLimit,
        bytes32 donId
    ) public override returns (bytes32) {
        IFunctionsCoordinator coordinator = IFunctionsCoordinator(getContractById(donId));
        return _sendRequest(donId, coordinator, subscriptionId, data, dataVersion, callbackGasLimit);
    }

    function sendRequestToProposed(
        uint64 subscriptionId,
        bytes calldata data,
        uint16 dataVersion,
        uint32 callbackGasLimit,
        bytes32 donId
    ) external override returns (bytes32) {
        IFunctionsCoordinator coordinator = IFunctionsCoordinator(getContractById(donId));
        return _sendRequest(donId, coordinator, subscriptionId, data, dataVersion, callbackGasLimit);
    }

    function _sendRequest(
        bytes32 donId,
        IFunctionsCoordinator coordinator,
        uint64 subscriptionId,
        bytes memory data,
        uint16 dataVersion,
        uint32 callbackGasLimit
    ) private returns (bytes32) {
        bytes32 requestId = bytes32(s_nextRequestId++);

        // Do not allow setting a comittment for a requestId that already exists
        if (s_requestCommitments[requestId] != bytes32(0)) {
            revert DuplicateRequestId(requestId);
        }

        s_requestCommitments[requestId] = keccak256(
            abi.encode(
                FunctionsResponse.Commitment({
                    adminFee: 0,
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
                })
            )
        );

        emit RequestStart(
            requestId,
            donId,
            subscriptionId,
            s_subscriptions[subscriptionId].owner,
            msg.sender,
            tx.origin,
            data,
            dataVersion,
            callbackGasLimit,
            0 // No cost estimation in mock
        );

        return requestId;
    }

    function fulfill(
        bytes memory response,
        bytes memory err,
        uint96 juelsPerGas,
        uint96 costWithoutCallback,
        address transmitter,
        FunctionsResponse.Commitment memory commitment
    ) external override returns (FunctionsResponse.FulfillResult, uint96) {
        require(msg.sender == commitment.coordinator, "OnlyCallableFromCoordinator");
        IFunctionsSubscriptions.Subscription storage sub = s_subscriptions[commitment.subscriptionId];
        require(sub.owner != address(0), "Invalid subscription");

        // Mock fulfillment: just call the client
        (bool success,) = commitment.client.call(
            abi.encodeWithSignature("fulfillRequest(bytes32,bytes,bytes)", commitment.requestId, response, err)
        );

        FunctionsResponse.FulfillResult resultCode =
            success ? FunctionsResponse.FulfillResult.FULFILLED : FunctionsResponse.FulfillResult.USER_CALLBACK_ERROR;

        return (resultCode, 0); // No gas cost tracking in mock

        delete s_requestCommitments[commitment.requestId];
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

    // Config Functions
    function getConfig() external view returns (Config memory) {
        return s_config;
    }

    function updateConfig(Config memory config) public onlyOwner {
        s_config = config;
    }

    function getAdminFee() external view override returns (uint72) {
        return s_config.adminFee;
    }

    function getAllowListId() external view override returns (bytes32) {
        return s_allowListId;
    }

    function setAllowListId(bytes32 allowListId) external override onlyOwner {
        s_allowListId = allowListId;
    }

    function isValidCallbackGasLimit(uint64 subscriptionId, uint32 callbackGasLimit) public view override {
        // Simplified: just check against first max limit
        if (s_config.maxCallbackGasLimits.length > 0 && callbackGasLimit > s_config.maxCallbackGasLimits[0]) {
            revert("GasLimitTooBig");
        }
    }

    function getContractById(bytes32 id) public view override returns (address) {
        address coordinator = s_route[id];
        require(coordinator != address(0), "RouteNotFound");
        return coordinator;
    }

    function getProposedContractById(bytes32 id) public view override returns (address) {
        return getContractById(id); // Simplified: no proposal in mock
    }

    function getProposedContractSet() external pure override returns (bytes32[] memory, address[] memory) {
        bytes32[] memory ids = new bytes32[](0);
        address[] memory to = new address[](0);
        return (ids, to); // Simplified: no proposal in mock
    }

    function proposeContractsUpdate(
        bytes32[] memory proposedContractSetIds,
        address[] memory proposedContractSetAddresses
    ) external override onlyOwner {
        require(proposedContractSetIds.length == proposedContractSetAddresses.length, "InvalidProposal");
        for (uint256 i = 0; i < proposedContractSetIds.length; i++) {
            s_route[proposedContractSetIds[i]] = proposedContractSetAddresses[i];
        }
    }

    function setFlags(uint64 subscriptionId, bytes32 flags) external override {
        s_subscriptions[subscriptionId].flags = flags;
    }

    function pendingRequestExists(uint64 subscriptionId) external pure returns (bool) {
        return false;
    }

    function getTotalBalance() external view returns (uint96) {
        return uint96(linkToken.balanceOf(address(this)));
    }

    function timeoutRequests(FunctionsResponse.Commitment[] calldata requestsToTimeoutByCommitment) external override {
        // No-op in mock
    }

    function recoverFunds(address to) external override onlyOwner {
        // No-op in mock
    }

    function pause() external override onlyOwner {
        // No-op in mock
    }

    function unpause() external override onlyOwner {
        // No-op in mock
    }

    function updateContracts() external override onlyOwner {
        // No-op in mock
    }

    function oracleWithdraw(address recipient, uint96 amount) external override {
        // No-op in mock
    }
}
