// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./ZombieAttack.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract ZombieOwnership is ZombieAttack, ERC721 {
    constructor() ERC721("CryptoZombies", "ZOMBIE") {}

  mapping (uint => address) zombieApprovals;
}
