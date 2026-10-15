# CryptoZombies — Foundry Test Suite

A QA engineering exercise: take the CryptoZombies tutorial contracts, port them to
modern Solidity, and test them the way a production codebase should be tested —
unit, fuzz, invariant and mainnet-fork tests, with the test suite itself verified
by mutation.

The contracts are a teaching example. **The tests are the deliverable.**

The original tutorial ships working-looking code with no test suite. This repo asks
what a test engineer actually finds when that code is put under pressure: seven
documented defects, including a denial-of-service bug introduced by the port itself
and an exploitable randomness flaw that lets a player win every fight.

---

## Contents

- [What this covers](#what-this-covers)
- [Quick start](#quick-start)
- [Test architecture](#test-architecture)
- [Findings](#findings)
- [Quality reports](#quality-reports)
- [Verifying the tests themselves](#verifying-the-tests-themselves)
- [CI](#ci)
- [Project layout](#project-layout)
- [Notes and limitations](#notes-and-limitations)
- [Roadmap](#roadmap)

---

## What this covers

| Area | Approach |
|---|---|
| **Port** | Solidity 0.4.x → 0.8.x; hand-rolled ERC-721 and `Ownable` → OpenZeppelin v5; `SafeMath` removed (0.8 checks arithmetic natively) |
| **Unit tests** | Happy paths, revert paths, access control, event emission, cooldown boundaries |
| **Fuzz tests** | Property-based testing over generated inputs — DNA format, fee handling |
| **Invariant tests** | Randomised call sequences through a handler, checking rules that must hold in every reachable state |
| **Fork tests** | Real CryptoKitties `KittyCore` on a pinned mainnet block, instead of a mock |
| **Mutation checks** | Deliberate bugs injected to prove each invariant can fail |
| **Exploratory** | Manual session against a local Anvil node — time travel, snapshots, gas probing |
| **Static analysis** | Slither, with findings triaged against those found by hand |

---

## Quick start
### Running tests

```bash
forge test                                   # everything
forge test --no-match-contract Fork          # offline only — no RPC needed
forge test --match-contract Invariant -vv    # invariants, with call summaries
forge test --match-test test_Attack -vvvv    # one test with full traces
source .env && forge test --match-contract Fork   # fork tests
```

### Reports

```bash
forge coverage --no-match-contract Fork --report summary
forge coverage --report lcov && genhtml lcov.info --branch-coverage -o coverage
forge test --gas-report
forge snapshot --check        # gas regression gate
forge fmt --check
forge build --sizes
```

### Local chain

```bash
anvil                                                    # terminal 1

# terminal 2
export ETH_RPC_URL=http://127.0.0.1:8545
forge script script/Deploy.s.sol --rpc-url $ETH_RPC_URL --broadcast --private-key $PK0
forge script script/Seed.s.sol  --rpc-url $ETH_RPC_URL --broadcast --private-key $PK0
```

`Seed.s.sol` produces a known starting state and writes the deployed address to a
JSON file, so downstream (browser) tests don't hardcode it.

---

## Test architecture

### Layers

```
test/
├── Base.t.sol                  shared fixture: deploy as a real EOA owner, funded actors
├── Zombie.t.sol                unit + fuzz tests
├── Zombie.invariant.t.sol      invariant definitions
├── KittyFork.t.sol             mainnet fork integration
├── handlers/
│   └── ZombieHandler.sol       bounded action space for the invariant fuzzer
└── mocks/
    └── MockKitty.sol           deterministic stand-in for unit tests
```

### Why a handler

Pointing the invariant fuzzer straight at the contract ("open testing") wastes
almost every call on nonsense input — `attack(8547219384, ...)` just reverts. The
handler translates random `uint256`s into plausible actions:

- `bound()` maps random numbers onto valid zombie IDs and a fixed cast of three actors
- invalid actions `return` early rather than reverting, so `fail_on_revert = true`
  stays meaningful
- a `passTime()` action advances `block.timestamp`, without which cooldowns never
  expire and the feed/attack paths are unreachable
- per-action counters are printed from `afterInvariant()`, so a run that silently
  did nothing is visible rather than passing as a false green

### `fail_on_revert = true`

Set deliberately, and it is the single most valuable setting in this repo.

With it off, the suite reported a clean pass while silently swallowing 380 reverts
across 12,800 calls. With it on, those reverts became a failure — and that failure
was [BUG-01](#findings), a real denial-of-service defect. The setting is the
difference between finding that bug and not.

### Invariants

| Invariant | Rule |
|---|---|
| `invariant_BalancesSumToTotalSupply` | Every zombie that exists is owned by exactly one actor — none vanish, none double-count |
| `invariant_AllDnaIsSixteenDigits` | DNA stays within 16 digits after arbitrary chains of feeding and combat |
| `invariant_ContractBalanceMatchesFees` | Contract ETH equals fees paid in minus withdrawals out, tracked by ghost variables independently of the contract's own arithmetic |

Ghost variables matter here: the balance invariant compares two values computed
different ways. Re-deriving the expected value from the contract's own formula would
re-derive the bug along with it.

### Fork tests

`KittyFork.t.sol` runs against real mainnet state at a **pinned block**. Pinning is
deliberate — an unpinned fork follows the chain head, which makes results change
every 12 seconds and turns the suite into a flaky one by construction. Pinning also
lets Foundry's RPC cache do its job, so repeat runs are fast.

Testing against the real `KittyCore` rather than a mock matters because a mock
encodes *my* assumptions about the dependency. Real kitty `genes` are 77-digit
values from a 2017 encoding scheme that no mock I'd have written would have produced.

---

## Findings

Full write-ups in [BUGS.md](./BUGS.md).

| ID | Issue | Found by | Severity | Status |
|---|---|---|---|---|
| BUG-01 | **Dual ownership accounting.** The port kept the tutorial's `ownerZombieCount` mapping alongside OZ's `_balances`. `transferFrom` updates only the latter, so after any transfer the two disagree permanently: the sender is locked out of ever creating a zombie again, and the receiver can mint an extra one — bypassing the one-per-player rule and the level-up fee entirely. | Invariant campaign with `fail_on_revert = true` | High | Fixed — legacy mapping removed, `balanceOf` is the single source of truth |
| BUG-02 | **Predictable randomness.** `randMod` hashes `block.timestamp`, `msg.sender` and a public storage counter — no secret inputs. An attacker contract can call `attack` and `require` a win, reverting the whole transaction on a loss and undoing the cooldown and nonce increment. Effective win rate: 100%, cost: gas only. | Code review | High | Documented; proper fix is Chainlink VRF or commit-reveal |
| BUG-03 | **Readiness enforced on one branch only.** `attack` has no readiness check of its own; the win path calls `feedAndMultiply` (which checks) and the loss path doesn't. The same call during cooldown therefore reverts or succeeds depending on a dice roll, and the free loss path lets anyone inflate a target's `winCount` at will. | Code review, reproduced live on Anvil | Medium | Fixed — precondition hoisted into `attack` |
| BUG-04 | **Self-attack storage aliasing.** With `_zombieId == _targetId`, `myZombie` and `enemyZombie` are two storage pointers to the same struct, so one zombie records a win and a loss simultaneously and feeds on its own DNA. Separately, attacking any zombie you own is free levelling that bypasses `levelUpFee` — a spec gap worth raising rather than a defect. | Code review | Medium | Fixed (self-attack); spec question raised |
| BUG-05 | **`getZombiesByOwner` is O(total supply).** Loops over every zombie ever created to build one owner's array. Measured: TODO gas at supply 1, TODO at 10, TODO at 100. As a `view` called via `eth_call` the practical impact is limited; it becomes a denial of service only if an on-chain path ever calls it. | Gas report | Low–Medium | Documented |
| BUG-06 | **Win-count overflow.** `winCount` is `uint16`, capped at 65,535. Under 0.8 the increment reverts rather than wrapping, permanently bricking that zombie's ability to attack. | Code review, reproduced with `vm.store` | Low | Documented |
| BUG-07 | **Off-by-one win probability.** `rand <= 70` counts 0–70 as wins, giving 71% rather than the intended 70%. | Code review | Low | Fixed |

<!-- TODO: fill in the BUG-05 gas measurements, and correct any status above that
     doesn't match what you ended up doing. -->

The two worth talking about are BUG-01 and BUG-02. BUG-01 is a defect the *port
itself* introduced — two sources of truth for one fact, where only one gets updated
— and it was found by a technique, not by guessing. BUG-02 is the general lesson:
any contract that reveals a random outcome in the same transaction that triggers it
can be sniped, because the caller can always choose to undo the result.

---

## Quality reports

| Metric | Result |
|---|---|
| Line coverage (`src/`, excl. fork tests) | TODO% |
| Branch coverage | TODO% |
| Function coverage | TODO% |
| Invariant campaign | 256 runs × 50 depth, 12,800 calls, 0 reverts |
| Mutation checks | 3/3 invariants confirmed to fail on injected bugs |
| Contract size | 16,426 / 24,576 bytes (EIP-170) |
| Gas snapshot | committed, enforced in CI |

<!-- TODO: paste real coverage numbers from `forge coverage --no-match-contract Fork` -->

Coverage is measured on `src/` only, with `test/` and `script/` filtered out and
fork tests excluded (they need an RPC and slow the run considerably). An unqualified
coverage percentage isn't a number anyone can check.

**Known coverage gaps**, each classified rather than papered over:

- `attack` self-attack branch — excluded from the invariant handler by design
  (see BUG-04), covered by a targeted unit test instead
- <!-- TODO: list any others from `forge coverage --report debug`, and say for each
     whether it's a genuine hole, dead code, or a deliberate handler exclusion -->

Branch coverage is the number that matters here. Every `require` is a branch tested
one way by definition — the question is whether the revert path has a test too.
BUG-03 is exactly what asymmetric branch coverage looks like in practice: a rule
enforced on one path and not the other, invisible to line coverage.

---

## Verifying the tests themselves

A suite that has never failed is a suite of unknown value. Each invariant was
checked by injecting a deliberate bug and confirming it fails with its own assertion
message, not an incidental revert:

| Mutation | Expected to break | Result |
|---|---|---|
| Array push without `_safeMint` (supply grows, no balance) | `invariant_BalancesSumToTotalSupply` | Caught — shrunk to a 2-call sequence |
| `withdraw` leaves 1 wei behind | `invariant_ContractBalanceMatchesFees` | TODO |
| `_createZombie` drops `% dnaModulus` | `invariant_AllDnaIsSixteenDigits` | TODO |

<!-- TODO: fill in results for mutations 2 and 3 -->

One lesson came out of this that changed the code: an invariant that *reverts* when
the contract is broken tells you much less than one that *asserts*. The first
mutation knocked over all three invariants, but only one of them actually detected
it — the other two blew up on `ERC721NonexistentToken` while reading an ownerless
token. Invariants are run against broken states by definition, so they were
rewritten not to assume a well-formed world.

This matters more than the coverage percentage. A 100%-coverage suite that never
fails when the contract is broken is worth nothing; a 90%-coverage suite proven to
catch injected bugs is worth something.

---

## CI

GitHub Actions, with the suite split by cost and dependency:

- `forge fmt --check` — formatting gate
- `forge build --sizes` — fails past the EIP-170 limit
- `forge test --no-match-contract Fork` — fast, hermetic, runs on every push, with
  a `ci` profile that raises fuzz runs 10×
- `forge test --match-contract Fork` — separate job, skipped when no RPC secret is
  configured
- `forge snapshot --check` — gas regression gate

Fork tests are integration tests against a third party and can fail for reasons
unrelated to this code (rate limits, provider outage), so they don't belong in the
gate that blocks every commit.

Dependencies are git submodules, so CI checks out with `submodules: recursive`.

---

## Project layout

```
src/
├── ZombieFactory.sol      creation, DNA generation, OZ ERC-721 base
├── ZombieFeeding.sol      kitty feeding, cooldowns, KittyInterface
├── ZombieHelper.sol       level gates, fees, withdrawal
├── ZombieAttack.sol       combat and the randomness under discussion
└── ZombieOwnership.sol    top of the inheritance chain

test/      see "Test architecture" above
script/
├── Deploy.s.sol           deploy to Anvil or a testnet
└── Seed.s.sol             reproducible known state for manual and browser testing
```

### Configuration

```toml
[fuzz]
runs = 1000

[invariant]
runs = 256
depth = 50
fail_on_revert = true

[profile.ci.fuzz]
runs = 10000
```

---

## Notes and limitations

- **`.env` is gitignored.** `.env.example` is committed as a template. Never commit
  an RPC key.
- **Local keys only.** Anvil's test private keys are public by design and appear in
  the commands above. They are safe on a local chain and nowhere else. Any testnet
  deployment uses `cast wallet import` with an encrypted keystore and a throwaway
  wallet that has never held real funds.
- **Not an audit.** This is a test-engineering exercise on tutorial code, not a
  security review. The findings are what a thorough testing pass surfaces, not a
  claim of completeness.
- **The randomness bug is documented, not fixed.** Fixing it properly means
  Chainlink VRF or commit-reveal, which is a different project. The demonstration
  of the exploit is the point.
- **Coverage figures exclude fork tests**, as noted above.

---

## Roadmap

Next phase: browser-level end-to-end testing against a local chain.

- Minimal front end (Vite + viem) — deliberately plain; the UI is a test target
- Playwright with a MetaMask test wallet (Synpress / Dappwright) against Anvil
- Scenarios: wallet connect, create, cooldown greyed-out state verified via
  `evm_increaseTime`, level gates, `onlyOwner` admin rejection, multi-wallet
  transfer, reverted transaction handling
- Per-test isolation via `evm_snapshot` / `evm_revert`
- Seeded chain state from `Seed.s.sol`, so tests start from a known world

---

## Background

Built as EVM practice by a QA engineer with ~4 years testing wallets and a community
governance platform on Cardano. The contracts started as the CryptoZombies tutorial;
everything in `test/` is original work.

The interesting part of the exercise was how different the eUTXO and account models
feel from a testing standpoint — reverts that still cost gas, approvals as a
standing attack surface, and the fact that contract storage is public no matter what
`private` says.
