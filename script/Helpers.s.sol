// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";

contract CheckActiveNetworkId is Script {
    function run() external view {
        console.log("Chain ID: ", block.chainid);
    }
}

contract ReadCfNetworkConfig is Script {
    struct FunctionsConfig {
        string donID;
        address functionsRouter;
        address linkToken;
    }

    function run() external view {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/functions-toolkit/local-network/cf-network-config.json");
        string memory json = vm.readFile(path);
        bytes memory data = vm.parseJson(json);

        FunctionsConfig memory config = abi.decode(data, (FunctionsConfig));

        console.log("Link Token: ", config.linkToken);
        console.log("Functions Router: ", config.functionsRouter);
        console.log("DonID: ", config.donID);
    }
}
