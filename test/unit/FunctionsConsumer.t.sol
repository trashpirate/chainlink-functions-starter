// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {FunctionsRouterMock, FunctionsResponse} from "test/mocks/FunctionsRouterMock.sol";
import {FunctionsRouter} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsRouter.sol";
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
    FunctionsRouter router;

    // helpers
    address USER = makeAddr("user");
    bytes response = "YELLOW";

    modifier onlyAnvil() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    function fulfilled() internal {
        if (block.chainid == 31337) {
            (FunctionsResponse.FulfillResult resultCode,) = FunctionsRouterMock(address(router)).fulfill(response);
            assertEq(uint256(resultCode), 0);
            console.log("Request Mock fulfilled.");
        }
    }

    function setUp() external virtual {
        deployer = new DeployFunctionsConsumer();
        (consumer, helperConfig) = deployer.run();

        networkConfig = helperConfig.getActiveNetworkConfig();

        router = FunctionsRouter(networkConfig.functionsRouter);
    }

    function test__Deployment() public view {
        assertEq(consumer.owner(), helperConfig.ANVIL_DEFAULT_ADDRESS());
        assertNotEq(consumer.getSubscriptionId(), 0);
        assertEq(consumer.getDonID(), networkConfig.donID);
        assertEq(consumer.getSource(), vm.readFile("functions-toolkit/source/code.js"));

        FunctionsRouter.Subscription memory sub =
            FunctionsRouter(networkConfig.functionsRouter).getSubscription(consumer.getSubscriptionId());
        assertEq(sub.owner, consumer.owner());
        console.log("Subscription Owner: ", sub.owner);
        console.log("Subscription Consumers:");
        for (uint256 i = 0; i < sub.consumers.length; i++) {
            console.log("%d: %s", i + 1, sub.consumers[i]);
        }
    }

    function test__SendRequest() public onlyAnvil {
        string[] memory args = new string[](2);
        args[0] = "ipfs://bafybeic2a7jdsztni6jsnq2oarb3o5g7iuya5r4lcjfqi64rsucirdfobm/21";
        args[1] = "Color";

        address owner = consumer.owner();

        vm.prank(owner);
        consumer.sendRequest(args);

        assertEq(router.pendingRequestExists(consumer.getSubscriptionId()), true);
    }

    function test__FulfillRequest() public onlyAnvil {
        string[] memory args = new string[](2);
        args[0] = "ipfs://bafybeic2a7jdsztni6jsnq2oarb3o5g7iuya5r4lcjfqi64rsucirdfobm/21";
        args[1] = "Color";

        FunctionsRouter.Subscription memory sub =
            FunctionsRouter(networkConfig.functionsRouter).getSubscription(consumer.getSubscriptionId());

        console.log("Subscription Balance before: ", sub.balance);
        address owner = consumer.owner();

        vm.prank(owner);
        consumer.sendRequest(args);

        fulfilled();

        sub = FunctionsRouter(networkConfig.functionsRouter).getSubscription(consumer.getSubscriptionId());
        console.log("Subscription Balance after: ", sub.balance);

        bytes memory lastResponse = consumer.getLastResponse();
        console.log("Last Response: ", string(lastResponse));

        console.log("Expected Response: ", string(response));

        assertEq(lastResponse, response);
    }
}
