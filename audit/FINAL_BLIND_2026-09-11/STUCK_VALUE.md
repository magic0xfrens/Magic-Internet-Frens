# Stranded value across every Cauldron generation — Sepolia forensic sweep

**Chain** 11155111 (Sepolia) · **read at block 11684078–11684130** (`cast block-number` → `11684078`;
PositionManager reads at `11684130`) · **fork simulations** run against
`--fork-url https://ethereum-sepolia-rpc.publicnode.com` at the same head.

Every figure below is tagged **VERIFIED** (read on-chain, or the balance delta of a fork simulation I ran) or
**DERIVED** (reasoned from source at `/tmp/blind-final/contracts/solidity`, line numbers identical to the repo).
Nothing in this document was broadcast. No `cast send`, no `forge script --broadcast`, no key was touched.

---

## 1. Headline

| bucket | ETH | wei |
|---|---:|---:|
| **RECOVERABLE NOW** (simulated, dead rounds only) | **24.687246083** | 24 687 246 082 821 803 043 |
| Live round 38 (recoverable, but pulling it **kills the live market**) | 0.919104662 | 919 104 662 239 193 331 |
| Recoverable by a **third party**, not by the deployer key (NFT holders / presale minters) | 0.778657706 | 778 657 706 496 665 469 |
| **UNRECOVERABLE** — no code path exists | **8.055989850** | 8 055 989 849 788 427 549 |
| **Total protocol-held value found** | **34.443568410** | 34 443 568 409 896 089 391 |

**ERC20 quote tokens: zero, everywhere.** `USDG` (`0x84b17f1c…`, 6 dp) and `xNVDA` (`0x4F3Df1F4…`, 18 dp)
— decimals read from `indexer/deployments/round.json` — return `balanceOf == 0` for **all 2 904 addresses tested**:
the 127 named protocol addresses plus every one of the deployer's 2 898 derived `CREATE` addresses. VERIFIED
(`/tmp/recovery-sim/erc20.json`, `/tmp/recovery-sim/known_sweep.json`). No generation ever ended up holding a
foreign quote asset, so there is no stranded non-ETH quote value and no leg-proceeds sweep to run.

Split of the recoverable-now total:

| source | ETH | signer |
|---|---:|---|
| Perp vaults — 11 old `PerpVault.withdrawEth` | 9.452490760 | deployer EOA `0xc944…c133` (direct, no timelock) |
| r33/34 registry `emergencyWithdrawLP(1)` | 6.888108470 | timelock `0x06705E8c…` |
| r32 registry `emergencyWithdrawLP(1)` + `emergencySweep(0)` | 5.547473768 | timelock `0xBc1C27Ed…` |
| v7 registry `emergencyWithdrawLP(1)` + `emergencySweep(0)` | 2.799173085 | deployer EOA `0xc944…c133` (direct) |
| r37 + r20 loose dust | 0.000000000000000392 | see below |

---

## 2. The generation list

Built from `git log` of `deployments/sepolia.json` and `indexer/deployments/round.json`, then **verified on-chain** —
every address below was called, not just read out of a file.

