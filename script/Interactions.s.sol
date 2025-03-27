// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {FunctionsConsumer} from "src/FunctionsConsumer.sol";
import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol";

contract SendRequest is Script {
    function sendRequest(address consumer, uint256 deployerKey) public returns (bytes32) {
        console.log("---------------- SENDING REQEUEST ------------------");
        console.log("Sending Request on ChainId: ", block.chainid);
        console.log("Using Functions Consumer: ", consumer);

        if (block.chainid == 31337 || block.chainid == 1337) {
            vm.startBroadcast(deployerKey);
        } else {
            vm.startBroadcast();
        }

        string[] memory args = new string[](2);
        args[0] = "ipfs://bafybeic2a7jdsztni6jsnq2oarb3o5g7iuya5r4lcjfqi64rsucirdfobm/124";
        args[1] = "Color";

        bytes32 requestId = FunctionsConsumer(consumer).sendRequest(args);
        vm.stopBroadcast();
        console.log("Request Sent; Request ID: ");
        console.logBytes32(requestId);
        console.log("-------------------------------------------------------");
        return requestId;
    }

    function sendRequestUsingConfig(address consumer) public returns (bytes32) {
        HelperConfig helperConfig = new HelperConfig();
        (,,,, uint256 deployerKey) = helperConfig.activeNetworkConfig();

        return sendRequest(consumer, deployerKey);
    }

    function run() external returns (bytes32) {
        address consumer = DevOpsTools.get_most_recent_deployment("FunctionsConsumer", block.chainid);
        return sendRequestUsingConfig(consumer);
    }
}

contract GetLastResponse is Script {
    function getLastResponse(address consumer) public returns (bytes memory) {
        console.log("---------------- READING RESPONSE ------------------");
        console.log("Using Functions Consumer: ", consumer);

        vm.startBroadcast();
        bytes memory response = FunctionsConsumer(consumer).getLastResponse();
        vm.stopBroadcast();
        console.log("Response: ", string(response));
        console.log("-------------------------------------------------------");
        return response;
    }

    function run() external returns (bytes memory) {
        address consumer = DevOpsTools.get_most_recent_deployment("FunctionsConsumer", block.chainid);
        return getLastResponse(consumer);
    }
}
