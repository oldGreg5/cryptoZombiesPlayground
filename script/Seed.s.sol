// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ZombieOwnership} from "../src/ZombieOwnership.sol";

contract Seed is Script {
    function run() external {
        // 1. Set up our known test accounts
        uint256 pk0 = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        uint256 pk1 = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;

        // 2. Deploy the game as Account 0
        vm.startBroadcast(pk0);
        ZombieOwnership game = new ZombieOwnership();

        // 3. Mint Zombie 0 for Account 0 (Alice)
        game.createRandomZombie("Alice");
        vm.stopBroadcast();

        // 4. Mint Zombie 1 for Account 1 (Bob)
        vm.startBroadcast(pk1);
        game.createRandomZombie("Bob");
        vm.stopBroadcast();

        // 5. Fast-forward time by 1.5 days so both zombies clear their birth cooldown
        vm.warp(block.timestamp + 1.5 days);

        // 6. Output the deployed address for Playwright to consume
        console.log("Game deployed at:", address(game));

        // Write the address to a local JSON file (requires fs_permissions in foundry.toml)
        string memory json = vm.serializeAddress("deployment", "gameAddress", address(game));
        vm.writeJson(json, "./deployments/local.json");
    }
}
