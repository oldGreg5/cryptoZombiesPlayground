// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {ZombieOwnership} from "../src/ZombieOwnership.sol";
import {ZombieHandler} from "./handlers/ZombieHandler.sol";

contract ZombieInvariantTest is Test {
    ZombieOwnership game;
    ZombieHandler handler;
    address gameOwner = makeAddr("gameOwner");

    function setUp() public {
        vm.prank(gameOwner);
        game = new ZombieOwnership();

        address[] memory actors = new address[](3);
        actors[0] = makeAddr("alice");
        actors[1] = makeAddr("bob");
        actors[2] = makeAddr("carol");

        handler = new ZombieHandler(game, actors);

        // the fuzzer may ONLY call the handler
        targetContract(address(handler));
    }

    function invariant_BalancesSumToTotalSupply() public view {
        uint256 sum;
        uint256 n = handler.actorCount();
        for (uint256 i; i < n; i++) {
            sum += game.balanceOf(handler.actors(i));
        }
        assertEq(sum, game.totalZombies(), "balances must sum to supply");
    }

    function invariant_AllDnaIsSixteenDigits() public view {
        uint256 n = game.totalZombies();
        for (uint256 i; i < n; i++) {
            (, uint256 dna,,,,) = game.zombies(i);
            assertLt(dna, 1e16, "dna must stay 16 digits");
        }
    }

    function invariant_ContractBalanceMatchesFees() public view {
        assertEq(
            address(game).balance,
            handler.ghost_feesPaid() - handler.ghost_withdrawn(),
            "contract ETH must equal fees in minus withdrawals out"
        );
    }

    function afterInvariant() public view {
        console.log("create     ", handler.calls("create"));
        console.log("create.ok  ", handler.calls("create.ok"));
        console.log("levelUp    ", handler.calls("levelUp"));
        console.log("levelUp.ok ", handler.calls("levelUp.ok"));
        console.log("transfer   ", handler.calls("transfer"));
        console.log("transfer.ok", handler.calls("transfer.ok"));
        console.log("attack     ", handler.calls("attack"));
        console.log("attack.ok  ", handler.calls("attack.ok"));
        console.log("withdraw   ", handler.calls("withdraw"));
        console.log("withdraw.ok", handler.calls("withdraw.ok"));
    }
}
