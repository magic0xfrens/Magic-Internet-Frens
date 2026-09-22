# Cross-chain genesis — mint on Ethereum, protocol on Robinhood (4663)

Design plan, rev. 2 · 2026-09-22. **Not built.** Supersedes rev. 1, which
recommended a soulbound-only mirror; that was written before the canonical
bridge and the current gas environment were checked, and both change the answer.

## Verified facts this rests on

| fact | source |
|---|---|
| LayerZero V2 deployed on 4663 | `docs.layerzero.network/v2/deployments/chains/robinhood` |
| OpenSea live on 4663, full collection tooling | OpenSea announcement |
| Canonical Arbitrum bridge, chainId 4663 / parent 1 | inbox `0x1A07cc4BD17E0118BdB54D70990D2158AbAD7a2D`, bridge `0xDf8755334ce7A73cCF6b581C02eA649AE3E864b3`, outbox `0xf0ce991ea4A0d2400A4AB49b20ae333f6Dce3DE9`, `confirmPeriodBlocks` 45818 |
| L1→L2 deposit ≈ **10 min**; L2→L1 ≈ **7 days** | Robinhood + Arbitrum docs |
| ETH/USD $2,479.60 | Chainlink `0x78F3…d3A9` on 4663, read live |
| Fren price `0.0062 ether` ≈ **$15.38** | `DeployLaunchpad.s.sol:136` |

**ESTIMATES, not measured:** every LayerZero fee below. They can only be
measured by calling `quote()` against deployed contracts. **This is now the
dominant cost term — measure it before committing to anything here (§10).**

---

## 1. What the design must deliver

1. Mint on Ethereum — that is where NFT credibility and buyers are.
2. **Hold on mainnet and still claim dividends/fees on Robinhood.** No forced
   bridging to participate.
3. Sell on OpenSea-mainnet *or* OpenSea-Robinhood, holder's choice.
4. Arb between NFT price and floor `F` available on both venues.
5. Never allow the same fren to be sold twice.

(2) and (3) together are why this is design **C**, not the simpler A or B.

---

## 2. The state machine

One mirror contract on 4663 with **one bit per token** — `locked[tokenId]` —
that tracks whether the mainnet NFT is in the vault.

```
                 syncOwner()                    lock()
   ┌──────────┐ ──────────────> ┌──────────┐ ───────────> ┌──────────┐
   │ UNSYNCED │                 │   HELD   │              │  LOCKED  │
   │ no mirror│ <────────────── │ mainnet: │ <─────────── │ mainnet: │
   └──────────┘   (never; only   │ WALLET   │   unlock()   │  VAULT   │
                   pre-ignition)  │ 4663:    │              │ 4663:    │
                                  │ soulbound│              │ transfer-│
                                  └──────────┘              │  able    │
                                    │                       └──────────┘
                    redeemFromMainnet()                        │
                                    ▼                          │ redeemOgFren()
                              ┌──────────┐                     │  (atomic)
                              │ IN_CUSTODY│ ───────────────────┤
                              │ transient │                    ▼
                              └──────────┘              ┌──────────┐
                                                        │ TREASURY │
                                                        │ resold 2F│
                                                        └──────────┘
```

| state | mainnet NFT | 4663 mirror | votes | dividends | floor redeem | sells on |
|---|---|---|---|---|---|---|
| **UNSYNCED** | wallet, tradeable | none | ✗ | ✗ | ✗ | OpenSea-mainnet |
| **HELD** | wallet, **tradeable** | **soulbound** | ✅ | ✅ | mainnet-initiated | OpenSea-mainnet |
| **LOCKED** | **vault, frozen** | **transferable** | ✅ | ✅ | **atomic on 4663** | OpenSea-Robinhood |
| IN_CUSTODY | escrow | frozen | ✗ | ✗ | in flight | — |
| TREASURY | vault | treasury-held | ✗ | ✗ | — | `buyTreasuryOgFren` at 2F |

