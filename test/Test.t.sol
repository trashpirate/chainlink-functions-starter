// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";

contract TestScript is Test {
    function setUp() external virtual {}

    function test__test() public {
        console.log("This is a test");
    }
}
