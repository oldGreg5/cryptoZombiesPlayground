// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract ZombieFactory is Ownable, ERC721 {
    constructor() Ownable(msg.sender) ERC721("Zombie", "ZMB") {}

    event NewZombie(uint256 zombieId, string name, uint256 dna);
    event ZombieCreated(uint256 zombieId, address owner);

    uint256 dnaDigits = 16;
    uint256 dnaModulus = 10 ** dnaDigits;
    uint256 cooldownTime = 1 days;

    struct Zombie {
        string name;
        uint256 dna;
        uint32 level;
        uint32 readyTime;
        uint16 winCount;
        uint16 lossCount;
    }

    Zombie[] public zombies;

    mapping(address => uint256) ownerZombieCount;

    error ZombieBelowLevel(uint256 zombieId, uint32 required, uint32 actual);
    modifier aboveLevel(uint256 _level, uint256 _zombieId) {
        if (zombies[_zombieId].level < _level) {
            revert ZombieBelowLevel(_zombieId, uint32(_level), zombies[_zombieId].level);
        }
        _;
    }

    error NotZombieOwner(uint256 zombieId, address caller);
    modifier onlyOwnerOf(uint256 _zombieId) {
        if (msg.sender != ownerOf(_zombieId)) {
            revert NotZombieOwner(_zombieId, msg.sender);
        }
        _;
    }

    function _createZombie(string memory _name, uint256 _dna) internal {
        zombies.push(Zombie(_name, _dna, 1, uint32(block.timestamp + cooldownTime), 0, 0));
        uint256 id = zombies.length - 1;
        _mint(msg.sender, id);
        ownerZombieCount[msg.sender] = ownerZombieCount[msg.sender] + 1;
        emit NewZombie(id, _name, _dna);
        emit ZombieCreated(id, msg.sender);
    }

    function _generateRandomDna(string memory _str) private view returns (uint256) {
        uint256 rand = uint256(keccak256(abi.encodePacked(_str)));
        return rand % dnaModulus;
    }

    function createRandomZombie(string memory _name) public {
        require(ownerZombieCount[msg.sender] == 0);
        uint256 randDna = _generateRandomDna(_name);
        randDna = randDna - randDna % 100;
        _createZombie(_name, randDna);
    }
}
