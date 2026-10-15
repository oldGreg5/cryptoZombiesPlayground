# Findings

Defects and observations from testing the ported CryptoZombies contracts.

Each entry records how it was found, because the method matters as much as the
finding: a bug found by a technique can be found again in other code, while a bug
found by luck cannot.

Severity is assessed against the contract's own stated rules (one zombie per
player, cooldowns between actions, fees as the only revenue) and against what an
adversarial player could actually extract. These are tutorial contracts with no
real value at stake; severity is relative to the system as specified, not an
absolute risk rating.

<!-- TODO: replace any [TODO] below with your measured values, and correct the
     Status column where it doesn't match what you ended up doing. -->

| ID | Title | Severity | Status |
|---|---|---|---|
| [BUG-01](#bug-01) | Dual ownership accounting after ERC-721 port | High | Fixed |
| [BUG-02](#bug-02) | Randomness is predictable and the outcome is revertible | High | Documented |
| [BUG-03](#bug-03) | Cooldown enforced on one branch of `attack` only | Medium | Fixed |
| [BUG-04](#bug-04) | Self-attack aliases storage; owner-vs-owner attack is free levelling | Medium | Fixed + spec question |
| [BUG-05](#bug-05) | `getZombiesByOwner` is O(total supply) | Low–Medium | Documented |
| [BUG-06](#bug-06) | `winCount` overflow permanently bricks a zombie | Low | Documented |
| [BUG-07](#bug-07) | Win probability is 71%, not 70% | Low | Fixed |
| [OBS-01](#obs-01) | No `Attack` event — combat is invisible to a front end | Observation | Raised |
| [OBS-02](#obs-02) | `setKittyContractAddress` accepts a non-contract address | Observation | Raised |

---

## BUG-01

### Dual ownership accounting after ERC-721 port

**Severity:** High · **Status:** Fixed · **Found by:** invariant campaign with
`fail_on_revert = true`

#### Description

The port inherits OpenZeppelin's `ERC721`, which tracks ownership in `_balances`
and `_owners`, but kept the tutorial's own `ownerZombieCount` mapping. Two sources
of truth for one fact.

`createRandomZombie` reads the legacy mapping:

```solidity
require(ownerZombieCount[msg.sender] == 0);
```

`transferFrom` goes through OZ's `_update`, which maintains OZ's bookkeeping and
knows nothing about the legacy mapping. After any transfer the two diverge, and
they never reconverge.

#### Impact

Both directions are exploitable:

- **Sender is permanently locked out.** After transferring their zombie away, the
  sender's `ownerZombieCount` is still 1 while `balanceOf` is 0. They can never
  create another zombie. A permanent denial of service triggered by using a
  feature the contract advertises.
- **Receiver gets a free extra zombie.** The receiver holds a zombie while their
  legacy count is still 0, so `createRandomZombie` succeeds and they end up with
  two. This defeats the one-zombie-per-player rule, which is the game's core
  economic constraint, and bypasses `levelUpFee` — the contract's only revenue.
  Round-tripping a zombie between two accounts mints a free zombie on every hop.

#### Reproduction

```
1. alice: createRandomZombie("A")        → owns zombie 0
2. alice: transferFrom(alice, bob, 0)    → bob owns zombie 0
3. bob:   createRandomZombie("B")        → SUCCEEDS; bob now owns 2
4. alice: createRandomZombie("A2")       → REVERTS; alice owns 0 and is stuck
```

#### How it was found

The invariant campaign reported a clean pass with 380 reverts across 12,800 calls
while `fail_on_revert = false`. Those reverts were invisible — a run where
everything bounced looked identical to a run that passed.

Turning on `fail_on_revert = true` converted them into a failure. The trace showed
all reverts came from exactly one place (`create`), and only after a transfer had
occurred. The handler's own guard read `balanceOf(carol) == 0` and allowed the
call; the contract then reverted. Handler and contract disagreed about who owned
what, which pointed straight at dual accounting.

The reverting call cost 24,807 gas — a `require` failing immediately, not deep
logic. Gas is a useful diagnostic here.

#### Evidence

```
[52634] ZombieHandler::create(2, "...")
  ├─ [2931] ZombieOwnership::balanceOf(carol) [staticcall]
  │   └─ ← [Return] 0
  ├─ [0] VM::prank(carol)
  ├─ [24807] ZombieOwnership::createRandomZombie("...")
  │   └─ ← [Revert] EvmError: Revert
  └─ ← [Revert] EvmError: Revert
```

#### Fix

Removed `ownerZombieCount` and `zombieToOwner` entirely; OZ's `_balances` and
`_owners` are now the single source of truth.

```diff
- mapping(uint => address) public zombieToOwner;
- mapping(address => uint) ownerZombieCount;

  function createRandomZombie(string memory _name) public {
-     require(ownerZombieCount[msg.sender] == 0);
+     require(balanceOf(msg.sender) == 0, "one zombie per player");
```

Every remaining read of the legacy mappings was replaced with `balanceOf` or
`ownerOf`. `getZombiesByOwner` in `ZombieHelper` was the other significant
consumer and would otherwise have returned wrong-sized arrays after any transfer —
the same defect in a different place.

#### Regression tests

- `test_TransferAllowsReceiverToMintExtraZombie`
- `test_TransferDoesNotLockOutSender`

Both confirmed failing before the fix, passing after. The invariant campaign now
runs 12,800 calls with 0 reverts.

#### Note

This is a defect the *port itself* introduced, not one inherited from the tutorial.
Worth recording separately: migrating to a library that owns state you were
previously tracking by hand is a standard source of this bug class, and the symptom
(silent divergence rather than an immediate error) is why it survives review.

---

## BUG-02

### Randomness is predictable and the outcome is revertible

**Severity:** High · **Status:** Documented — not fixed · **Found by:** code review

#### Description

```solidity
uint randNonce = 0;

function randMod(uint _modulus) internal returns (uint) {
    randNonce++;
    return uint(keccak256(abi.encodePacked(block.timestamp, msg.sender, randNonce))) % _modulus;
}
```

`keccak256` is deterministic, so the output is only as unpredictable as its inputs.
None of the three are secret:

| Input | Who knows it before the transaction |
|---|---|
| `block.timestamp` | Predictable — slots are 12 seconds apart and timestamps are slot-aligned |
| `msg.sender` | The attacker's own address |
| `randNonce` | Public storage; readable by anyone via `eth_getStorageAt` |

`private` in Solidity is a compile-time visibility restriction. It stops other
Solidity contracts referring to the variable by name; it does not hide the bytes.
Every node stores all contract storage and anyone can run a node.

The nonce's actual purpose is de-duplication — without it, two calls by the same
sender in the same block would hash identical inputs. It makes results *differ*; it
does not make them *unguessable*. Calling it a nonce borrows a word from
cryptography, where a nonce is combined with a secret. Here there is no secret.

#### Impact — three attacks, increasing in reliability

**1. Off-chain simulation.** Read the nonce from storage, compute the next slot
timestamp, hash it, and submit only when the result is a win. `eth_call` runs a
transaction against current state without publishing it, so the attacker can dry-run
instead of predicting. Failed attempts cost nothing and don't advance the nonce.
Imperfect only because a transaction landing a slot late changes the timestamp.

**2. Attacker contract that reverts on a loss — 100% reliable.** A transaction is
atomic, so a revert undoes everything inside it:

```solidity
contract ZombieSniper {
    function snipe(uint256 target) external {
        (,,,, uint16 before,) = game.zombies(myZombie);
        game.attack(myZombie, target);
        (,,,, uint16 after_,) = game.zombies(myZombie);
        require(after_ > before, "lost - undo everything");
    }
}
```

"Attack; if I lost, pretend it never happened." The loss, the cooldown and the
nonce increment all roll back. Retry next block, where the timestamp differs and
the roll changes. Effective win rate 100%; cost is gas only.

Note the sniper contract must own the zombie, since `msg.sender` is the contract,
not the human.

**3. Block builder influence.** A validator chooses inclusion, ordering and has
latitude over the timestamp, so for a valuable outcome they can nudge inputs in
their favour. This is why `block.timestamp`, `blockhash` and `block.prevrandao`
are all unsuitable as entropy for anything with value attached.

#### Generality

Attack 2 is not specific to this contract. **Any contract that reveals the outcome
of a random event in the same transaction that triggers it can be sniped**, because
the caller can always choose to undo it. This has drained on-chain lotteries and
rarity mints. The reviewable question for any contract is: *can the caller learn
the result before committing to it?*

#### Reproduction

`test_AttackOutcomeIsPredictable` reads `randNonce` with `vm.load` (slot from
`forge inspect ZombieAttack storageLayout`), recomputes the hash off-chain, and
asserts the predicted winner matches the actual result.

A loop test using `vm.roll` / `vm.warp` with `try/catch` demonstrates the sniper
pattern recording zero losses.

#### Why not fixed

A correct fix means Chainlink VRF (randomness delivered in a *later* transaction,
with proof, so it can't be reverted away) or commit-reveal. Either is a project in
itself and out of scope here.

A cheap mitigation worth noting: charge the fee and trigger the cooldown *before*
the roll. Sniping then costs something even when the outcome is predictable.

#### Confirmed by

Slither flags this as weak PRNG. Found first by reasoning about the design;
static analysis agreed afterwards.

---

## BUG-03

### Cooldown enforced on one branch of `attack` only

**Severity:** Medium · **Status:** Fixed · **Found by:** code review, reproduced
live on Anvil

#### Description

```solidity
function attack(uint _zombieId, uint _targetId) external ownerOf(_zombieId) {
    uint rand = randMod(100);
    if (rand <= attackVictoryProbability) {
        ...
        feedAndMultiply(_zombieId, enemyZombie.dna, "zombie");   // checks _isReady
    } else {
        myZombie.lossCount++;
        enemyZombie.winCount++;
        _triggerCooldown(myZombie);                               // no check
    }
}
```

`attack` has no readiness check of its own. The check lives inside
`feedAndMultiply`, which only the win branch calls.

#### Impact

**Nondeterministic behaviour on identical input.** Calling `attack` while in
cooldown reverts ~71% of the time (win path, `feedAndMultiply` rejects) and
succeeds ~29% of the time (loss path, no check). Same preconditions, different
outcome, decided by a dice roll. As a test observation: a flaky result whose cause
is a product defect, not the environment.

**Free stat manipulation.** The loss path increments the *target's* `winCount` at
no cost beyond gas, and targets cannot refuse being attacked. A player in permanent
cooldown can inflate an ally's win count indefinitely, or inflate a rival's
`lossCount`. Any leaderboard or reward tied to those counters is manipulable.

#### Reproduction

Live on Anvil, zombie in cooldown:

```bash
for i in {1..20}; do
  cast send $Z "attack(uint256,uint256)" 0 1 --private-key $PK0 2>&1 \
    | grep -q "status.*1" && echo "$i: SUCCEEDED" || echo "$i: reverted"
done
```

Observed roughly a 71/29 split of reverts to successes on identical input.

#### Fix

Hoisted the precondition to the entry point so it holds on every path:

```solidity
function attack(uint _zombieId, uint _targetId) external ownerOf(_zombieId) {
+   require(_isReady(zombies[_zombieId]), "zombie not ready");
+   require(_zombieId != _targetId, "cannot attack itself");
    ...
```

#### Lesson

A business rule enforced as a side effect of one branch, rather than stated once as
a precondition, is invisible to line coverage: the lines all execute, and the rule
still isn't enforced. The review habit this suggests — list each state-changing
function's preconditions, then check every branch enforces all of them — generalises
well beyond this contract.

---

## BUG-04

### Self-attack aliases storage; owner-vs-owner attack is free levelling

**Severity:** Medium · **Status:** Fixed (self-attack) + spec question raised ·
**Found by:** code review

#### Description

The tutorial only applies the `ownerOf(_zombieId)` modifier, which checks that the
caller owns the *attacking* zombie. Nothing is said about the target. Two separate
issues result.

**The defect — `_zombieId == _targetId`.** `myZombie` and `enemyZombie` are both
`storage` pointers, so with equal IDs they alias the same struct — two names for
the same slots, not copies. On a win, the same zombie receives `winCount++`,
`level++` *and* `lossCount++`, then feeds on its own DNA to produce a near-clone.
One entity is simultaneously winner and loser, which is incoherent under any product
decision. No spec is required to call this wrong.

**The spec gap — attacking a zombie you also own.** Roughly 71% of the time the
attacker levels up and spawns a new zombie; the victim takes a loss you don't care
about. That is free levelling, bypassing `levelUpFee`, the contract's only revenue.
Whether this should be allowed is a product decision, not a tester's call.

#### Impact

Self-attack corrupts a zombie's record irrecoverably. Owner-vs-owner attacks make
the fee-based progression optional.

#### Fix and open question

`require(_zombieId != _targetId)` added (see BUG-03's fix block).

Open question for the product owner: *should a player be permitted to attack a
zombie they also own?* Impact if yes: `levelUpFee` becomes avoidable.

#### Note

Neither issue appears anywhere in the tutorial's specification. The category is
behaviour nobody wrote down and nobody intended — found by reading the code and
asking what else it permits, not by executing a test case.

---

## BUG-05

### `getZombiesByOwner` is O(total supply)

**Severity:** Low–Medium · **Status:** Documented · **Found by:** gas report

#### Description

`getZombiesByOwner` iterates over every zombie that has ever existed to assemble one
owner's array, so its gas cost grows linearly with total supply rather than with the
owner's holdings.

#### Measurements

| Total supply | Gas |
|---|---|
| 1 | [TODO] |
| 10 | [TODO] |
| 100 | [TODO] |

Extrapolated supply at which a single call exceeds the 30M block gas limit:
**[TODO]**

Measured by `test_GetZombiesByOwnerGasScaling` using `gasleft()` deltas.

#### Impact — stated honestly

As a `view` function called from a front end via `eth_call`, this is **not** bound
by the block gas limit in the way an on-chain call would be, so the practical impact
at realistic supply is limited: slower RPC responses and possible provider timeouts.

It becomes a genuine denial of service **only if an on-chain path ever calls it**.
At that point the function — and anything depending on it — becomes permanently
uncallable past a certain supply, with no way to recover because the loop bound only
grows. This is the standard unbounded-loop DoS pattern.

#### Recommendation

Track per-owner token IDs in a mapping updated on mint and transfer (OZ's
`ERC721Enumerable` provides this), or paginate the getter. Either removes the
dependency on total supply. Not fixed here, as the function is currently view-only
and the exercise is about finding the issue rather than refactoring.

---

## BUG-06

### `winCount` overflow permanently bricks a zombie

**Severity:** Low · **Status:** Documented · **Found by:** code review, reproduced
with `vm.store`

#### Description

`winCount` and `lossCount` are `uint16`, capping at 65,535. Under Solidity 0.8,
arithmetic overflow reverts rather than wrapping, so once a zombie reaches the cap
every subsequent `attack` that would increment the counter reverts. The zombie can
never attack again, and there is no way to reset it.

#### Impact

Low in practice — reaching 65,535 wins requires 65,535 transactions and the matching
gas. But it is unrecoverable when it happens, and under 0.4.x (the tutorial's
original compiler) the same code would have silently wrapped to zero instead, which
is arguably worse. Worth recording as an example of a port changing failure mode:
silent corruption became a hard revert.

#### Reproduction

`test_WinCountOverflowBricksZombie` uses `vm.store` to set the counter near the cap
and confirms the next attack reverts.

#### Recommendation

Widen to `uint32` (still packs into the struct) or saturate at the maximum rather
than reverting.

---

## BUG-07

### Win probability is 71%, not 70%

**Severity:** Low · **Status:** Fixed · **Found by:** code review

#### Description

```solidity
uint attackVictoryProbability = 70;
if (rand <= attackVictoryProbability) { /* win */ }
```

`randMod(100)` returns 0–99. `rand <= 70` counts 71 values (0 through 70) as wins,
giving 71%, not the 70% the variable name states.

#### Impact

A one-point discrepancy between documented and actual game balance. Trivial here;
the same off-by-one in a fee split, a liquidation threshold or a collateral ratio
would not be.

#### Fix

```diff
- if (rand <= attackVictoryProbability) {
+ if (rand < attackVictoryProbability) {
```

Covered by a statistical test over a fixed seed asserting the win rate falls within
tolerance of 70%.

---

## OBS-01

### No `Attack` event — combat is invisible to a front end

**Status:** Raised · **Found by:** exploratory session (`cast logs`)

`createRandomZombie` emits `NewZombie`, but `attack` emits nothing. A front end has
no way to learn that one of its user's zombies was attacked, so the real-time
notification the tutorial itself describes in its final chapter cannot be built.

From a UI-testing standpoint this is the relevant framing: **if the front end cannot
observe it, the front end cannot display it, and no amount of UI testing will
surface the gap** — it has to be caught at the contract.

Recommendation: emit `Attack(address indexed attacker, uint256 attackerId,
uint256 targetId, bool won)`. Indexing the address lets a client filter for events
concerning its own user.

---

## OBS-02

### `setKittyContractAddress` accepts a non-contract address

**Status:** Raised · **Found by:** fork test edge-case exploration

The setter performs no validation. Pointing it at an EOA (an address with no code)
breaks feeding permanently from the users' perspective: a call to a codeless address
returns success with empty data, which the ABI decoder then rejects, so every
`feedOnKitty` reverts.

Recoverable by the owner calling the setter again with a correct address, so not a
permanent brick — but an owner typo takes a core feature offline until noticed.

Covered by `test_FeedRevertsIfKittyContractIsNotAContract`.

Recommendation: `require(_address.code.length > 0, "not a contract")` in the setter.
Cheap, and turns a silent runtime failure into an immediate one.

---

## Method notes

**What the invariant suite found that unit tests did not.** BUG-01 required a
specific *sequence* — create, transfer, create — across different actors. No unit
test I would have written by hand covered that ordering, because the bug only exists
in the interaction between two features that look independent.

**What `fail_on_revert` decided.** With it off, BUG-01 was invisible: the campaign
reported a clean pass while swallowing 380 reverts. The same 12,800 calls found
nothing. The setting, not the test count, was the difference.

**What code review found that no amount of fuzzing would.** BUG-02 and BUG-04 are
about what the code *permits*, not about input values. A fuzzer exploring `attack`
would never construct an attacker contract that reverts on a loss, because that
isn't an input — it's a different caller. Automated testing and adversarial reading
of the code cover different ground, and this repo needed both.

**Verifying the tests themselves.** Each invariant was mutation-checked — a
deliberate bug injected, the invariant confirmed to fail with its own assertion
message rather than an incidental revert. See the README for results. An invariant
that has never failed is of unknown value.
