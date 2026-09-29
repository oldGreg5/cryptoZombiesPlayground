// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ZombieOwnership} from "../../src/ZombieOwnership.sol";

contract ZombieHandler is Test {
    ZombieOwnership public game;
    address[] public actors;

    // "ghost variables" — our own bookkeeping, explained in section 7
    uint256 public ghost_feesPaid;
    uint256 public ghost_withdrawn;
    uint256 public ghost_attackCalls;

    constructor(ZombieOwnership _game, address[] memory _actors) {
        game = _game;
        actors = _actors;
    }

    mapping(string => uint256) public calls;

    modifier count(string memory key) {
        calls[key]++;
        _;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[bound(seed, 0, actors.length - 1)];
    }

    function create(uint256 actorSeed, string calldata name) external count("create") {
        address who = _actor(actorSeed);
        if (game.balanceOf(who) != 0) return;   // already has one — skip, don't revert
        vm.prank(who);
        game.createRandomZombie(name);
        calls["create.ok"]++;
    }

    function levelUp(uint256 idSeed) external count("levelUp") {
        uint256 n = game.totalZombies();
        if (n == 0) return;
        uint256 id = bound(idSeed, 0, n - 1);
        address who = game.ownerOf(id);

        uint256 fee = game.getLevelUpFee();
        vm.deal(who, fee);                 // make sure they can pay
        vm.prank(who);
        game.levelUp{value: fee}(id);

        ghost_feesPaid += fee;             // remember what went in
        calls["levelUp.ok"]++;
    }

    function transfer(uint256 idSeed, uint256 toSeed) external count("transfer") {
        uint256 n = game.totalZombies();
        if (n == 0) return;
        uint256 id = bound(idSeed, 0, n - 1);
        address from = game.ownerOf(id);
        address to = _actor(toSeed);
        if (to == from) return;
        vm.prank(from);
        game.transferFrom(from, to, id);
        calls["transfer.ok"]++;
    }

    function passTime(uint256 secs) external count("passTime") {
        vm.warp(block.timestamp + bound(secs, 0, 3 days));
    }

    function attack(uint256 idSeed, uint256 targetSeed) external count("attack") {
        uint256 n = game.totalZombies();
        if (n < 2) return;
        uint256 id = bound(idSeed, 0, n - 1);
        uint256 target = bound(targetSeed, 0, n - 2);
        if (target == id) return;                 // known bug 3 — excluded on purpose
        // make sure the zombie is ready to attack
        (, , , uint32 readyTime, , ) = game.zombies(id);
        if (readyTime > block.timestamp) vm.warp(readyTime);

        address who = game.ownerOf(id);
        vm.prank(who);
        game.attack(id, target);   // may revert on cooldown — that's fine
        ghost_attackCalls++;
        calls["attack.ok"]++;
    }

    function withdraw() external count("withdraw") {
        uint256 before = address(game).balance;
        vm.prank(game.owner());
        game.withdraw();
        ghost_withdrawn += before;
        calls["withdraw.ok"]++;
    }
}