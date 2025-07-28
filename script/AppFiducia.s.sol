// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {SafeSingletonFactory} from "./SafeSingletonFactory.sol";
import {AppFiducia} from "../src/test/AppFiducia.sol";

contract AppFiduciaScript is Script {
    AppFiducia public addFiducia;

    function setUp() public {}

    function run() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        uint256 delay = 30;

        addFiducia = AppFiducia(
            SafeSingletonFactory.deploy({
                salt: bytes32(0),
                code: abi.encodePacked(type(AppFiducia).creationCode, abi.encode(delay))
            })
        );

        vm.stopBroadcast();
    }
}
