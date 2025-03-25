// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {FunctionsConsumer} from "src/FunctionsConsumer.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "./Subscriptions.s.sol";

contract DeployFunctionsConsumer is Script {
    function run() external returns (FunctionsConsumer, HelperConfig) {
        string memory functionsCode = vm.readFile("assets/source.txt");

        HelperConfig helperConfig = new HelperConfig();

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

        vm.startBroadcast();
        FunctionsConsumer consumer = new FunctionsConsumer(functionsRouter, subscriptionId, donID, functionsCode);
        vm.stopBroadcast();

        // add consumer
        AddConsumer addConsumer = new AddConsumer();
        addConsumer.addConsumer(address(consumer), functionsRouter, subscriptionId, deployerKey);

        return (consumer, helperConfig);
    }
}