| round | registry | status | live LP position(s) | ETH out (simulated) |
|---|---|---|---|---:|
| **38 (live)** | `0x018efe32379bfc3f38ed7e592f5c9f214b6e3ded` | summoned, gen 1 | **39124** (active) + **39125** (reserve) | 0.919104662 |
| 37 | `0x012abab319b381ce4ed5d941dfd0626e46c1f18b` | summoned, gen 1 | 39121/39122 **burned** | 321 wei |
| 35 | `0x94b16dc3b31fe2849f62d5b9a152dce4b480a2b9` | summoned, gen 1 | 39109 **burned** | 0 |
| 33/34 | `0x3FD7649FcF3aF0CB511E625e7d868d98bb85D7D4` | summoned, gen 1 | **38888** (reserve) | **6.888108470** |
| 32 | `0x56022128bF27a58f3c03cFE72Cb2b5F460E46940` | summoned, gen 1 | **38776** (reserve) | **5.547473768** |
| ~31 | `0xF3d621392D8aaB7507E902cB2638d3bf934a4107` | summoned, gen 2 | 38742/38743 **burned** | 0 |
| 20 | `0x60f5e17f0A7cb39503B4C5A844b16DBc6604BB51` | summoned, gen 1 | 38583/38584 **burned** | 71 wei |
| v7 "GNOME" | `0x09579fbb9657322012c0c155f5af95eecca4010b` | summoned, gen 1 | **38337** | **2.799173085** |
| cycle-twin | `0x0181A8d68A91CE2E9253568e6B83f44beBCa628F` | gen 2 | **38292** (liq 2 655 482 661 599 110) | no exit — see §5 |
| "final" | `0x4Cdb936e0224651a7Ab47acdC34babF8ae433eD4` | gen 2 | 38296/38297 **burned** | n/a |
| "canonical" | `0x0dcc4D2d1C41EdE0F394C6a7De16c118FAFaFf23` | `summoned()==false`, gen 0 | none | nothing ever deployed into it |
| pre-r20 "A" | `0x6eaaf93eaba9f957514fa2031f17357ba7e64143` | gen 1 | not enumerated | **holds 2.344615651 ETH, no exit** |
| pre-r20 "B" | `0x3493e94c3f4fcdc47883247e9b2cd67590ca39b3` | gen 1 | not enumerated | **holds 2.067283323 ETH, no exit** |
| pre-r20 "C" | `0xd6176ebfb61cedae6d5663c796abe80779229754` | gen 1 | not enumerated | holds 0.047344517 ETH, no exit |

All position ids VERIFIED via `PositionManager.ownerOf(uint256)` / `getPositionLiquidity(uint256)` /
`getPoolAndPositionInfo(uint256)` on `0x429ba70129df741B2Ca2a85BC3A2a3328e5c09b4`. "burned" = the call reverts
`NOT_MINTED`, i.e. that generation's liquidity has already been withdrawn.

The three pre-r20 registries appear in **no deployment JSON in the repository**. They were found by deriving every
`CREATE` address of the deployer EOA `0xc94400e90bb652afa02740bff50824e14069c133` for nonces 0…2897
(`keccak(rlp(sender,nonce))`) and reading the balance of each. VERIFIED.

### Live LP detail (VERIFIED)

| id | owner | liquidity | pool key |
|---|---|---:|---|
| 39124 | r38 registry | 2 787 332 595 870 106 077 398 | ETH / `0xf3ead60f…`, fee 0, spacing 200, hook `0xa319112c…` |
| 39125 | r38 registry | 39 023 818 453 393 242 888 654 | same pool (out-of-range reserve) |
| 38888 | r33/34 registry | 137 566 741 694 677 939 517 344 | ETH / `0xf0efaeb8…`, hook `0x38aa4638…` |
| 38776 | r32 registry | 117 227 582 257 829 546 086 610 | ETH / `0xb2e013a3…`, hook `0xEC66519e…` |
| 38337 | v7 registry | 19 709 417 799 620 566 164 056 | ETH / `0x0588ca16…` (GNOME), hook `0x4f44adc0…` |
| 38292 | twin registry | 2 655 482 661 599 110 | ETH / `0x5b26ba6b…`, fee 10000, hook `0x41c14c19…` |

Liquidity is **not** value: the reserve legs are out-of-range and hold the dead generation's ERC20, not ETH. The ETH
column in §2 is the *measured* ETH that leaves the pool in simulation, which is the only honest valuation.

---

## 3. Recovery playbook — largest first

All five were fork-simulated. Simulation sources: `/tmp/recovery-sim/sim/test/Recover.t.sol`,
`/tmp/recovery-sim/sim/test/PerpAll.t.sol`, `/tmp/recovery-sim/sim/test/Perp.t.sol`. **Do not run these as
transactions from this document without re-checking state at the time of sending.**

### 3.1 Perp vaults — 9.452490760009882763 ETH — signer: deployer EOA, no timelock (largest, easiest)

