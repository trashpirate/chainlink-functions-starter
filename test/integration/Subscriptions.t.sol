// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {FunctionsRouterMock} from "test/mocks/FunctionsRouterMock.sol";
import {FunctionsRouter} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/FunctionsRouter.sol";

import {DeployFunctionsConsumer} from "script/DeployFunctionsConsumer.s.sol";
import {FunctionsConsumer} from "src/FunctionsConsumer.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "script/Subscriptions.s.sol";

contract SubscriptionsTest is Test {
    // configurations
    HelperConfig helperConfig;

    // helpers
    address functionsRouter;
    address link;
    bytes32 donID;
    uint64 subscriptionId;
    uint256 deployerKey;

    function setUp() external virtual {
        helperConfig = new HelperConfig();
        (functionsRouter, link, donID,, deployerKey) = helperConfig.activeNetworkConfig();
    }

    function test__CreateSubscription() public {
        CreateSubscription createSubscription = new CreateSubscription();
        subscriptionId = createSubscription.createSubscription(functionsRouter, deployerKey);

        FunctionsRouter.Subscription memory subscription =
            FunctionsRouter(functionsRouter).getSubscription(subscriptionId);
        assertEq(subscription.owner, 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
    }

    function test__FundSubscription() public {
        // create subscription
        CreateSubscription createSubscription = new CreateSubscription();
        subscriptionId = createSubscription.createSubscription(functionsRouter, deployerKey);

        // fund subscription
        FundSubscription fundSubscription = new FundSubscription();
        fundSubscription.fundSubscription(functionsRouter, subscriptionId, link, deployerKey);

        FunctionsRouterMock.Subscription memory sub =
            FunctionsRouterMock(functionsRouter).getSubscription(subscriptionId);

        assertGt(sub.balance, 0);
    }

    function test__AddConsumer() public {
        // create subscription
        CreateSubscription createSubscription = new CreateSubscription();
        subscriptionId = createSubscription.createSubscription(functionsRouter, deployerKey);

        // fund subscription
        FundSubscription fundSubscription = new FundSubscription();
        fundSubscription.fundSubscription(functionsRouter, subscriptionId, link, deployerKey);

        FunctionsConsumer consumer = new FunctionsConsumer(functionsRouter, subscriptionId, donID, "some code");

        // add consumer
        AddConsumer addConsumer = new AddConsumer();
        addConsumer.addConsumer(address(consumer), functionsRouter, subscriptionId, deployerKey);

        FunctionsRouterMock.Subscription memory sub =
            FunctionsRouterMock(functionsRouter).getSubscription(subscriptionId);
        assertEq(sub.consumers[0], address(consumer));
    }
}
