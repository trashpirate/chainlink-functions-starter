// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {FunctionsRouterMock} from "test/mocks/FunctionsRouterMock.sol";
import {FunctionsCoordinatorMock, FunctionsBillingConfig} from "test/mocks/FunctionsCoordinatorMock.sol";

import {LinkToken} from "test/mocks/LinkToken.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address functionsRouter;
        address functionsCoordinator;
        address link;
        bytes32 donID;
        uint64 subscriptionId;
        uint256 deployerKey;
    }

    NetworkConfig public activeNetworkConfig;

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/
    uint256 public constant ANVIL_DEFAULT_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address public constant ANVIL_DEFAULT_ADDRESS = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    address LINK_TO_NATIVE_FEED = 0xDC530D9457755926550b59e8ECcdaE7624181557;
    address LINK_TO_USD_FEED = 0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c;

    uint256 constant CONSTANT = 0;

    constructor() {
        if (block.chainid == 8453 || block.chainid == 123) {
            activeNetworkConfig = getMainnetConfig();
        } else if (block.chainid == 84532 || block.chainid == 84531) {
            activeNetworkConfig = getTestnetConfig();
        } else {
            activeNetworkConfig = getAnvilConfig();
        }
    }

    /*//////////////////////////////////////////////////////////////
                          CHAIN CONFIGURATIONS
    //////////////////////////////////////////////////////////////*/
    function getTestnetConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            functionsRouter: 0xf9B8fc078197181C841c296C876945aaa425B278,
            functionsCoordinator: 0xf9b8fC078197181C841C296C876945aAa425B271,
            link: 0x84b9B910527Ad5C03A9Ca831909E21e236EA7b06,
            donID: 0x66756e2d626173652d6d61696e6e65742d310000000000000000000000000000,
            subscriptionId: 0,
            deployerKey: vm.envUint("TESTNET_PRIVATE_KEY")
        });
    }

    function getMainnetConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            functionsRouter: 0xf9B8fc078197181C841c296C876945aaa425B278,
            functionsCoordinator: 0xf9b8fC078197181C841C296C876945aAa425B271,
            link: 0x404460C6A5EdE2D891e8297795264fDe62ADBB75,
            donID: 0x66756e2d626173652d7365706f6c69612d310000000000000000000000000000,
            subscriptionId: 0,
            deployerKey: uint256(0x0)
        });
    }

    function getAnvilConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.functionsCoordinator != address(0)) {
            return activeNetworkConfig;
        }

        uint32[] memory maxCallbackGasLimits = new uint32[](1);
        maxCallbackGasLimits[0] = 500000;

        vm.startBroadcast();

        // Deploy LINK token
        LinkToken linkToken = new LinkToken();

        // Fund with deployer LINK
        linkToken.transfer(ANVIL_DEFAULT_ADDRESS, 100 ether);

        // Deploy mock router
        FunctionsRouterMock router = new FunctionsRouterMock(
            address(linkToken),
            FunctionsRouterMock.Config({
                maxConsumersPerSubscription: 5,
                adminFee: 0,
                handleOracleFulfillmentSelector: bytes4(keccak256("fulfillRequest(bytes32,bytes,bytes)")),
                gasForCallExactCheck: 5000,
                maxCallbackGasLimits: maxCallbackGasLimits,
                subscriptionDepositMinimumRequests: 0,
                subscriptionDepositJuels: 0
            })
        );

        // Deploy mock coordinator
        FunctionsCoordinatorMock coordinator = new FunctionsCoordinatorMock(
            address(router),
            FunctionsBillingConfig({
                fulfillmentGasPriceOverEstimationBP: 10000,
                feedStalenessSeconds: 86400,
                gasOverheadBeforeCallback: 100000,
                gasOverheadAfterCallback: 100000,
                minimumEstimateGasPriceWei: 1000000000,
                maxSupportedRequestDataVersion: 1,
                fallbackUsdPerUnitLink: 1000000000000000000, // 1 LINK per USD
                fallbackUsdPerUnitLinkDecimals: 18,
                fallbackNativePerUnitLink: 5000000000000000, // 0.005 ETH per LINK
                requestTimeoutSeconds: 300,
                donFeeCentsUsd: 0,
                operationFeeCentsUsd: 0
            }),
            LINK_TO_NATIVE_FEED,
            LINK_TO_USD_FEED
        );
        vm.stopBroadcast();

        return NetworkConfig({
            functionsRouter: address(router),
            functionsCoordinator: address(coordinator),
            link: address(linkToken),
            donID: 0x66756e2d626173652d6d61696e6e65742d310000000000000000000000000000,
            subscriptionId: 0,
            deployerKey: ANVIL_DEFAULT_KEY
        });
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/
    function getActiveNetworkConfig() public view returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }
}