### THE INVARIANT

> **Exactly one side of a fren is transferable at any moment.**

HELD: mainnet moves, mirror is soulbound. LOCKED: mirror moves, mainnet is
frozen in the vault. Double-spend is impossible **structurally**, not by timing —
there is no window to race, because the other side is inert by construction.

Every safety question in this design reduces to whether that invariant holds
through a transition. **Any new transition must be checked against it.**

---

## 3. Why HELD can claim dividends but not the floor

The sync gap is real: Alice sells on OpenSea-mainnet, and until someone calls
`syncOwner`, the mirror still names Alice.

| right | what Alice can take in the gap | verdict |
|---|---|---|
| dividends | accrued-but-unclaimed | **acceptable.** A rational seller claims *before* selling anyway, so the gap enables nothing she could not do legitimately. Buyers price in "unclaimed may be zero", as with any rewards-bearing NFT. `MiFrensDividend` already breaks `enchantedBy` on transfer; the mirror replicates that on sync. |
| votes | one vote she sold | **acceptable.** Bounded by the `block.number - 1` snapshot; ordinary vote-rental risk, present on mainnet-only NFTs too. |
| **floor redeem** | **`F` of real ETH, and the fren's backing is destroyed** | **NOT acceptable.** Alice extracts the sale price *and* the floor. Theft. |

The principle: **dividends are a flow** — small, continuous, self-limiting.
**The floor is a stock** — large, one-shot, and redeeming destroys the asset's
backing permanently. That is why only the third is gated.

---

## 4. The two redeem paths

### Path 1 — from HELD, mainnet-initiated

```
mainnet:  redeemFromMainnet(tokenId, minOut)
            require ownerOf(tokenId) == msg.sender
            custodyTransfer(msg.sender -> escrow)     ← IRREVERSIBLE, LOCAL, FIRST
            lzSend(REDEEM, tokenId, msg.sender, minOut)

4663:     F = floorPerFren()                          ← COMPUTED AT PAYOUT TIME
          if (F < minOut) -> lzSend(REDEEM_REFUSED) and stop
          genesisReserveOutstanding -= F
          treasuryHeldOg += 1
          mirror -> treasury
          claimFromReserve(..., F, redeemer)
```

Ordering is load-bearing: **custody moves before any value is released.** If the
message is slow the redeemer waits; they can never double-claim.

### Path 2 — from LOCKED, atomic on 4663

```
4663:     redeemOgFren(tokenId, minOut)
            require mirror.ownerOf(tokenId) == msg.sender
            F = floorPerFren();  require F >= minOut
            ... existing logic, entirely local ...
```

Safe because the mainnet NFT is **frozen in the vault** — the mirror is
authoritative, so the ownership check and the payout are atomic, exactly as they
are on a single chain today. The mainnet token stays in the vault while the fren
is treasury-held; whoever buys it at `2F` can unlock.

**This path is what makes `F` a hard floor** — buy the mirror below `F` on
OpenSea-Robinhood and redeem in the same transaction. Flashloanable, spread
compresses to gas.

### `F` MUST be computed at payout — settled

`floorPerFren()` moves: `redeemOgFren` does `genesisReserveOutstanding -= F` and
`treasuryHeldOg += 1`, both of which change the divisor.

Quoting `F` at mainnet initiation and honouring it at payout hands arbs a **free
option** — fire a batch when `F` is high and the protocol is committed to a stale
`F` as the reserve drains. **Critical if built that way.** Therefore the mainnet
call cannot promise an amount; it takes a **`minOut`** and the UI must say the
payout is whatever `F` is on arrival.

---

## 5. Which rail carries what, and why

| what | rail | time | trust |
|---|---|---|---|
| **Ignition value (6.89 ETH, L1→L2, once)** | **canonical bridge** | ~10 min | **trustless** — inherits Ethereum |
| Ignition owner roster | LayerZero | minutes | DVN set |
| `syncOwner`, `lock`, `unlock`, redeem msgs | LayerZero | minutes | DVN set |