Every old round seeded its `PerpEngine` with protocol liquidity (`plv`) and the deployer holds **100 % of the
`ethShares`**. `PerpVault.withdrawEth(shares)` (`cauldron/PerpVault.sol:240`) has **no owner gate and no timelock** —
it is gated only on `ethShareOf[msg.sender]`. This is 11 independent, immediately-callable withdrawals.

| vault | engine | deployer shares | ETH paid (simulated) |
|---|---|---:|---:|
| `0xFd34f4b2c87C7C7580b479d3Da08E458a10c085E` | `0xce989dD896A9ADd42A111B255e47f47a78Cb174b` | 2000000000000000000000000 | 2 005 091 977 361 111 109 |
| `0xabD9Dbb68edb2b36ca06a6A4c3b51FfC86F02772` | `0xC39d6Ed8C020f1B9686807638975F8d9294c419a` | 2000000000000000000000000 | 1 580 103 632 648 771 669 |
| `0x6Bb4D151cA52b95F68914a04F739ED85439B03a0` | `0x9Ef763322F3d8e0B5a7f11C6c00FBe14D72c31eD` | 1100000000000000000000000 | 1 004 484 999 999 999 994 |
| `0x00B07D1e07C1a39e7DA2BBD7C614805c4e2A4389` (r32) | `0x706eEbBF2C9CbeA25b4150ED0379DDE9DCc41f75` | 1000000000000000000000000 | 1 000 000 000 000 000 000 |
| `0x06dB1ea16180d6D3aefED3B4B54fF962431Ce46E` (r20) | `0x26ae199E143d98be557Eaf89EF7764291bcc51e5` | 1000000000000000000000000 | 1 000 000 000 000 000 000 |
| `0x744cDC7E21CEEEc51ACDF9Bf393505cC7FAB4E78` | `0x83277a4F92e76ad782b42dC9E579c842AF951833` | 500000000000000000000000 | 500 000 000 000 000 000 |
| `0xFbFbCDd4baC7092006cCF856398aA61C6fdbDfAd` | `0xa4E436163c338bAb6c013a85AB3d281Fc787e9A7` | 500000000000000000000000 | 500 000 000 000 000 000 |
| `0x561027Fd8aFf4D70F355e9516ca29856BFA21bb0` | `0xE6990aA30E1c3081e2b2f64d5d3bDE8c99A8B233` | 500000000000000000000000 | 500 000 000 000 000 000 |
| `0xadEc1faCD4a6810090192792a2A148563bC39088` | `0xFa2d2fa505f8dfbD5a73760b08fa22eD38F93f3F` | 500000000000000000000000 | 500 000 000 000 000 000 |
| `0xe59C81f5a253e30B9eE7E3e8b91F30da1467A2b2` | `0xea63f2D1A0719A21aa1f2cD52A14d4346A82480f` | 500000000000000000000000 | 500 000 000 000 000 000 |
| `0x8932BF0585e4b4a4Aa962f606035842F5017aEd1` | `0xF6F3eB7148fbC3c673d287a16798B0b432269DB4` | 500000000000000000000000 | 362 810 149 999 999 991 |

Command per vault (signer `0xc94400e90bb652afa02740bff50824e14069c133`):

```
cast send <VAULT> "withdrawEth(uint256)" <DEPLOYER_SHARES> \
  --rpc-url $FORK_RPC --account deployer --from 0xc94400e90bb652afa02740bff50824e14069c133
```

Two of them return a non-zero `queued` (`0x6Bb4D151…` queues 96 550 000 000 000 005 wei, `0xabD9Dbb6…` and
`0x8932BF05…` queue 144 825 000 000 000 00x wei). Queued ETH is **not paid** — `withdrawEth` pays
`min(owed, engine.freeEth())` (`PerpVault.sol:246-248`) and books the remainder in `pendingEth`. The engine's
balance exceeds `plv` in those three cases, so the residue is real ETH that the share maths cannot reach; see §5.

### 3.2 r33/34 — 6.888108469848070785 ETH — signer: timelock `0x06705E8c819D962bEf3a3d7d0fF5a91E404e23B3`

