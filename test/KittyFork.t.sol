// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseTest} from "./Base.t.sol";
import {KittyInterface} from "../src/ZombieFeeding.sol";

contract KittyForkTest is BaseTest {
    address constant KITTY_CORE = 0x06012c8cf97BEaD5deAe237070F9587f8E7A266d;
    uint256 constant FORK_BLOCK = 20_000_000;

    function setUp() public override {
        vm.createSelectFork("mainnet", FORK_BLOCK); // fork FIRST
        super.setUp(); // then deploy onto it
        vm.prank(owner);
        z.setKittyContractAddress(KITTY_CORE);
    }

    function test_ForkIsLive() public view {
        assertEq(block.number, FORK_BLOCK);
        assertGt(KITTY_CORE.code.length, 0, "KittyCore has bytecode");
    }

    function test_FeedOnRealKitty() public {
        uint256 id = _spawnZombie(alice, "A");
        vm.warp(block.timestamp + 1 days);

        vm.prank(alice);
        z.feedOnKitty(id, 1); // kitty #1, Genesis

        assertEq(z.totalZombies(), 2, "a new zombie was spawned");
        (, uint256 dna,,,,) = z.zombies(1);
        assertEq(dna % 100, 99, "kitty offspring DNA ends in 99");
        assertLt(dna, 1e16);
        assertEq(z.ownerOf(1), alice);
    }

    function test_FeedRevertsIfKittyContractIsNotAContract() public {
        vm.prank(owner);
        z.setKittyContractAddress(makeAddr("not-a-contract"));
        uint256 id = _spawnZombie(alice, "A");
        vm.warp(block.timestamp + 1 days);
        vm.prank(alice);
        vm.expectRevert();
        z.feedOnKitty(id, 1);
    }

    function testFuzz_FeedOnAnyRealKitty(uint256 kittyId) public {
        kittyId = bound(kittyId, 1, 2_000_000); // real supply at that block
        uint256 id = _spawnZombie(alice, "A");
        vm.warp(block.timestamp + 1 days);

        vm.prank(alice);
        z.feedOnKitty(id, kittyId);

        (, uint256 dna,,,,) = z.zombies(1);
        assertLt(dna, 1e16);
        assertEq(dna % 100, 99);
    }

    function test_FeedOnRealKittyZero() public {
        uint256 id = _spawnZombie(alice, "A");
        vm.warp(block.timestamp + 1 days);

        vm.prank(alice);
        z.feedOnKitty(id, 0);

        assertEq(z.totalZombies(), 2, "a new zombie was spawned");
        (, uint256 dna,,,,) = z.zombies(1);
        assertEq(dna % 100, 99, "kitty offspring DNA ends in 99");
        assertLt(dna, 1e16);
        assertEq(z.ownerOf(1), alice);
    }

    function test_FeedOnRealKittyMax() public {
        uint256 id = _spawnZombie(alice, "A");
        vm.warp(block.timestamp + 1 days);

        vm.prank(alice);
        vm.expectRevert();
        z.feedOnKitty(id, type(uint256).max);
    }
}
