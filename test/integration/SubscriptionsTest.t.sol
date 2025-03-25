// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {FunctionsRouterMock} from "test/mocks/FunctionsRouterMock.sol";

import {DeployFunctionsConsumer} from "script/DeployFunctionsConsumer.s.sol";
import {FunctionsConsumer} from "src/FunctionsConsumer.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract TestScript is Test {
    // configurations
    HelperConfig helperConfig;
    HelperConfig.NetworkConfig networkConfig;

    // contracts
    DeployFunctionsConsumer deployer;
    FunctionsConsumer functionsConsumer;

    // helpers
    address USER = makeAddr("user");

    function setUp() external virtual {
        deployer = new DeployFunctionsConsumer();
        (functionsConsumer, helperConfig) = deployer.run();

        networkConfig = helperConfig.getActiveNetworkConfig();
    }

    function test__Deployment() public {
        FunctionsRouterMock.Subscription memory sub =
            FunctionsRouterMock(networkConfig.functionsRouter).getSubscription(functionsConsumer.getSubscriptionId());
        console.log("Subscription Owner: ", sub.owner);
        console.log("Subscription Number of Consumbers: ", sub.consumers.length);
    }
}
