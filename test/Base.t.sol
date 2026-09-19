// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ZombieOwnership} from "../src/ZombieOwnership.sol";
import {MockKittyContract} from "./mocks/KittyContract.sol";
import {ZombieFeeding} from "../src/ZombieFeeding.sol";

abstract contract BaseTest is Test {
    ZombieOwnership z;
    MockKittyContract kitty;
    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public virtual {
        vm.prank(owner); // owner is an EOA, not the test contract
        z = new ZombieOwnership();
        vm.deal(alice, 1 ether);
        vm.deal(bob, 1 ether);
        kitty = new MockKittyContract();
        vm.prank(owner);
        z.setKittyContractAddress(address(kitty));
    }

    function _spawnZombie(address who, string memory name) internal returns (uint256 id) {
        vm.prank(who);
        z.createRandomZombie(name);
        id = z.totalZombies() - 1;
    }
}