**The money never depends on a DVN.** The canonical bridge is trustless but its
L2→L1 leg takes **7 days** — fine for a one-way ignition deposit, fatal for
anything needing a round trip. That is exactly why everything ongoing uses
LayerZero: a 7-day unlock would kill the arb, which is the point of the design.

**This is a real trade, stated plainly: you are buying arb efficiency with trust
assumptions.** A compromised DVN set could release frens from the vault. It
cannot touch the presale proceeds.

---

## 6. Ignition flow

```
mainnet: igniteCauldron()                     [requires minted == 1111]
  ├─ inbox.createRetryableTicket{value: ~6.89 ETH}(
  │      to: registry (4663), l2CallValue: 6.89 ETH, data: summon() )
  │    └─ ~10 min → summon() runs ON 4663 WITH the value
  │                 → token, pool, LP, reserve
  └─ ~12 × lzSend(MIRROR_MINT, [~100 × (tokenId, owner)])
       └─ mirror mints soulbound tokens, checkpoints votes
```

**Batching the roster is what keeps rights free.** ~12 messages × ~$2 ≈ **$24
total, amortised over 1,111 frens ≈ 2 cents each**, paid from presale proceeds.
Every holder has votes and dividends at ignition without paying a toll — which
also removes a governance-capture surface, since rights are not rationed by
whoever finds them worth a bridging fee.

### Address aliasing — will break ignition if missed

When an L1 contract calls L2 via a retryable ticket, `msg.sender` on 4663 is the
**aliased** address (L1 address + `0x1111000000000000000000000000000000001111`),
not the presale address.

**`summon()`'s access control must expect the alias.** Get this wrong and
ignition reverts *on arrival*, after the ETH has already crossed. Use the
Arbitrum SDK's `applyAlias` when computing the expected caller, and assert it in
a fork test before mainnet.

---

## 7. Costs (at 0.171 gwei, the current mainnet rate)

| action | mainnet gas | gas cost | LZ fee (EST) | total (EST) |
|---|---|---|---|---|
| `syncOwner` | ~150k | $0.06 | $0.50–2.50 | **$0.56–2.56** |
| `lock` (→ LOCKED) | ~200–270k | $0.09–0.11 | $0.50–2.50 | **$0.59–2.61** |
| `unlock` (→ HELD) | ~4663-side only | cents | $0.50–2.50 | **~$0.50–2.50** |
| ignition roster | — | — | ~$24 total | **~2¢/fren** |

Mainnet gas is now ~4% of the cost; **the LZ fee is ~90%.** At 50 gwei the lock
cost rises to ~$25, but these actions are **deferrable** — a holder simply waits
for cheaper gas, unlike ignition, which is one-shot.

Mainnet transfers are expensive relative to a plain ERC721 because
`MiFrensGenesis` is `ERC721Votes`: a transfer moves voting units and writes
checkpoints for both parties, plus the `genesisBalanceOf` SSTORE in `_update`.

---

## 8. Failure modes — answer before writing Solidity

1. **Redeem message never lands.** Fren in escrow, no payout. Needs a replay
   path and a timeout returning custody. **The worst failure here — solve first.**
2. **`minOut` not met at payout.** Fren already in escrow. `REDEEM_REFUSED`
   returns custody — an extra message, and its own failure mode. Alternative:
   hold the claim open until `F` recovers. **Owner decision.**
3. **Unlock message never lands.** Mirror already soulbound, NFT still in vault.
   Holder has rights but cannot retrieve the token. Replayable — and **`unlock()`
   must freeze the mirror BEFORE sending**, never after, or the mirror could be
   sold while the vault releases to its former owner.
4. **Retryable ticket fails on arrival** (under-provisioned L2 gas). Arbitrum
   allows **manual redemption within 7 days**. For a one-shot ignition this needs
   an operator runbook, not a hope.
