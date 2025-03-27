// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {FunctionsRouterMock} from "test/mocks/FunctionsRouterMock.sol";
import {IFunctionsSubscriptions} from
    "@chainlink/contracts/src/v0.8/functions/v1_0_0/interfaces/IFunctionsSubscriptions.sol";
import {FunctionsRouter} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsRouter.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";
import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol";

contract CreateSubscription is Script {
    function createSubscriptionUsingConfig() public returns (uint64) {
        HelperConfig helperConfig = new HelperConfig();

        (address functionsRouter,,,, uint256 deployerKey) = helperConfig.activeNetworkConfig();

        return createSubscription(functionsRouter, deployerKey);
    }

    function createSubscription(address functionsRouter, uint256 deployerKey) public returns (uint64) {
        console.log("---------------- CREATE SUBSCRIPTION ------------------");
        console.log("Creating subscription on ChainId: ", block.chainid);
        console.log("Using Functions Router: ", functionsRouter);

        uint64 subId;
        if (block.chainid == 31337 || block.chainid == 1337) {
            vm.startBroadcast(deployerKey);
            subId = FunctionsRouter(functionsRouter).createSubscription();
            vm.stopBroadcast();
        } else {
            vm.startBroadcast();
            subId = FunctionsRouter(functionsRouter).createSubscription();
            vm.stopBroadcast();
        }
        console.log("Created Subscription with SubId: ", subId);
        console.log("-------------------------------------------------------");
        return subId;
    }

    function run() external returns (uint64) {
        return createSubscriptionUsingConfig();
    }
}

contract FundSubscription is Script {
    uint96 public constant FUND_AMOUNT = 3 ether;

    function fundSubscriptionConfig() public {
        HelperConfig helperConfig = new HelperConfig();

        (address functionsRouter, address link,, uint64 subId, uint256 deployerKey) = helperConfig.activeNetworkConfig();

        fundSubscription(functionsRouter, subId, link, deployerKey);
    }

    function fundSubscription(address functionsRouter, uint64 subId, address link, uint256 deployerKey) public {
        console.log("---------------- FUND SUBSCRIPTION ------------------");
        console.log("Funding subscription %d with: %d JUELS", subId, FUND_AMOUNT);

        if (block.chainid == 31337 || block.chainid == 1337) {
            vm.startBroadcast(deployerKey);
            LinkToken(link).transferAndCall(functionsRouter, FUND_AMOUNT, abi.encode(subId));
            vm.stopBroadcast();
        } else {
            vm.startBroadcast();
            LinkToken(link).transferAndCall(functionsRouter, FUND_AMOUNT, abi.encode(subId));
            vm.stopBroadcast();
        }

        console.log("-------------------------------------------------------");
    }

    function run() external {
        fundSubscriptionConfig();
    }
}

contract AddConsumer is Script {
    function addConsumer(address consumer, address functionsRouter, uint64 subId, uint256 deployerKey) public {
        console.log("--------------------- ADD CONSUMER --------------------");
        console.log("Adding Consumer contract: ", consumer);

        if (block.chainid == 31337 || block.chainid == 1337) {
            vm.startBroadcast(deployerKey);
            FunctionsRouter(functionsRouter).addConsumer(subId, consumer);
            vm.stopBroadcast();
        } else {
            vm.startBroadcast();
            FunctionsRouter(functionsRouter).addConsumer(subId, consumer);
            vm.stopBroadcast();
        }
        console.log("-------------------------------------------------------");
    }

    function addConsumerUsingConfig(address functionsConsumer) public {
        HelperConfig helperConfig = new HelperConfig();
        (address functionsRouter,,, uint64 subId, uint256 deployerKey) = helperConfig.activeNetworkConfig();

        addConsumer(functionsConsumer, functionsRouter, subId, deployerKey);
    }

    function run() external {
        address functionsConsumer = DevOpsTools.get_most_recent_deployment("FunctionsConsumer", block.chainid);
        addConsumerUsingConfig(functionsConsumer);
    }
}
