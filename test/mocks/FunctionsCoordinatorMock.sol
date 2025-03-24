// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IFunctionsCoordinator} from
    "@chainlink/contracts/src/v0.8/functions/v1_0_0/interfaces/IFunctionsCoordinator.sol";
import {FunctionsResponse} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsResponse.sol";
import {FunctionsBillingConfig} from "@chainlink/contracts/src/v0.8/functions/v1_3_0/FunctionsBilling.sol";

/// @title Mock Functions Coordinator for Local Testing
/// @notice Simplified version of FunctionsCoordinator for Foundry testing with identical interface
contract FunctionsCoordinatorMock is IFunctionsCoordinator {
    using FunctionsResponse for FunctionsResponse.RequestMeta;
    using FunctionsResponse for FunctionsResponse.Commitment;

    address public router; // Simulated router address
    address public owner; // Contract owner
    address public linkToNativeFeed; // Mocked price feed
    address public linkToUsdFeed; // Mocked price feed
    FunctionsBillingConfig public config; // Stored but unused in mock

    mapping(bytes32 => FunctionsResponse.Commitment) public commitments; // Store commitments by requestId

    event OracleRequest(
        bytes32 indexed requestId,
        address indexed requestingContract,
        address requestInitiator,
        uint64 subscriptionId,
        address subscriptionOwner,
        bytes data,
        uint16 dataVersion,
        bytes32 flags,
        uint64 callbackGasLimit,
        FunctionsResponse.Commitment commitment
    );
    event OracleResponse(bytes32 indexed requestId, address transmitter);

    constructor(
        address _router,
        FunctionsBillingConfig memory _config,
        address _linkToNativeFeed,
        address _linkToUsdFeed
    ) {
        router = _router;
        owner = msg.sender;
        config = _config;
        linkToNativeFeed = _linkToNativeFeed;
        linkToUsdFeed = _linkToUsdFeed;
    }

    modifier onlyRouter() {
        require(msg.sender == router, "Only router can call");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call");
        _;
    }

    // Matches original interface for request initiation
    function startRequest(FunctionsResponse.RequestMeta calldata request)
        external
        override
        onlyRouter
        returns (FunctionsResponse.Commitment memory commitment)
    {
        bytes32 requestId = keccak256(abi.encodePacked(msg.sender, block.timestamp, request.data));
        commitment = FunctionsResponse.Commitment({
            coordinator: address(this),
            client: request.requestingContract,
            subscriptionId: request.subscriptionId,
            callbackGasLimit: request.callbackGasLimit,
            estimatedTotalCostJuels: 0, // No billing in mock
            timeoutTimestamp: uint32(block.timestamp + 1 hours), // Arbitrary timeout
            requestId: requestId,
            donFee: 0, // No DON fee in mock
            gasOverheadBeforeCallback: 0,
            gasOverheadAfterCallback: 0,
            adminFee: 0 // No admin fee in mock
        });

        commitments[requestId] = commitment;

        emit OracleRequest(
            requestId,
            request.requestingContract,
            tx.origin,
            request.subscriptionId,
            request.subscriptionOwner,
            request.data,
            request.dataVersion,
            request.flags,
            request.callbackGasLimit,
            commitment
        );

        return commitment;
    }

    // Simulate fulfillment (callable by anyone for simplicity in testing)
    function fulfillRequest(bytes32 requestId, bytes calldata result, bytes calldata error) external {
        FunctionsResponse.Commitment memory commitment = commitments[requestId];
        require(commitment.client != address(0), "Unknown request ID");

        // Simulate callback to client
        (bool success,) = commitment.client.call(
            abi.encodeWithSignature("fulfillRequest(bytes32,bytes,bytes)", requestId, result, error)
        );

        if (success) {
            emit OracleResponse(requestId, msg.sender);
        }

        // Clean up after fulfillment
        delete commitments[requestId];
    }

    // Stubbed functions required by IFunctionsCoordinator
    function getThresholdPublicKey() external pure override returns (bytes memory) {
        return hex"1234";
    }

    function setThresholdPublicKey(bytes calldata thresholdPublicKey) external override onlyOwner {
        // No-op in mock
    }

    function getDONPublicKey() external pure override returns (bytes memory) {
        return hex"5678";
    }

    function setDONPublicKey(bytes calldata donPublicKey) external override onlyOwner {
        // No-op in mock
    }
}
