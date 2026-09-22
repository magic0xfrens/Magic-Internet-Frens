# Cross-chain genesis — mint on Ethereum, protocol on Robinhood (4663)

Design plan, 2026-09-22. **Not built. Every number marked ESTIMATE is an
estimate**, because LayerZero fees can only be measured by calling `quote()`
against deployed contracts, and these contracts do not exist yet.

Verified facts this plan rests on:
- LayerZero V2 is deployed on 4663 — endpoint, DVN and executor addresses at
  `docs.layerzero.network/v2/deployments/chains/robinhood`.
- OpenSea supports 4663 with full collection tooling (floors, offers, rarity).
- ETH/USD on 4663 is $2,479.60 (Chainlink `0x78F3…d3A9`, read live).
- A fren costs `PRESALE_PRICE = 0.0062 ether` ≈ **$15.38**.

---

## 0. The cost problem, first — because it decides the architecture

Per-fren, per-direction, ESTIMATED:

| component | gas | notes |
|---|---|---|
| `transferFrom` into vault (mainnet) | 80–120k | `MiFrensGenesis` is `ERC721Votes`; a transfer moves voting units and writes checkpoints for both parties, plus the `genesisBalanceOf` SSTORE in `_update` |
| `_lzSend` (mainnet) | 100–150k | encoding + endpoint + DVN payment |
| **mainnet total** | **~200–270k** | |
| LayerZero fee | — | 0.0002–0.001 ETH = **$0.50–$2.50** |
| 4663 execution | 100–150k | paid by the executor out of the LZ fee; Orbit L2 gas, cents |

**Total: ~$7 at 10 gwei, ~$19 at 30 gwei, ~$37 at 60 gwei.**

Against a **$15.38** fren, that is **0.5× to 2.4× the mint price**. Bridging one
fren can cost more than the fren.

**This is the finding that shapes everything else.** A design requiring each
holder to individually bridge will see low adoption at launch valuations, and the
rights would concentrate in whoever finds them worth a $20 toll — which is a
governance-capture surface, not just a UX problem.

### The mitigation that actually works: batch at ignition

At ignition the presale knows all 1,111 owners. Send them as batched messages —
roughly 100 `(tokenId, owner)` pairs per message, ~12 messages — **paid once out
of presale proceeds**:

```
12 messages x ~$2 = ~$24 total, amortised over 1,111 frens = ~2 cents each
```

Every genesis holder's rights go live on 4663 at ignition, **free to them**. Only
*subsequent* transfers need an individual sync, and by then the fren has a market
price that justifies the toll or it does not.

---

## 1. Three architectures, and what each costs

### A — Soulbound mirror (mainnet stays free)

The 4663 mirror is **non-transferable**. It carries votes and dividends. The
mainnet NFT is never locked and trades normally on OpenSea-mainnet.

- Batched ignition mirroring works (nothing needs locking) → **free to holders**
- `redeemOgFren` must be **mainnet-initiated**: the `ownerOf` check and
  `custodyTransfer` happen on mainnet, then a message releases `F` on 4663
- Floor arb becomes **non-atomic** → the floor is soft, spread widens by latency
  and two-chain inventory cost
- No OpenSea-Robinhood market for frens

### B — Lock-and-mirror (venue follows the live side)

The mainnet NFT locks in a vault; a **transferable** mirror mints on 4663.

| state | mainnet | 4663 |
|---|---|---|
| dormant | in wallet, tradeable on OpenSea-mainnet | nothing |
| active | locked in vault | mirror tradeable on OpenSea-Robinhood, carries all rights |

- **Exactly one side is transferable at any moment** — the invariant that makes
  double-spend structurally impossible rather than timing-bounded
- `redeemOgFren` stays **entirely on 4663**: check `ownerOf` on the mirror, pay
  from the reserve, same transaction. **Atomic, flashloanable, hard floor** —
  identical to today
- Two-way arb (buy mirror → unwrap → sell mainnet, and the reverse) ties the two
  venues within round-trip friction, so you get one floor observed twice, not two
- **Cannot be batched at ignition** — you cannot lock NFTs you do not custody, so
  every holder pays the $7–37 toll themselves

### C — Hybrid

A as the default (free, batched, rights live for everyone at ignition); B as an
opt-in upgrade for holders who want to trade on 4663 or redeem atomically.

Best properties, most surface area, two code paths through the rights system.

---

## 2. Recommendation

**Ship A. Document B as the v2 path. Do not build C first.**

Reasoning: the launch-critical property is that **all 1,111 holders have rights
without paying a toll comparable to the mint price.** Only A delivers that. B's
advantage — the atomic floor arb — matters most when the collection is valuable,
which is exactly when per-fren bridging becomes affordable and B becomes
reachable as an upgrade.

A's real cost is a soft floor. That is acceptable at launch because the floor is
funded by the legacy-buyback slice and is small in absolute terms early on.

**B is strictly better once frens are worth >$200.** Build it then, with its own
adversarial pass.

---

## 3. The rule that decides every case

> **Value-consuming actions initiate on the chain where the NFT lives.
> Read-only, snapshot-based rights mirror.**

Applied:

| right | where | why |
|---|---|---|
| `getVotes` / `getPastVotes` | **4663 mirror** | governor reads synchronously at `block.number - 1`; cannot be a cross-chain call |
| dividends | **4663 mirror** | `enchantedBy[tokenId] != ownerOf(tokenId)` already gates staleness — a sync that changes owner clears enchantment |
| `redeemOgFren` (design A) | **mainnet-initiated** | pays real ETH; the `ownerOf` check must be atomic with `custodyTransfer` |
| `buyTreasuryOgFren` | **4663** | no mainnet NFT involved until unwrap |

