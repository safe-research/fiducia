// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Fiducia} from "../src/Fiducia.sol";

contract FiduciaTest is Test {
    Fiducia public fiducia;

    function setUp() public {
        fiducia = new Fiducia();
    }

    function test_demo() public view {
        // Example test function
        assertTrue(address(fiducia) != address(0), "Fiducia contract should be deployed");
    }
}
