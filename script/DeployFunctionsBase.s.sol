// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {FunctionsBase} from "src/FunctionsBase.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {CreateSubscription, FundSubscription} from "./Subscriptions.s.sol";

contract DeployFunctionsBase is Script {
    function run() external returns (FunctionsBase, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();

        (
            address functionsRouter,
            address functionsCoordinator,
            address link,
            bytes32 donID,
            uint64 subscriptionId,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();

        if (subscriptionId == 0) {
            // create subscription
            CreateSubscription createSubscription = new CreateSubscription();
            subscriptionId = createSubscription.createSubscription(functionsRouter, deployerKey);

            // fund subscription
            FundSubscription fundSubscription = new FundSubscription();
            fundSubscription.fundSubscription(functionsRouter, subscriptionId, link, deployerKey);
        }

        vm.startBroadcast();
        FunctionsBase myContract = new FunctionsBase(functionsRouter, subscriptionId);
        vm.stopBroadcast();
        return (myContract, helperConfig);
    }
}
