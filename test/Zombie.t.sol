// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {BaseTest} from "./Base.t.sol";

contract ZombieUnitTest is BaseTest {
    function test_CreateZombie_SetsOwnerAndDnaFormat() public {
        uint256 id = _spawnZombie(alice, "Alice");
        (, uint256 dna,,,,) = z.zombies(id);
        assertEq(z.ownerOf(id), alice);
        assertLt(dna, 1e16);
        assertEq(dna % 100, 0);          // random zombies end in 00
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
        uint256 id = _spawnZombie(alice, "A");     // level 1
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
        (, , , uint32 readyTime,,) = z.zombies(id);
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
}