// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {BaseTest} from "./Base.t.sol";
import "forge-std/console.sol";

contract ZombieUnitTest is BaseTest {
    function test_CreateZombie_SetsOwnerAndDnaFormat() public {
        uint256 id = _spawnZombie(alice, "Alice");
        (, uint256 dna,,,,) = z.zombies(id);
        assertEq(z.ownerOf(id), alice);
        assertLt(dna, 1e16);
        assertEq(dna % 100, 0); // random zombies end in 00
    }

    function test_CreateZombie_RevertsOnSecond() public {
        _spawnZombie(alice, "A");
        vm.prank(alice);
        vm.expectRevert();
        z.createRandomZombie("B");
    }

    function test_LevelUp_RequiresExactFee() public {
        uint256 id = _spawnZombie(alice, "A");
        vm.prank(alice);
        vm.expectRevert();
        z.levelUp{value: 0.002 ether}(id);

        vm.prank(alice);
        z.levelUp{value: 0.001 ether}(id);
        (,, uint32 level,,,) = z.zombies(id);
        assertEq(level, 2);
    }

    function test_ChangeName_GatedByLevel() public {
        uint256 id = _spawnZombie(alice, "A"); // level 1
        vm.prank(alice);
        vm.expectRevert();
        z.changeName(id, "New");

        z.levelUp{value: 0.001 ether}(id);
        (,, uint32 level,,,) = z.zombies(id);
        assertEq(level, 2);
        vm.prank(alice);
        z.changeName(id, "New");
    }

    function test_Withdraw_OnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        z.withdraw();
    }

    function test_Withdraw_SendsFeesToOwner() public {
        uint256 id = _spawnZombie(alice, "A");
        vm.prank(alice);
        z.levelUp{value: 0.001 ether}(id);
        vm.prank(owner);
        z.withdraw();
        assertEq(owner.balance, 0.001 ether);
        assertEq(address(z).balance, 0);
    }

    function test_Feed_CooldownBoundary() public {
        uint256 id = _spawnZombie(alice, "A");
        (,,, uint32 readyTime,,) = z.zombies(id);
        vm.warp(readyTime - 1);
        // Feed the zombie and trigger cooldown gate
        vm.prank(alice);
        vm.expectRevert();
        z.feedOnKitty(id, 1);
        // Feed the zombie and in cooldown boundary
        vm.warp(readyTime);
        vm.prank(alice);
        z.feedOnKitty(id, 1);
    }

    function testFuzz_DnaAlwaysValid(string memory name) public {
        uint256 id = _spawnZombie(alice, name);
        (, uint256 dna,,,,) = z.zombies(id);
        assertLt(dna, 1e16);
        assertEq(dna % 100, 0); // random zombies end in 00
    }

    function testFuzz_LevelUpRejectsWrongFee(uint256 wrongFee) public {
        wrongFee = bound(wrongFee, 0, 1 ether);
        vm.assume(wrongFee != 0.001 ether);
        uint256 id = _spawnZombie(alice, "A");
        vm.prank(alice);
        vm.expectRevert();
        z.levelUp{value: wrongFee}(id);
    }

    function test_OnlyOwnerOf_Reverts() public {
        vm.prank(alice);
        z.createRandomZombie("Alice"); // Spawns at level 1

        // Level up the zombie to 2 so it safely bypasses the aboveLevel modifier
        uint256 fee = z.getLevelUpFee();
        z.levelUp{value: fee}(0);

        // Now Bob tries to steal it
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSignature("NotZombieOwner(uint256,address)", 0, bob));
        z.changeName(0, "BobStoleIt");
    }

    function test_SetLevelUpFee() public {
        uint256 newFee = 0.005 ether;

        vm.prank(owner);
        z.setLevelUpFee(newFee);

        // Verify the state actually changed
        assertEq(z.getLevelUpFee(), newFee);
    }

    function test_GetZombiesByOwnerGasScaling() public {
        // Measure gas cost when the total supply is 1, 10, and 100
        for (uint256 n = 1; n <= 100; n++) {
            // Use a unique address for each iteration to bypass the 1-per-account rule
            address player = address(uint160(1000 + n));

            vm.prank(player);
            z.createRandomZombie("Spam");

            if (n == 1 || n == 10 || n == 100) {
                // Measure how much gas it takes to read Alice's array
                uint256 gasBefore = gasleft();
                z.getZombiesByOwner(alice);
                uint256 gasUsed = gasBefore - gasleft();

                console.log("Global Supply:", n, "| Gas Used:", gasUsed);
            }
        }
    }

    // function test_AboveLevel_Reverts() public {
    //     vm.prank(alice);
    //     z.createRandomZombie("Alice"); // Spawns at level 1

    //     vm.prank(alice);
    //     vm.expectRevert(abi.encodeWithSignature("ZombieBelowLevel(uint256,uint32,uint32)", 0, 2, 1));
    //     z.changeName(0, "NewName"); // Requires level 2
    // }

    // function test_SetLevelUpFee() public {
    //     uint256 newFee = 0.005 ether;
    //     z.setLevelUpFee(newFee);
    //     assertEq(z.getLevelUpFee(), newFee);
    // }

    // // --- GAS SCALING BUG PROOF ---

    // function test_GetZombiesByOwnerGasScaling() public {
    //     // Measure gas cost for 1, 10, and 100 zombies
    //     for (uint256 n = 1; n <= 100; n++) {
    //         // Use a unique address for each to bypass the 1-per-account rule
    //         address player = address(uint160(1000 + n));

    //         vm.prank(player);
    //         z.createRandomZombie("Spam");

    //         if (n == 1 || n == 10 || n == 100) {
    //             // Record how much gas is left before the call
    //             uint256 gasBefore = gasleft();

    //             z.getZombiesByOwner(alice);

    //             uint256 gasUsed = gasBefore - gasleft();
    //             console.log("Global Supply:", n, "| Gas Used:", gasUsed);
    //         }
    //     }
    // }
}