---

## 4. `F` MUST be computed at payout time — settled

`floorPerFren()` moves: `redeemOgFren` does `genesisReserveOutstanding -= F` and
`treasuryHeldOg += 1`, and both change the divisor.

- **Quote at mainnet initiation, honour at payout** → a **free option**. Initiate
  a batch when `F` is high and the protocol is committed to the stale `F` as the
  reserve drains. A bot does this at scale and drains the reserve. **Critical.**
- **Compute at 4663 payout time** → the redeemer carries the risk, which is how
  it behaves today. **This is the decision.**

Consequence: the mainnet call **cannot promise an amount**. It is "redeem this
fren, receive whatever `F` is when it lands." The UI must say so, and the call
must take a **`minOut`** so a redeemer can bound their own downside rather than
eating an unbounded move.

---

## 5. Message flows (design A)

**Ignition batch** — presale, once, paid from proceeds:
```
mainnet: igniteCauldron()
  -> summon value to 4663 (existing path)
  -> for each chunk of ~100 owners: lzSend(MIRROR_MINT, [(tokenId, owner)...])
4663:  mirror mints soulbound tokens, checkpoints votes
```

**Ongoing sync** — permissionless, caller pays:
```
mainnet: syncOwner(tokenId)          // reads ownerOf, no custody change
  -> lzSend(OWNER_SYNC, tokenId, owner)
4663:  mirror reassigns; clears enchantment if the owner changed
```
Permissionless and caller-paid is deliberate: `transferFrom` is **not payable**,
so a fee cannot ride inside a transfer, and a prefunded fee pool is drainable by
spam transfers. The buyer pays because the buyer wants the rights.

**Floor redeem** — mainnet-initiated:
```
mainnet: redeemOgFrenCrossChain(tokenId, minOut)
  -> require ownerOf == msg.sender
  -> custodyTransfer(msg.sender -> registryProxy)   // irreversible, local, FIRST
  -> lzSend(REDEEM, tokenId, msg.sender, minOut)
4663:  F = floorPerFren()           // PAYOUT TIME
       require F >= minOut
       genesisReserveOutstanding -= F; treasuryHeldOg += 1
       claimFromReserve(..., F, redeemer)
```
Ordering is load-bearing: **custody moves before any value is released.** If the
message is slow the redeemer waits; they can never double-claim.

---

## 6. Failure modes that need answers before code

1. **Redeem message never lands.** The fren is in custody, no payout. Needs a
   replay path, and a timeout that returns custody if the message is provably
   dead. **This is the worst failure in the design — solve it first.**
2. **`minOut` not met at payout.** The fren is already in custody. Return it
   (another message) or hold the claim open? Returning is safer; holding is
   cheaper. **Owner decision.**
3. **Ignition batch partially delivered.** Some holders have rights, some do not.
   Must be replayable per chunk, and `getPastTotalSupply` must not be read for
   quorum until every chunk lands (see §7).
4. **LayerZero down at ignition.** Ignition is one-shot and irreversible. Needs a
   manual path that does not block `summon`.

---

## 7. The quorum trap — do not repeat R46's

`TreasuryGovernor` measures quorum as
`getPastTotalSupply(snapshot) * QUORUM_BPS / 10_000`.

If quorum is measured against the **full 1,111** while only some holders are
mirrored, **governance is unreachable** — the exact denominator trap investigated
this run. If measured against **mirrored supply**, a small mirrored minority can
pass proposals.

With batched ignition mirroring, all 1,111 are mirrored from day one and the
question mostly dissolves — but the invariant still has to be asserted:
**quorum is measured against the same trace the votes come from.** A test must
prove a proposal remains executable after a partial mirror.

---

## 8. New trust assumption — name it plainly

The protocol today has no cross-chain trust dependency. This adds one: **the
mirror's rights model depends entirely on message authenticity.** A compromised
DVN set could mint mirrors, which are votes and dividend claims; in design B it
could release NFTs from the vault outright.

Mitigations: multiple independent DVNs (never the default single-DVN config), a
cap on what one message can do, and a guardian pause on the mirror's mint path.

---

## 9. What changes in existing contracts

**Nothing in `TreasuryGovernor`, `RedemptionExt` or `MiFrensDividend`** — they
already read an `IVotes721` / `IERC721` interface, so pointing them at the mirror
is a constructor argument.

New: `MiFrensMirror` (4663, ERC721Votes, soulbound in A), `GenesisOutbox`
(mainnet, LZ OApp), and in design B a `GenesisVault` (mainnet).

**Size:** `CauldronRegistry` has **8 bytes** of EIP-170 headroom and
`CauldronBase` is where inherited getters cost the registry directly. Anything
that adds a public getter there blows it. The new contracts must be standalone —
not additions to `CauldronBase`.

---

## 10. Open decisions

1. **A, B, or C.** (Recommendation: A now, B at >$200/fren.)
2. Redeem `minOut` failure: return custody, or hold the claim open?
3. Does burn-for-iteration-tokens exist at all? It conflicts with the OG floor
   ratchet, which deliberately does **not** burn — `redeemOgFren` moves the fren
   to the treasury for 2× resale, and that resale is the ratchet.
4. DVN set and threshold.
5. Who funds the ignition batch — presale proceeds, or the deployer?