5. **Ignition roster partially delivered.** Some holders have rights, some do
   not. Per-chunk replay required, and quorum must not be read until all chunks
   land (§9).
6. **LayerZero down at ignition.** Roster can be sent later; `summon` must not
   block on it. Order the ticket first.

---

## 9. The quorum trap — do not repeat R46's

`TreasuryGovernor` computes
`getPastTotalSupply(snapshot) * QUORUM_BPS / 10_000`.

Measured against the full 1,111 while only some are mirrored → **governance
unreachable**. Measured against mirrored supply → a small mirrored minority can
pass proposals. Batched ignition mirroring makes all 1,111 live on day one, which
mostly dissolves it — but the invariant must still be asserted:

> **Quorum is measured against the same trace the votes come from.**

A regression test must prove a proposal stays executable under a partial mirror.

---

## 10. DVN configuration — the security decision

The mirror's rights model depends entirely on message authenticity. The protocol
has **no cross-chain trust dependency today**; this adds one.

- **Never ship the default single-DVN config.** Require **≥2 independent DVNs**
  for rights messages (`syncOwner`, roster) and **≥3 for vault release**
  (`unlock`), which is the highest-value message in the system.
- **Guardian pause** on the mirror mint path and the vault release path,
  reachable without a governance cycle.
- Cap what a single message can do — no unbounded batch releases.

**Step zero before any contracts: deploy a trivial OApp on both chains and call
`quote()` for a realistic payload.** The LZ fee is ~90% of the running cost and
is currently an estimate. A few hours removes the largest unknown from an
architectural decision.

---

## 11. What changes in existing contracts

**Nothing in `TreasuryGovernor`, `RedemptionExt` or `MiFrensDividend`.** They
read `IVotes721` / `IERC721` interfaces, so pointing them at the mirror is a
constructor argument.

New, all standalone:
- `MiFrensMirror` (4663) — ERC721Votes, `locked[tokenId]` gates transferability
- `GenesisOutbox` (mainnet) — LZ OApp + retryable-ticket sender
- `GenesisVault` (mainnet) — custody for LOCKED, releases to the address the
  unlock message names (**never to the depositor** — the mirror may have been
  sold since)

**Size constraint:** `CauldronRegistry` has **8 bytes** of EIP-170 headroom, and
`CauldronBase` is where inherited getters cost the registry directly. **Nothing
here may be added to `CauldronBase`.** All new contracts stand alone.

---

## 12. Open decisions

1. **`minOut` failure (path 1):** return custody, or hold the claim open?
2. **Does burn-for-iteration-tokens exist at all?** It conflicts with the OG
   floor ratchet, which deliberately does **not** burn — `redeemOgFren` moves the
   fren to the treasury for 2× resale, and that resale *is* the ratchet.
3. **DVN set and thresholds** (§10).
4. **Who funds the ignition roster** — presale proceeds, or deployer?
5. **Does `HELD` require an explicit `syncOwner` after every mainnet sale, or is
   there a keeper?** Permissionless + buyer-pays is the default; a keeper is
   nicer UX but needs funding.

---

## 13. Build order

1. **Measure the LZ fee** (§10). Everything else is priced off it.
2. Write the state machine as a test harness — transitions only, no value — and
   assert the invariant (§2) holds through every one, including failures.
3. `MiFrensMirror` + `syncOwner`. Gets HELD working: rights on Robinhood, NFT on
   mainnet. **This alone satisfies the primary requirement.**
4. Ignition path: retryable ticket + roster batching, with the aliasing test.
5. `GenesisVault` + lock/unlock. Adds LOCKED and OpenSea-Robinhood.
6. Path-2 redeem (atomic). Adds the hard floor.
7. Path-1 redeem (mainnet-initiated) with `minOut` and the custody-return path.

Steps 3–4 deliver what you asked for. Steps 5–7 add the second venue and the hard
floor, and can ship separately with their own adversarial pass.
