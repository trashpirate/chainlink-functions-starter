// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {FunctionsConsumer} from "src/FunctionsConsumer.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "./Subscriptions.s.sol";
import {FunctionsRouter} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsRouter.sol";
import {LinkToken} from "test/mocks/LinkToken.sol";
import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol";

contract DeployFunctionsConsumer is Script {
    uint96 public constant FUND_AMOUNT = 3 ether;

    function run() external returns (FunctionsConsumer, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        FunctionsConsumer consumer;
        if (block.chainid != 31337) {
            address contractAddress = DevOpsTools.get_most_recent_deployment("FunctionsConsumer", block.chainid);
            consumer = FunctionsConsumer(contractAddress);

            helperConfig.udpateSubscriptionId(consumer.getSubscriptionId());
        } else {
            string memory functionsCode = vm.readFile("functions-toolkit/source/code.js");
            console.log("Functions Code Length: %s", bytes(functionsCode).length);
            // console.log("Functions Code: %s", functionsCode);

            (address functionsRouter, address link, bytes32 donID, uint64 subscriptionId, uint256 deployerKey) =
                helperConfig.activeNetworkConfig();

            if (subscriptionId == 0) {
                // create subscription
                CreateSubscription createSubscription = new CreateSubscription();
                subscriptionId = createSubscription.createSubscription(functionsRouter, deployerKey);

                // fund subscription
                FundSubscription fundSubscription = new FundSubscription();
                fundSubscription.fundSubscription(functionsRouter, subscriptionId, link, deployerKey);
            }

            console.log("--------------------- DEPLOY CONSUMER --------------------");

            if (block.chainid == 31337 || block.chainid == 1337) {
                vm.startBroadcast(deployerKey);
            } else {
                vm.startBroadcast();
            }
            consumer = new FunctionsConsumer(functionsRouter, subscriptionId, donID, functionsCode);
            vm.stopBroadcast();
            console.log("Functions Consumer deployed at: %s", address(consumer));
            console.log("-------------------------------------------------------");

            // add consumer
            AddConsumer addConsumer = new AddConsumer();
            addConsumer.addConsumer(address(consumer), functionsRouter, subscriptionId, deployerKey);
        }

        return (consumer, helperConfig);
    }
}
