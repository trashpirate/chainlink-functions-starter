// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {FunctionsRouterMock, IFunctionsSubscriptions} from "test/mocks/FunctionsRouterMock.sol";

import {DeployFunctionsBase} from "script/DeployFunctionsBase.s.sol";
import {FunctionsBase} from "src/FunctionsBase.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract TestScript is Test {
    // configurations
    HelperConfig helperConfig;
    HelperConfig.NetworkConfig networkConfig;

    // contracts
    DeployFunctionsBase deployer;
    FunctionsBase functionsBase;

    // helpers
    address USER = makeAddr("user");

    function setUp() external virtual {
        deployer = new DeployFunctionsBase();
        (functionsBase, helperConfig) = deployer.run();

        networkConfig = helperConfig.getActiveNetworkConfig();
    }

    function test__Deployment() public {
        IFunctionsSubscriptions.Subscription memory sub =
            FunctionsRouterMock(networkConfig.functionsRouter).getSubscription(functionsBase.getSubscriptionId());
        console.log("Subscription Owner: ", sub.owner);
    }
}
