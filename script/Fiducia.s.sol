// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {SafeSingletonFactory} from "./SafeSingletonFactory.sol";
import {Fiducia} from "../src/Fiducia.sol";

contract FiduciaScript is Script {
    Fiducia public fiducia;

    function setUp() public {}

    function run() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        uint256 delay = 3600;

        // Deploy the Fiducia contract using the SafeSingletonFactory
        fiducia = Fiducia(
            SafeSingletonFactory.deploy({
                salt: bytes32(0),
                code: abi.encodePacked(type(Fiducia).creationCode, abi.encode(delay))
            })
        );

        vm.stopBroadcast();
    }
}
