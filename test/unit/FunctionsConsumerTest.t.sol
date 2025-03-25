// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {FunctionsRouterMock, FunctionsResponse} from "test/mocks/FunctionsRouterMock.sol";

import {DeployFunctionsConsumer} from "script/DeployFunctionsConsumer.s.sol";
import {FunctionsConsumer} from "src/FunctionsConsumer.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract FunctionsConsumerTest is Test {
    // configurations
    HelperConfig helperConfig;
    HelperConfig.NetworkConfig networkConfig;

    // contracts
    DeployFunctionsConsumer deployer;
    FunctionsConsumer consumer;
    FunctionsRouterMock router;

    // helpers
    address USER = makeAddr("user");

    function setUp() external virtual {
        deployer = new DeployFunctionsConsumer();
        (consumer, helperConfig) = deployer.run();

        networkConfig = helperConfig.getActiveNetworkConfig();

        router = FunctionsRouterMock(networkConfig.functionsRouter);
    }

    function test__Deployment() public view {
        assertEq(consumer.owner(), helperConfig.ANVIL_DEFAULT_ADDRESS());
        assertNotEq(consumer.getSubscriptionId(), 0);
        assertEq(consumer.getDonID(), networkConfig.donID);
        assertEq(consumer.getGasLimit(), 500_000);
        assertEq(consumer.getSource(), vm.readFile("assets/source.txt"));

        FunctionsRouterMock.Subscription memory sub =
            FunctionsRouterMock(networkConfig.functionsRouter).getSubscription(consumer.getSubscriptionId());
        assertEq(sub.owner, consumer.owner());
        console.log("Subscription Owner: ", sub.owner);
        console.log("Subscription Number of Consumers: ", sub.consumers.length);
    }

    function test__SendRequest() public {
        address owner = consumer.owner();

        vm.prank(owner);
        consumer.sendRequest();

        assertEq(router.getNextRequestId(), 2);
    }

    function test__FulfillRequest() public {
        FunctionsRouterMock.Subscription memory sub =
            FunctionsRouterMock(networkConfig.functionsRouter).getSubscription(consumer.getSubscriptionId());

        console.log("Subscription Balance before: ", sub.balance);
        address owner = consumer.owner();

        vm.prank(owner);
        consumer.sendRequest();

        bytes memory response = "WHITE";
        (FunctionsResponse.FulfillResult resultCode,) = router.fulfill(response);
        assertEq(uint256(resultCode), 0);

        sub = FunctionsRouterMock(networkConfig.functionsRouter).getSubscription(consumer.getSubscriptionId());
        console.log("Subscription Balance after: ", sub.balance);

        assertEq(consumer.getLastResponse(), response);
    }
}
