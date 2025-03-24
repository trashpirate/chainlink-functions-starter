// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {Contract} from "./../src/Contract.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract Deploy is Script {
    function run() external returns (Contract, HelperConfig) {
        HelperConfig config = new HelperConfig();

        (address initialOwner) = config.activeNetworkConfig();

        vm.startBroadcast();
        Contract myContract = new Contract(initialOwner);
        vm.stopBroadcast();
        return (myContract, config);
    }
}
