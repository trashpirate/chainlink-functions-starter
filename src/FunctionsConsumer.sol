// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/*//////////////////////////////////////////////////////////////
                                IMPORTS
//////////////////////////////////////////////////////////////*/
import {FunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";

/**
 * @title FunctionsConsumer
 * @author Nadina Oates
 * @notice Simple Chainlink Functions contract
 */
contract FunctionsConsumer is FunctionsClient, ConfirmedOwner {
    using FunctionsRequest for FunctionsRequest.Request;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint64 private immutable i_subId;
    uint32 private immutable i_gasLimit;
    bytes32 private immutable i_donID;
    string private i_source;

    bytes32 private s_lastRequestId;
    bytes private s_lastResponse;
    bytes private s_lastError;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event Response(bytes32 indexed requestId, bytes response, bytes err);
    event RequestRevertedWithErrorMsg(string reason);
    event RequestRevertedWithoutErrorMsg(bytes data);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error UnexpectedRequestID(bytes32 requestId);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(address router, uint64 subId, bytes32 donId, string memory source)
        FunctionsClient(router)
        ConfirmedOwner(msg.sender)
    {
        i_subId = subId;
        i_gasLimit = 300_000;
        i_donID = donId;
        i_source = source;
    }

    // receive / fallback functions

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Send a simple request
     */
    function sendRequest(string[] memory args) external onlyOwner returns (bytes32 requestId) {
        uint8 donHostedSecretsSlotID = 0;
        uint64 donHostedSecretsVersion = 2;
        bytes memory encryptedSecretsUrls = "";

        bytes[] memory bytesArgs;

        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(i_source);
        if (encryptedSecretsUrls.length > 0) {
            req.addSecretsReference(encryptedSecretsUrls);
        } else if (donHostedSecretsVersion > 0) {
            req.addDONHostedSecrets(donHostedSecretsSlotID, donHostedSecretsVersion);
        }
        if (args.length > 0) req.setArgs(args);
        if (bytesArgs.length > 0) req.setBytesArgs(bytesArgs);

        s_lastRequestId = _sendRequest(req.encodeCBOR(), i_subId, i_gasLimit, i_donID);
        emit RequestSent(requestId);

        return s_lastRequestId;
    }

    /**
     * @notice Send a pre-encoded CBOR request
     * @param request CBOR-encoded request data
     * @param subscriptionId Billing ID
     * @param gasLimit The maximum amount of gas the request can consume
     * @param donID ID of the job to be invoked
     * @return requestId The ID of the sent request
     */
    function sendRequestCBOR(bytes memory request, uint64 subscriptionId, uint32 gasLimit, bytes32 donID)
        external
        onlyOwner
        returns (bytes32 requestId)
    {
        s_lastRequestId = _sendRequest(request, subscriptionId, gasLimit, donID);
        return s_lastRequestId;
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Store latest result/error
     * @param requestId The request ID, returned by sendRequest()
     * @param response Aggregated response from the user code
     * @param err Aggregated error from the user code or from the execution pipeline
     * Either response or error parameter will be set, but never both
     */
    function fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err) internal override {
        if (s_lastRequestId != requestId) {
            revert UnexpectedRequestID(requestId);
        }
        s_lastResponse = response;
        s_lastError = err;
        emit Response(requestId, s_lastResponse, s_lastError);
    }

    /*//////////////////////////////////////////////////////////////
                           PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    function getLastResponse() public view returns (bytes memory) {
        return s_lastResponse;
    }

    function getSubscriptionId() public view returns (uint64) {
        return i_subId;
    }

    function getGasLimit() public view returns (uint32) {
        return i_gasLimit;
    }

    function getDonID() public view returns (bytes32) {
        return i_donID;
    }

    function getSource() public view returns (string memory) {
        return i_source;
    }
}