`emergencyWithdrawLP(1)` at `CauldronRegistry.sol:451`, gated `onlyEmergency timelocked nonReentrant`.
`emergencyAdmin` is **immutable** (`CauldronRegistry.sol:169`) and is the timelock, so the call must be scheduled
through it. `emergencyDelay() == 172800` (48 h) and **it is already armed**: `emergencyReadyAt() == 1789200300`
(VERIFIED) — roughly 2026-09-12 ~20:05 UTC, i.e. it has **not** matured yet at the time of this report. Arming is
mandatory even at zero delay (`CauldronRegistry.sol:389`).

Simulated result: `6 888 108 469 848 070 785 wei` ETH **and** `776 999 999 999 999 717 081 474 875` units of the dead
token `0xf0efaeb8…` land on the timelock. `emergencySweep(address(0))` afterwards returns 0 (the registry's loose
balance is 0). This is the "~6.8882 ETH" the owner's own `recover-old-lp.sh` was written for — the number is right.

```
# once emergencyReadyAt has passed:
cast send 0x06705E8c819D962bEf3a3d7d0fF5a91E404e23B3 \
  "schedule(address,uint256,bytes,bytes32,bytes32,uint256)" \
  0x3FD7649FcF3aF0CB511E625e7d868d98bb85D7D4 0 \
  $(cast calldata "emergencyWithdrawLP(uint256)" 1) \
  0x00..00 0x00..00 $(cast call 0x06705E8c819D962bEf3a3d7d0fF5a91E404e23B3 "getMinDelay()(uint256)")
# wait getMinDelay, then execute(...) with the same arguments, then forward the ETH out of the timelock.
```

### 3.3 r32 — 5.547473767837051841 ETH — signer: timelock `0xBc1C27Edd1Cb66437D4B2290F9787a51081bDfB3`

Same shape, `emergencyDelay() == 300`, `emergencyReadyAt() == 0` → must be armed first (`armEmergency()`, also
`onlyEmergency`, so also through the timelock). Simulated: `5 542 473 767 837 051 841 wei` from the LP plus
`5 000 000 000 000 000 wei` loose on the registry via `emergencySweep(address(0))`, plus
`712 650 687 312 533 427 305 156 521` units of token `0xb2e013a3…`.

**This round is in no manifest that calls itself current** — `deployments/sepolia.json` at HEAD still says round 20.

### 3.4 v7 "GNOME" — 2.799173085126797262 ETH — signer: deployer EOA directly

`emergencyAdmin()` is the **deployer EOA** `0xc944…c133`, and this build predates the arming requirement — the
bytecode has no `armEmergency()` selector (VERIFIED by selector probe of the deployed code). So it is a single
transaction, no timelock, no wait:

```
cast send 0x09579fbb9657322012c0c155f5af95eecca4010b "emergencyWithdrawLP(uint256)" 1 \
  --rpc-url $FORK_RPC --account deployer --from 0xc94400e90bb652afa02740bff50824e14069c133
cast send 0x09579fbb9657322012c0c155f5af95eecca4010b "emergencySweep(address)" \
  0x0000000000000000000000000000000000000000 \
  --rpc-url $FORK_RPC --account deployer --from 0xc94400e90bb652afa02740bff50824e14069c133
```

Simulated: `2 799 173 085 126 796 190 wei` + `1 072 wei` loose + `138 777 109 591 421 868 937 577 323` GNOME.

### 3.5 Round 38 (LIVE) — 0.919104662239193331 ETH — signer: timelock `0x3925859Cefe56af4Cbc670152bc322D57a09A9B6`

`emergencyDelay() == 600`, not armed. Simulated `919 104 662 239 193 010` from the LP + `321 wei` loose +
`438 878 291 467 625 493 350 937 757` units of the live token. **Pulling this removes the live market.** Listed for
completeness, not recommended.

---

## 4. Blocked — needs a fix or another party

