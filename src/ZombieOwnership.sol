// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./ZombieAttack.sol";

contract ZombieOwnership is ZombieAttack {
    mapping(uint256 => address) zombieApprovals;
}
