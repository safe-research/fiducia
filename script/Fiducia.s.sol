// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Fiducia} from "../src/Fiducia.sol";

contract FiduciaScript is Script {
    Fiducia public fiducia;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        uint256 delay = 0; // Set the delay as needed

        fiducia = new Fiducia(delay);

        vm.stopBroadcast();
    }
}