| pot | ETH | why it is blocked |
|---|---:|---|
| Genesis dividends `0x0c148d56…`, `0xdf68f9ce…`, `0xeace2b22…`, `0xe8492b2f…`, `0x5acf85b2…` | 0.429747747 | `MiFrensDividend.claim(uint256)` / `claimMany(uint256[])` are **per-NFT**: only the holder of each genesis tokenId can pull their share. Recoverable in aggregate only to the extent the deployer holds those NFTs. VERIFIED the selectors exist in each deployed bytecode; the per-token entitlement was not enumerated. |
| Presales `0x324d75d5…` (0.12), `0x6495341c…` (0.03), `0x622ad50b…` (0.0222) | 0.172200000 | `MiFrensGenesis` has **no owner withdrawal**. The only ETH exits are `igniteCauldron()` (`MiFrensGenesis.sol:575`, pays it into that round's cauldron) and `refund()` (`:300`), which requires `cancelPresale()` (`:289`) first and pays **minters**, not the deployer. DERIVED from source + VERIFIED selector presence. |
| v7 floor vault `0xb2F7ef8C…` | 0.076709959 | `CauldronVault.close()` is `registry`-only (`cauldron/CauldronVault.sol:116`) and the v7 registry has no function that calls it outside a relaunch; `redeem(tokenId)` (`:94`) pays NFT holders at `floorPerNFT() == 1 783 952 543 528 700` wei. So it is holder money, not owner money. |
| r38 live perp vault `0xfC9B5EED…` | 0.100000000 | `ethShares() == 100000000000000006000000` but `ethShareOf(deployer) == 0` — someone else holds the shares. VERIFIED (`withdrawEth` reverts `ZeroShares` `0x9811e0c7` for the deployer). Find the holder; no fix needed. |
| Perp insurance on 4 dead engines | 0.002570109 | `PerpEngine.skimInsurance(uint256,address)` at `cauldron/PerpEngine.sol:1784` is `onlyOwner` and caps at `insuranceEth`. Callable, but only for the insurance slice, not the rest of those engines' balance. |

---

## 5. Unrecoverable — 8.055989849788427549 ETH

| pot | ETH | the missing path |
|---|---:|---|
| Perp engine `0xec8505fd4c1440354dded1f344fd2ee7660b88ac` | **2.952204050** | `plv()` equals the full balance, but this build **has no `vault()`** and no `withdrawPlvTo`, no `skimInsurance`, no sweep. Selector probe of the deployed code finds only `close(uint256,uint256)`, `forceCloseDead(uint256)`, `fundPlvToken(uint256)`, `owner()`, `transferOwnership`, `renounceOwnership`. Nothing pays ETH to anyone but a position closer, and there are no positions. **Single largest dead pot.** |
| Pre-r20 registries `0x6eaaf93e…` (2.344615651), `0x3493e94c…` (2.067283323), `0xd6176ebf…` (0.047344517), twin `0x0181A8d6…` (0.049965585) | **4.509209076** | None of these four has `emergencyWithdrawLP`, `emergencySweep`, `rescueSeeder`, `migrateToSuccessor`, `withdraw`, or any sweep selector in its deployed bytecode (VERIFIED by selector probe). Only `owner()`, `transferOwnership`, `relaunch()`, `claimByBurn`/`claimTokens`. `relaunch()` recycles the ETH into a *new* generation inside the same contract — it never leaves. The twin's LP (position 38292) is stuck behind the same wall. |
| Perp engines with **zero total shares**: `0x37a8f609…` (0.302665890), `0xef1263c0…` (0.274479765), `0x559d51bd…` (0.002179255), `0x33049367…` (0.000133726), net of skimmable insurance | **0.576888527** | `ethShares() == 0` on all four vaults, so there is no share to burn and `withdrawEth` can never pay. `withdrawPlvTo` is `onlyVault`, and the vault will not call it without shares. `0xef1263c0…` is the starkest: balance 0.2745 ETH, `plv == 0`, `insuranceEth == 0` — the money is counted by nothing at all. |
| Hook ETH: r38 `0xa319112c…` (0.010878983), r33 `0x38aa4638…` (0.004259214), r35 `0xfAc5cA22…` (0.002550000) | **0.017688197** | Each equals `legacyBuffer()` exactly (VERIFIED — counter and balance agree to the wei). `legacyBuffer` is spent **only** by `legacyBuyStep` (`CauldronHook.sol:1016-1080`), which returns early unless `legacyRegistry != 0` and the buffer clears `legacyThreshold`. `CauldronHook` has **no** ETH sweep: the only withdrawals are `sweepLegacyReserve(address,address)` (`:1112`, ERC20 and `legacyRegistry`-gated) and `claimProposerFees()` (`:2060`). On a dead round this ETH can never leave. |

To recover any of these would take a new contract with authority over the old one — which does not exist, because
none of these contracts has an upgrade hook, a successor pointer, or an owner-callable sweep.

---

## 6. Record errors in the deployment JSONs

1. **`deployments/sepolia.json` (repo root) calls itself "CANONICAL … SINGLE SOURCE OF TRUTH" and is 18 rounds
   stale.** It records round **20**, registry `0x60f5e17f…`. That registry is real and has code, but its generation-1
   positions (38583/38584) are burned and it holds **71 wei**. The live round is **38**
   (`indexer/deployments/round.json`). Two files, each claiming to be the single source of truth, disagreeing by 18
   rounds, is the most dangerous record error here: `scripts/recover-live.sh` reads the *indexer* manifest and is
   therefore right, while anything reading the root manifest would point a break-glass at a stale registry.
2. **`contracts/solidity/deployments/sepolia.json`, `sepolia-final.json`, `sepolia-launch.json`** are all marked
   SUPERSEDED but every address in them is live code holding or having held value — `sepolia-launch.json`'s v7
   round alone still holds **2.799 ETH** of recoverable LP. They are not "history"; they are an active recovery list.
3. **`contracts/solidity/deployments/sepolia.json → canonical.CauldronRegistry` = `0x0dcc4D2d…`** has code but
   `summoned() == false`, `currentGeneration() == 0`. It was deployed and never ignited. Harmless, but it is not the
   "canonical autonomous launchpad" its note claims.
4. **Rounds 32, 33/34, 35, 37 and the ~r31 registry `0xF3d62139…` exist only in git history**, not in any file at
   HEAD. Round 32 alone holds 5.547 ETH.
5. **Three pre-r20 registries and eleven perp vaults holding 9.45 ETH appear in no file at all.** They were found
   only by deriving the deployer's CREATE addresses. Any recovery driven from the repo's JSONs would have missed
   **12.0 ETH** — about half of everything that is recoverable.
6. `indexer/deployments/round.json` lists `"poolIds": []` and `"deathThresholdEth": 0` for the live round while the
   live pool ids are readable on-chain from `generationPoolKey(1)`; cosmetic, but it means the manifest cannot be
   used to audit the live pool.

Everything in every JSON that was checked **does** have code on-chain — there are no phantom addresses. The errors
are staleness and omission, not fabrication.

---

## 7. The existing recovery scripts, judged against today's state

### `scripts/recover-old-lp.sh` — **would work, but not yet, and it under-recovers**
Hardcodes `REG=0x3FD7649F…` (round 33/34) and `TL=0x06705E8c…`. Both are correct and current for that round.
`emergencyReadyAt()` is `1789200300`, which has **not** elapsed, so the script's own guard exits with
"break-glass not ready yet" — correct behaviour. After it matures the script recovers **6.888108469848070785 ETH**
(VERIFIED by simulation), matching its comment. Two flaws: it schedules with a hardcoded `180`s delay instead of
reading `getMinDelay()`, and it never calls `emergencySweep`/`rescueSeeder`, so it leaves the seeder's 534 wei behind
(negligible here, but the pattern is wrong).

### `scripts/arm-old-emergency.sh` — **would work but is redundant now**
Same registry/timelock. The break-glass is already armed; re-arming just resets the 48 h clock **further into the
future**. Running it right now would *delay* the recovery in §3.2 by another two days. Do not run it.

### `scripts/reclaim-old-lp.sh` — **defaults to a round with nothing in it**
`OLD_REGISTRY` defaults to `0xF3d621392D8aaB7507E902cB2638d3bf934a4107` (~r31). That registry is real
(`currentGeneration() == 2`, `emergencyAdmin` = the deployer EOA, `emergencyDelay == 0`) but **both its reserve
positions, 38742 and 38743, are burned** and its balance is 0. Simulated recovery: **0 ETH**. The script itself is
the best-designed of the four — dry-run by default, refuses to send from the wrong signer, and correctly understands
that a progressive generation hides its book in the seeder — it is simply pointed at an empty round. Point it at
`0x56022128…` (r32) or `0x09579fbb…` (v7) with `OLD_REGISTRY=` and it recovers 5.547 / 2.799 ETH.
One real bug: it arms with `send "$OLD_REGISTRY" "armEmergency()"` **only when `DELAY != 0`**, but arming is
mandatory at any delay (`CauldronRegistry.sol:389`) — against a zero-delay post-audit registry every subsequent call
would revert `Timelocked()`. Its own comment says this ("post-audit builds require the arm at ANY delay — see F-19")
and the code then does the opposite.

### `scripts/recover-live.sh` — **would work, and would kill round 38**
Reads the registry from `indexer/deployments/round.json` (round 38 — correct), derives the timelock from the chain
rather than hardcoding it (correct), arms, waits `emergencyDelay` (600 s), withdraws, forwards. Simulated yield
**0.919104662239193331 ETH**. It does exactly what its header says, including the part that says it kills the round.
The one stale assumption is `DEP` defaulting to `0xc944…c133`: round 38's `emergencyAdmin` is the timelock
`0x3925859C…`, and the deployer is only the **guardian** — who can `vetoEmergency()` but cannot propose. The script
handles this correctly because it goes through the timelock, but anyone reading `DEPLOYER=` would assume the EOA has
break-glass rights on the live round, and it does not.

---

## 8. Counter-versus-balance divergences

| contract | counter | balance | divergence |
|---|---|---|---|
| `0x9Ef76332…` engine | `plv` 1 004 484 999 999 999 994 + `insuranceEth` 2 242 500 000 000 000 | 2 390 898 276 154 545 565 | **+1.384 ETH held above every counter** — unowned money |
| `0xC39d6Ed8…` engine | `plv` 1 580 103 632 648 771 669 | 1 721 895 101 558 904 782 | +0.142 ETH |
| `0xF6F3eB71…` engine | `plv` 362 810 149 999 999 991 + ins 862 500 000 000 000 | 648 672 837 658 690 984 | +0.285 ETH |
| `0xef1263c0…` engine | `plv` 0, `insuranceEth` 0 | 274 479 764 686 095 920 | **+0.274 ETH counted by nothing** |
| r38 / r33 / r35 hooks | `legacyBuffer` | identical to the wei | no divergence (the counters are honest) |
| r38 registry | `genesisReserveOutstanding` 108 779 999 999 999 999 999 999 869 | reserve position 39125 | entitlement, backed by LP, not by balance |

The three "+" rows are the same defect in different amounts: `PerpVault.withdrawEth` pays `min(owed, freeEth)` and
books the rest as `pendingEth`, so ETH above the share base is unreachable through the share path. It is not lost to
an attacker — it is simply addressed by no counter that any function reads.

### Not verified / where the RPC stopped me
- **Contracts deployed by contracts** (factory-made tokens, collections, vaults) are covered only where a registry or
  manifest named them. A factory-created contract that no registry points at would not appear here.
- **Positions outside id range 38270–39215** were not scanned. All ids actually referenced by every registry fall
  inside it, and my first range scan was discarded entirely because per-item RPC errors were coming back
  indistinguishable from "no owner" — an errored call is not a zero, and that scan was reporting live positions
  (39124, 38888) as burned. Every position id in this report was re-read individually with explicit error reporting.
- Two earlier batches **silently returned `0x`/error for `eth_getCode` and for a whole 60-call `eth_call` chunk**;
  both were caught and re-run. If any figure here looks like a suspicious zero, re-read it before acting on it.
