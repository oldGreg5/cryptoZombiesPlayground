// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ZombieOwnership} from "../src/ZombieOwnership.sol";

contract Deploy is Script {
    function run() external returns (ZombieOwnership game) {
        vm.startBroadcast();
        game = new ZombieOwnership();
        vm.stopBroadcast();
        console.log("ZombieOwnership deployed at", address(game));
    }
}
