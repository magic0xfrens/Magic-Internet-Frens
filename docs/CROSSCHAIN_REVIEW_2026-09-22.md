# Cross-chain genesis — review of rev. 2 + sketch for rev. 3

2026-09-22 · reviews `docs/CROSSCHAIN_GENESIS_PLAN.md` (rev. 2) and
`docs/CROSSCHAIN_REVIEW_BRIEF.md` against HEAD `72832ad`. Every contract file
cited below is **clean against HEAD** (`git status` on `contracts/solidity/*.sol`
and `cauldron/` is empty), so nothing here is dirty-tree contamination.

**Still nothing is built.** Measurements below were taken live on 2026-09-22 and
are labelled with their conditions.

---

## 0. Verdict

The plan's core is right: one transferable side per fren, and a floor that is
atomic only where the mirror is authoritative. Four things change:

1. **LayerZero isn't needed for v1.** Three of the four message types go
   L1→L2 (roster, sync, lock). The canonical Arbitrum inbox carries those for
   **~$0.07** instead of ~$0.60, with **no trust beyond 4663 itself**. The floor
   arb never needs the L2→L1 leg. LZ becomes an optional fast-unlock add-on.
2. **The "mirror" is not a small new contract.** It *is* the canonical 4663
   collection: a fork of `MiFrensGenesis` minus the presale, plus bridge state.
   That is also what makes "no changes to existing contracts" true.
3. **Path 1 collapses into `lock` + Path 2.** That removes the escrow, the
   REDEEM/REDEEM_REFUSED messages, `minOut`, failure modes #1 and #2, and open
   decision #1.
4. **Build the mainnet side with multiple spokes in mind from the start.**
   Mainnet contracts are the only ones you can never redeploy, because the NFT
   address is the collection's identity. If `home[tokenId]` stores a spoke id
   rather than a boolean, adding "iteration on another chain" later is a
   configuration change instead of a migration (§3).

---

## 1. The brief's six claims — checked

| # | claim | verdict | evidence |
|---|---|---|---|
| 1 | `igniter` must hold the aliased address | **Real, but avoidable.** `igniter` is **settable**, not immutable: `setIgniter(address) onlyOwner`, `CauldronRegistry.sol:420`. The check is at `:731` (the brief cites `:728`, the comment line). Better: keep the alias out of the registry entirely (F6). | read |
| 2 | LZ fee $0.50–2.50/msg | **In range. Measured below.** L1→4663 messages sit at the bottom of the range (~$0.58–0.61); 4663→L1 in the middle (~$1.61). | executor + DVN `getFee` on both chains |
| 3 | LZ on testnet 46630 unconfirmed | **Confirmed.** EndpointV2 `0x3aCAAf60502791D199a5a5F0B173D78229eBFe32`, `eid() = 40451`. Mainnet 4663: `0x6F475642a6e85809B1c36Fa62763669b1b48DD5B`, `eid() = 30416`. | `cast call … eid()` |
| 4 | Transfer gas 200–270k | **About right for `MiFrensGenesis` as it stands.** Measured below. The fix is not to ship that contract to mainnet (F8). | forge, cold slots |
| 5 | "Exactly one side transferable" | **Holds through the plan's transitions**, but the load-bearing line is somewhere the plan doesn't name, and the plan's boolean name collides with ERC-5192 (F3). | `RedemptionExt.sol:80-98` |
| 6 | Dividends are a flow, the floor a stock | **Holds for one spoke.** The sync gap is the M-06 shape (the seller earns during the buyer's ownership), bounded by how fast the buyer syncs. It becomes **unbounded with a second spoke** unless rights are suspended there (§3.3). | `MiFrensGenesis.sol:870-876` |

### Canonical bridge — verified on L1

| check | result |
|---|---|
| `inbox(0x1A07…7a2D).bridge()` | `0xDf8755334ce7A73cCF6b581C02eA649AE3E864b3` ✅ |
| `bridge.allowedDelayedInboxes(inbox)` | `true` ✅ |
| `rollup(0x23A1…2D94).chainId()` | `4663` ✅ (settles to **Ethereum**, not Arbitrum One. This answers the open "Verify" in `ROBINHOOD_L2_REVIEW.md`.) |
| `rollup.outbox()` | `0xf0ce991e…3DE9` ✅ |
| `rollup.confirmPeriodBlocks()` | `45818` → **~6.4 days** at 12 s |
| `rollup.validatorWhitelistDisabled()` | **`false`**: validation is permissioned |
| rollup admin slot | `0x5526…b4bf` |

"Trustless" in plan §5 should read **"no trust beyond 4663 itself"**. L2→L1 relies
on 4663's whitelisted validators and its upgrade admin, which is the same trust
the protocol already places in the chain it runs on. For L1→L2 the point is
stronger: the message is executed *by 4663*, so a canonical deposit adds
**zero** new trust. LayerZero adds a DVN set.

### Measured: LayerZero fees

Conditions: L1 base fee 0.068 gwei (gas price 0.078), 4663 gas price
0.054 gwei, ETH = **$2,750.17** (L1 Chainlink `0x5f4e…8419`; the plan's
$2,479.60 is stale). `EndpointV2.quote()` **reverts** for an unconfigured OApp on
this pathway (`"Please set your OApp's DVNs and/or Executor"`). The default ULN
config points at a dead DVN (`0x747C…f6Ac`), so fees were summed directly from
the executor's and each DVN's `getFee`, which is what `quote()` does internally.
LZ treasury fee: `0`. Source-chain gas for `lzSend` is **not** included.

| message | executor (wei) | + DVNs | total | USD |
|---|---|---|---|---|
| sync, L1→4663, 128 B, 150k gas | 199.31e12 | 2 × ~5.3e12 | 209.96e12 | **$0.58** |
| lock, L1→4663, 128 B, 300k gas | 207.16e12 | 2 × ~5.3e12 | 217.81e12 | **$0.60** |
| roster batch, 6.4 KB, 5M gas | 458.53e12 | 2 × ~5.3e12 | 469.18e12 | $1.29 |
| roster batch, 6.4 KB, 12M gas | 825.08e12 | 2 × ~5.3e12 | 835.73e12 | $2.30 |
| unlock, 4663→L1, 128 B, 150k gas | 567.35e12 | 3 × ~6.6e12 | 587.05e12 | **$1.61** |

The executor fee is almost all a **fixed base** (~0.000195 ETH outbound from L1,
~0.00056 ETH outbound from 4663). Gas is a rounding error. Each DVN costs
**~$0.015–0.018**, so cost is never a reason to run fewer than 3.

DVNs live on **both** ends (LZ metadata API): LayerZero Labs, Nethermind,
Horizen, BitGo, Paxos, Luganodes, P2P, Canary, StablecoinX, Superform, Frax,
Nansen.

### Measured: canonical L1→L2 (retryable ticket)

| component | value |
|---|---|
| `createRetryableTicket` L1 gas (128 B payload) | **101,306** (`cast estimate`, incl. 21k base) → ~$0.02 |
| submission fee, 128 B / 6.4 KB | 1.47e11 / 2.69e12 wei, negligible |
| L2 execution, 300k gas @ 0.054 gwei | ~16e12 wei → ~$0.045 |
| **total per sync/lock** | **≈ $0.07**, about 8× cheaper than LZ, no new trust |
| roster batch (6.4 KB, 10M L2 gas) | ≈ $1.55. Same as LZ, because minting on 4663 dominates |

At 50 gwei L1 both rails cost roughly $14 per message, set by L1 gas, and the
plan's "deferrable" argument applies unchanged.

### Measured: mainnet transfer gas (execution only, cold slots, first-time recipient)

| contract | exec gas |
|---|---|
| `MiFrensGenesis` (ERC721Votes), no dividend wired | **182,853** |
| same + dividend hook (no-op mock) | 184,142, **plus 54k–202k for the real hook**, and `_update` refuses to run with < **320k** gas left (`MiFrensGenesis.sol:110-111, 898`) |
| plain ERC721 + `everMoved` bit | **63,559** |
| plain OZ ERC721 | 41,054 |

Harness: `/tmp/gasprobe` (outside the repo), OZ 5.6.1, solc 0.8.30, 200 runs.

---

## 2. Findings against the plan

Ordered by cost if missed.

### F3 · CRITICAL IF MISSED — the floor guard is one line in the mirror, and the plan's name for it is inverted by ERC-5192

`redeemOgFren` checks only `IERC721(mifrens).ownerOf(id) == msg.sender`
(`RedemptionExt.sol:86`), then calls `custodyTransfer(msg.sender → registry)`
(`:98`). A HELD mirror's `ownerOf` returns the mainnet holder. So with
`RedemptionExt` unmodified, **the only thing between a HELD holder and the §3
theft (sell on OpenSea-mainnet, then redeem `F` on 4663 in the sync gap) is
`mirror.custodyTransfer` reverting for a non-vaulted OG id.** The plan never
names this line. It needs its own regression test: *HELD holder calls
`redeemOgFren` → revert*.

The plan's bit is `locked[tokenId] == true` ⇒ **transferable**. ERC-5192, which
the mirror should implement so OpenSea shows HELD frens as soulbound, defines
`locked(tokenId) == true` ⇒ **non-transferable**. Shipping both inverts the most
important boolean in the system at the interface boundary. **Rename the plan's
bit to `vaulted`** (or `home == this spoke`).

### F1 · ARCHITECTURE — L1→L2 messages don't need LayerZero

| message | direction | canonical | LZ |
|---|---|---|---|
| roster | L1→L2 | ~10 min, ≈$1.55/batch, no new trust | ≈$1.3–2.3/batch, DVN trust |
| `syncOwner` | L1→L2 | ~10 min, **≈$0.07**, no new trust | **≈$0.58**, DVN trust |
| `lock` | L1→L2 | ~10 min, **≈$0.07**, no new trust | **≈$0.60**, DVN trust |
| `unlock` | L2→L1 | **~6.4 days**, trust = 4663 validators | minutes, **≈$1.61**, DVN trust |

Plan §5 says "a 7-day unlock would kill the arb, which is the point of the
design." It would kill only the **cross-venue** arb (mirror cheap on Robinhood,
NFT dear on mainnet). The **floor** arb never touches unlock:

- mirror below `F` on OpenSea-Robinhood → `redeemOgFren`, atomic on 4663;
- NFT below `F` on OpenSea-mainnet → `lock` (L1→L2, 10 min) → `redeemOgFren`.

**v1 can ship with zero third-party trust.** The DVN question (§10, open
decision #3) then becomes "do we want fast unlock at all?" If yes, make it a
**per-token opt-in chosen at lock time** on mainnet: the vault accepts an LZ
release only for tokens whose owner opted in. A compromised DVN set can then
release only the tokens that chose speed, not the whole vault.

### F2 · SCOPE — the mirror is the canonical 4663 collection

"Pointing them at the mirror is a constructor argument" is true, but only
because the mirror has to answer **every** call the 4663 stack makes on
`mifrens`:

| caller | calls | where |
|---|---|---|
| `RedemptionExt` | `ownerOf`, `custodyTransfer` | `:86, :98, :125, :136` |
| `CauldronRegistry` | `balanceOf` (auto-migrate tier); `setVault`, `setMinter`, `totalMinted` at gen 2 | `:1359, :1258-1259` |
| `MiFrensDividend` | `ownerOf`, `GENESIS_SUPPLY`, `MAX_SUPPLY`, `everMoved`; **and must be pinged from `_update`** | `:177-181, :508, :523` |
| `TreasuryGovernor` | `getVotes`, `getPastVotes`, `getPastTotalSupply` | `:416, :474, :996` |
| **`CauldronGovernor`**, missing from the plan | `getVotes`, `getPastVotes` | `:506, :659` |
| `PerpEngine` | `balanceOf` (OG fee discount) | `:2314` |
| hook / `GachaLib` (gen 2) | `mint(to)`, `totalMinted`, `maxSupply` | `GachaLib.sol:214-246` |
| hook (gen 2) | `setLiquidatorMinter` → badges via `mintLiquidatorWithStats` | `CauldronHook.sol:2313` |
| `PoolOps` | `GENESIS_SUPPLY` staticcall (OG-tranche guard), `custodyTransfer` | `:1610, :1650` |

**Iteration #2's forged tranche (ids 1112..2222) is 4663-native.** The plan
never mentions it. On gen 2 the registry continues `mifrens` (`:1138`), so the
mirror must mint above `GENESIS_SUPPLY` natively, and those ids are freely
transferable with no bridge state.

→ **Build the mirror as a fork of `MiFrensGenesis`** (21,831 B, 2,745 B
headroom). Remove `mint(qty)`, `refund`, `cancelPresale`, `igniteCauldron`,
`setMaxPerWallet`, `paid`, `genesisMintedBy`; add roster/sync/lock/unlock and
the `vaulted` gate. Roster minting must advance `minted` to 1111 so the volume
mint starts at 1112, and must set `revealed`. **Keep transport logic out of the
mirror:** a separate port contract the mirror trusts keeps LZ's OApp base (and
the EIP-170 bytes it costs) out of the mirror, and it is what makes spoke 2
pluggable.

### F4 · SIMPLIFICATION — Path 1 is `lock` + Path 2

The holder already needs a 4663 account, because dividends and votes are
claimed there. A "mainnet-initiated redeem" can therefore be `lock(tokenId, me)`
(~10 min) followed by `redeemOgFren` on 4663 at the live `F`. This deletes:

- the escrow state (IN_CUSTODY) and two message types (REDEEM, REDEEM_REFUSED);
- `minOut` and its failure path (open decision #1);
- failure modes #1 ("the worst failure here — solve first") and #2;
- a **registry change the plan didn't cost**: Path 1's pseudo-code pays
  `claimFromReserve(..., redeemer)`, but today that only runs inside
  `redeemOgFren` with `msg.sender` as payee. Paying someone else needs a new
  entrypoint in a registry with **8 bytes** free.

### F5 · CORRECTION — `F` isn't ETH, and redemptions don't drain it

- `F` is paid in the **current generation's token** from the out-of-range
  reserve LP (`PoolOps.claimFromReserve`). §3 says "`F` of real ETH."
- `floorPerFren = genesisReserveOutstanding / (shares − treasuryHeldOg)`
  (`CauldronBase.sol:455-472`). A redeem subtracts `F` and adds one to
  `treasuryHeldOg`: `(nF − F)/(n − 1) = F`. **Exactly floor-neutral.**

§4's "free option … as the reserve drains" is therefore the wrong reason. The
conclusion (compute `F` at payout) is still right, for a different reason: a
**relaunch** between initiation and payout changes which token `F` is paid in.
With F4 the question disappears.

### F6 · IGNITION — don't aim the retryable at `summon()`

`summon()` deploys a token, creates and seeds a pool, runs the prime buy and
deploys a collection (`CauldronRegistry.sol:722-800`). A retryable that
under-provisions L2 gas for that fails **on arrival**, leaving 6.89 ETH in the
7-day manual-redeem window (failure mode #4). Split it:

```
mainnet  igniteCauldron()  [sold out]
           └ createRetryableTicket{value: bal}(to: IgnitionReceiver, data: deposit())
                                              callValueRefundAddress: IgnitionReceiver
4663     IgnitionReceiver.deposit()   require msg.sender == applyAlias(L1_GENESIS); armed = true
         IgnitionReceiver.igniteCauldron()   [finalizer-gated]
           └ registry.summon{value: address(this).balance}()
```

- A payable flag-set essentially can't fail. The heavy call becomes an ordinary
  4663 transaction: gas-estimated, retryable forever, no 7-day clock.
- `registry.setIgniter(IgnitionReceiver)` is a **native** 4663 address. The
  registry never sees an alias, and the alias check lives in one ~30-line
  contract with one fork test.
- The receiver exposes `soldOut()` and `igniteCauldron()`, the exact interface
  `LaunchSniper` already calls (`LaunchSniper.sol:8-9, :81`). The atomic
  ignite-and-buy survives with **no `LaunchSniper` change**.
- `igniteCauldron()` before `armed` must revert. Otherwise anyone summons gen 1
  with dust.

### F7 · MESSAGING — every message is re-sendable state, never an event

Retryables can be redeemed out of order or expire, and LZ is unordered by
default. So:

> **Every message is a pure function of current source-chain state plus a
> monotonic nonce. Anyone can re-send it. The receiver applies only a strictly
> newer nonce.**

That closes failure modes #3, #5 and #6 by construction instead of with three
runbooks. It also prevents one sequence a per-message design misses: lock (n=1)
→ unlock (n=2) → re-lock (n=3) → a **duplicate** of unlock n=2 (LZ retry, or the
same unlock over a second port) releases a re-locked token. The vault must
require `nonce > lastApplied[tokenId]`.

### F8 · MAINNET CONTRACT — don't ship `MiFrensGenesis` to Ethereum

Votes and the dividend hook live on 4663. On mainnet they only make every trade
~2.9× more expensive (182,853 vs 63,559 exec gas) and impose a 320k gas-left
floor. The lean L1 contract is ERC721 + presale/cancel/refund + ERC2981 +
optional 721C + an **`everMoved` bit**, carried in roster and sync messages so
the paid re-enchant rule keeps working (`MiFrensDividend.sol:508` reads it from
the mirror).

### F9 · QUORUM — fail closed is the right transient

Plan §9 treats "full 1,111 while partial ⇒ unreachable" as a trap. As a
**transient during roster delivery** it's the safe failure. The other option is
the dangerous one: `MAX_PER_WALLET = 100` (`DeployLaunchpad.s.sol:137`) against a
10% quorum of a 100-token first batch lets one wallet pass proposals alone.
Mirror: `getPastTotalSupply = max(actual, GENESIS_SUPPLY)` for OG units.

After the roster the two are equal forever, because OG units never burn: redeem
moves them to the treasury, and the only burn path, `CauldronVault.redeem`,
refuses genesis ids (`CauldronVault.sol:163`). So this costs nothing once live.

### F10 · SYNC GAS — 150k will revert against F-09

A sync that changes the owner runs the mirror's `_update`, which pings the
dividend and **reverts below 320k gas left** (`MiFrensGenesis.sol:898`). Sync
and lock messages need an L2 gas limit of **≥ 450k**, not 150k. That costs
cents on either rail, but an under-provisioned canonical sync fails into manual
redemption. Also: a lock whose recipient equals the current owner must **not**
call `_transfer`. Otherwise locking to yourself breaks your own enchantment and
sets `everMoved`.

### F11 · RIGHTS RECIPIENTS — mainnet contract holders

The mirror names the mainnet address. Safes that can't be replicated on 4663,
lending escrows and AMM pairs have **no controller on 4663**: their rights are
stranded. Worse, anyone who can deploy at that address on 4663 can claim them
(CREATE2 factories replicated across chains). Add
`setRightsRecipient(address)` on mainnet, per owner, carried in every sync.

### F12 · ROYALTIES

ERC2981 royalties on mainnet land as ETH on L1. The dividend's `receive()` is
open to anyone (`MiFrensDividend.sol:235`), so a permissionless
`flushRoyalties()` that deposits through a retryable is enough: cents, no new
trust.

### F13 · OFF-CHAIN — the app is single-chain by construction

`indexer/deployments/round.json` pins one `chainId`, and the presale page reads
the same chain as the protocol (`src/config/presale.ts`, `indexer/src/index.ts`).
Minting on 1 while running on 4663 is a real frontend and indexer workstream,
not a config flip.

### F14 · NEW, not specific to cross-chain — the successor upgrade path can't move the contracts that depend on the registry

The docstring on `migrateToSuccessor` (`CauldronRegistry.sol:533-539`) says
treasury frens and the MiFrens custody pointer are re-homed "separately by
governance (`mifrens.setRegistry(successor)`)". **That call reverts.**
`MiFrensGenesis.setRegistry` is deployer-only and can be called once
(`RegistryAlreadySet`, `MiFrensGenesis.sol:352-357`). Three other pointers have
the same shape:

| pointer | can it follow a successor? |
|---|---|
| `MiFrensGenesis.registry` (`custodyTransfer`'s only caller, `:530`) | ❌ set once |
| `MiFrensDividend.registry` (re-enchant fee → `donateToReserve`) | ❌ set once (`:189-193`) |
| `CauldronGovernor.registry` (`markConsumed`) | ❌ set once (`:375-376`) |
| `CauldronToken.registry` (`burn`) | ❌ `immutable` |
| `CauldronHook.registry` | ✅ delayed override (`CauldronHook.sol:2240-2270`) |

**Consequences after a successor migration. Now EXECUTED (2026-09-23):**
`test/functional/F23_SuccessorRehearsal.t.sol`, 7/7, with every revert pinned.
See `docs/UPGRADE_READINESS.md` §1.

- **The OG floor stops working.** Called from the successor, `redeemOgFren` and
  `buyTreasuryOgFren` revert, and the frens the treasury holds are stranded.
- **Frens that have moved can never earn again.** The dividend still donates the
  re-enchant fee to the *old* registry, which no longer owns the reserve
  position, so `castSpell` on a moved fren reverts.
- **A successor built from today's registry code can't relaunch or migrate
  v1-era tokens.** Its first `relaunch` reverts at step 3a
  (`CauldronToken(oldToken).burn`), and `claimByBurn` reverts for every
  v1-era generation.

I searched `audit/` for these symbols and found no prior note.

**Fix before launch. It's cheap, because none of these is the registry that's
short on bytes.** Give the first three the hook's delayed-override pair. Every
successor registry (and every remote instance, §3.9) must treat
foreign-generation tokens with **lock or transfer-to-dead, never `burn`**.

---

## 3. Sketch — rev. 3: hub on mainnet, protocol on 4663, spokes later

### 3.1 Shape

```
                         ETHEREUM (hub, immutable identity)
   ┌──────────────────────────────────────────────────────────────────┐
   │ MiFrensGenesis (lean ERC721 + presale)   GenesisHub               │
   │   ids 1..1111, forever                     vault                  │
   │                                            home[tokenId]: spokeId │
   │                                            nonce[tokenId]         │
   │                                            rightsRecipient[owner] │
   │                                            spokes[k]: {adapter,   │
   │                                               kind: CUSTODY|RIGHTS}│
   └───────────────┬──────────────────────────────────┬───────────────┘
        canonical inbox/outbox               canonical (OP) or LZ
                   │                                  │   (later)
   ┌───────────────▼───────────────────┐   ┌──────────▼────────────────┐
   │ ROBINHOOD 4663 — spoke 1, CUSTODY  │   │ spoke 2 (Base / Arc / …)   │
   │ MiFrensMirror (MiFrensGenesis fork)│   │ MiFrensMirror₂             │
   │   OG ids: bridged, ERC-5192        │   │ own Cauldron machine       │
   │   forged ids 1112+: native         │   │   (registry/hook/reserve)  │
   │ IgnitionReceiver                   │   │ genesis bonus → same 1111  │
   │ registry · hook · dividend ·       │   └────────────────────────────┘
   │ governors · perp — UNCHANGED       │
   └────────────────────────────────────┘
```

### 3.2 State per fren: `home[tokenId]`

| home | mainnet NFT | mirror on `home` | mirrors elsewhere | floor redeem |
|---|---|---|---|---|
| `0` (HELD) | wallet, **transferable** | — | soulbound, rights ✅ | via `lock` → spoke |
| `k` (vaulted at k) | vault, frozen | **transferable**, rights ✅ | **suspended**, no rights | atomic on k |

**Invariant, generalised:** the transferable side is exactly `home[tokenId]`.
With one spoke this is rev. 2's invariant unchanged.

| transition | chain | effect | message |
|---|---|---|---|
| `sync(id, spokes[])` | 1 | — | owner + rightsRecipient + everMoved → chosen spokes |
| `lock(id, k, to)` | 1 | NFT → vault; `home = k` | LOCK → k; SUSPEND → others |
| `redeemOgFren(id)` | k | mirror → k's treasury (**requires `home == k`**) | none |
| `buyTreasuryOgFren(id)` | k | mirror → buyer at 2F | none |
| `unlock(id, to)` | k | **freeze mirror first**, then send | RELEASE → hub |
| RELEASE arrives | 1 | `home = 0`; NFT → `to` | RESUME(owner) → others |

### 3.3 Why suspension is required with two spokes

Rev. 2's "dividends are a flow" argument depends on the gap being **temporary**:
the buyer syncs, and it closes. With two spokes, a fren locked to spoke 1 and
then sold or redeemed there is invisible to spoke 2, which has no path to learn
the new owner except through mainnet (7 days). Without SUSPEND, the ex-owner
keeps spoke 2's votes and dividends **indefinitely**. A fren redeemed into
spoke 1's treasury would pay its redeemer on every other spoke forever. That is
M-06 made permanent. **Rights follow the transferable side:** HELD frens have
rights everywhere, vaulted frens only at home.

Suspension parks the non-home mirror on a sentinel owner. `enchantedBy !=
ownerOf` stops the dividend (`MiFrensDividend.sol:257`), the spell breaks
through the normal `_update` ping, and the votes sit unused like a treasury-held
fren. With one spoke, SUSPEND and RESUME are no-ops. **Build the message types
now anyway**, because the hub can't be redeployed later.

### 3.4 Two kinds of spoke

- **CUSTODY**: may hold the transferable side and command vault release. Only
  over transports that add no trust (canonical rollup bridges: 4663, Base,
  Arbitrum One, other Orbit chains settling to L1), or over a DVN set the owner
  explicitly accepts.
- **RIGHTS**: HELD mirrors only. It can never be `home`, so it can never
  release an NFT. A compromised transport can corrupt that spoke's votes and
  dividends but **cannot move a single fren**. This is the tier for a
  non-rollup chain reached only by LZ (e.g. Arc).

### 3.5 What "iteration on another chain" can and can't mean

- **It can't be a relaunch that hops chains.** `relaunch` is a single-tx state
  transition over one PoolManager's LP (recover → burn → reseed), and the hook
  is unpatchable. There is no atomic cross-chain version of that.
- **It can be a new machine on spoke 2**, with its own registry, hook, reserve
  and governors, ignited through its own `IgnitionReceiver`. The presale ETH is
  spent on spoke 1, so spoke 2's `summon()` value has to come from somewhere
  else: a 4663 `TreasuryGovernor` allocation bridged over, a slice of fees, or
  a fresh raise for that iteration.
- **OGs get a floor on every chain.** `setGenesisBonus(mirror₂, bps, 1111)`
  gives every mainnet fren a reserve share on spoke 2 too. Each spoke's floor
  can be claimed once per "tour": redeem on k → k's treasury → buyer at 2F_k →
  unlock → lock to j → redeem on j. Every floor ratchets independently, and
  **nothing is burned**, so the OG ratchet stays intact. This answers open
  decision #2: no burn-for-iteration.
- **Forged-tranche collision to resolve before spoke 2.** Gen 2 on spoke 2 would
  call `_continueMiFrens` on mirror₂ (`CauldronRegistry.sol:1138`) and mint ids
  1112+ that collide with spoke 1's forged ids. Either deploy mirror₂ with
  `MAX_SUPPLY == GENESIS_SUPPLY` (GachaLib mints through `try/catch` and checks
  `maxSupply`, `GachaLib.sol:214-246`, so it should degrade; **needs a test**
  of what the hook does when a continuation is minted out), or give each spoke
  a disjoint forged id range.

### 3.6 Adding or changing a spoke is a custody action, so gate it like one

A new CUSTODY adapter is a new key to the vault. Use the registry's own pattern
(`armEmergency` → delay → `_consumeTimelock`, `CauldronRegistry.sol:412-428`):
**arm → wait ≥ 7 days → execute, with a guardian veto.** Any holder who distrusts
the new adapter can unlock through the existing one during the window.
Replacing an **existing** CUSTODY adapter is the highest-risk action in the
system and gets the same gate.

### 3.7 What to build now so spoke 2 is config later

Mainnet only, because nothing else is immutable in a way that matters:
`home` as a spoke id (not a bool) · an adapter table with `kind` · per-owner
`rightsRecipient` · state-derived, re-sendable, nonced messages · SUSPEND/RESUME
message types. Everything else waits until there's a reason to launch spoke 2.

### 3.8 Iteration *tokens* on other chains

Three different things can be meant. They have different answers.

| meaning | feasible? | 4663 contract changes |
|---|---|---|
| **A. Bridge the live iteration token** (trade $GNOME on Base etc.) | **Yes**, with economic trade-offs | none |
| **B. A cross-chain *branch*:** a new machine on X whose gen 1 descends from a 4663 generation | **Yes**, as a new deployment | none |
| **C. `relaunch()` deploys the next gen on another chain** | **No**, not without a new registry | would need them, and there's no room |

**Why C is out.** `relaunch` is one transaction over one PoolManager: check
death → force-close perps → pull LP → burn → mine token → reseed
(`CauldronRegistry.sol:821+`). Recovered LP value can't cross a bridge inside
that transaction. `BrewSpec` has no chain field (`ICauldron.sol:19-31`), and the
registry has 8 bytes free to add one. The only route to new registry code is
`migrateToSuccessor` (`:540`), which is an emergency, timelocked path.

**A — bridging the token. The contract side is easy; the costs are economic.**

- `CauldronToken` is a plain fixed-supply ERC20 with no mint
  (`CauldronToken.sol`), so only **lock-and-mint** works: an adapter on 4663
  locks the token, and a mintable representation lives on X. It needs no token
  change.
- **Migration backing survives.** The next reserve is
  `TOTAL_SUPPLY − newActive`, where `newActive` comes from the recovered LP
  (`CauldronRegistry.sol:1045-1066`). Every token outside the dead LP is covered
  1:1, including those locked in the adapter.
- **But `claimByBurn` burns the caller's balance on 4663** (`:1291-1315`).
  Holders on X must bridge back to migrate, or an adapter-side composer migrates
  the locked balance for them. If `claimGate` (vesting) is set, that composer
  has to route through the escrow (`:1300`). `autoMigrateBatch` refuses
  outright while it is set (`:1402`).
- **Trading on X bypasses the hook.** It earns no fees, so no dividends, no
  floor ratchet, no forging and no surtax. Only arbitrage flow that crosses back
  to 4663 pays.
- **Volume on X doesn't keep the generation alive.** `isDead` sums only tracked
  4663 pools (`CauldronHook.sol:1863-1883`). The hook's `deathChecker` is
  pluggable (owner/registry, `:2180`), so an attested remote-volume module can
  count X's volume. Its failure mode is bounded: a module that only **adds**
  volume can be forged to keep a dying generation alive, but never to kill a
  healthy one.
- **A thinner 4663 pool is cheaper to move.** That pool prices `F`, the perp
  mark and liquidations. Liquidity that migrates to X weakens all three.
- **Each generation is a new token address**, so it needs a new adapter and a
  new remote token every relaunch. The registry can't do this (no bytes), so it
  has to be a permissionless deployer keyed on `generationToken[g]`.
- **Trust:** the fast path out of 4663 is LZ (canonical is 6.4 days out, then
  L1 → X). A forged remote mint can't touch the reserve directly, but it can
  bridge back and **drain the adapter's locked balance**. Apply per-window rate
  limits.
- **Optional satellite hook:** a v4 hook on X that takes a fee on the bridged
  token's pool and ships it to the 4663 dividend and reserve (and reports volume
  for the `deathChecker`). It brings X's volume back into the flywheel, at the
  cost of a second hook to audit.

**B — a branch on X.** The seam already exists:
`generationParent[newGen] = oldGen; // V1 linear chain; V2 branch graph seam`
(`CauldronRegistry.sol:1042`).

- **The machine:** its own registry, hook, reserve and governors on X, ignited
  through its own `IgnitionReceiver`. OGs get rights through the hub (§3.1–3.5).
- **Funding comes from outside the 4663 machine.** `relaunch` puts all
  recovered value into 4663's own next gen, and I found no lever that sends
  registry value to another chain. Sources: a fresh raise for the branch, the
  treasury multisig, or fees already paid out to it.
- **Migrating into the branch:** burn or lock the gen-g token on 4663 → message
  → claim branch gen-1 tokens from X's reserve. A forged message drains **X's**
  reserve only, so the damage stays on X. Cap X's migration reserve, since the
  demand isn't known in advance.
- **Who decides:** `CauldronGovernor` votes on the next brew *on 4663*. A branch
  decision needs its own vote (a new governor reading the mirror's votes) or an
  off-chain signal.

**Recommendation.** If the goal is *reach* (users on other chains), do A with a
satellite hook and the remote-volume `deathChecker`. If the goal is *the
Cauldron living on several chains*, do B, one machine per chain, and let the
mainnet hub carry OG rights to each. Both are additive, and neither touches the
4663 contracts. §3.9 covers the owner's actual intent, which is a variant of C.

### 3.9 The Cauldron moves between chains — one live pool, any chain

The owner's intent: deploy the full protocol on several chains, keep **exactly
one** live pool anywhere, let the frens vote the next iteration onto whichever
chain has the momentum, and be able to come back to Robinhood later.

**Same invariant, one level up:** *exactly one ACTIVE instance globally.* During
a handoff there are **zero** active instances. That is the safe state, just as a
fren in flight is transferable nowhere.

| instance state | meaning |
|---|---|
| ACTIVE | live generation, live pool, relaunch possible |
| EXITING | LP recovered, value in flight, nothing trades |
| PARKED | no pool. Still serves local claims (accrued dividends, old-gen migration burns, NFTs born here) |

**The handoff: a relaunch that exits instead of reseeding**

```
A (ACTIVE)  relaunch() with winning spec.chain = B     same gates: dead + minLifetime + frens' vote
            steps 1-4 UNCHANGED: perps force-closed, LP recovered, dead tokens burned, tickets drained
            snapshot -> HandoffPacket{epoch, spec N+1, migrationDemand,
                                      genesisReserveOutstanding, legacyEntitled, treasuryOg[]}
            packet -> LayerZero -> RoamReceiver(B)          authority, ~$0.27
            ETH    -> Across (chunked) -> RoamReceiver(B)   value, ~1 s per fill      A: PARKED
            pointer {chain B, epoch} -> LZ -> every other spoke + the L1 hub
B (PARKED)  RoamReceiver: lzReceive stores the packet; ETH accumulates; neither step can fail
            resume(packet)   ordinary tx, retryable, once received >= threshold  B: ACTIVE
```

- **The pointer is recorded on the Ethereum hub** (the one place frontends
  read, and what the NFT vault consults), but updates reach it and the other
  spokes over LZ like everything else. A PARKED instance refuses relaunch,
  summon and resume unless an authenticated packet with the next epoch names
  it.
- **Coming back to Robinhood is just another handoff with A as the
  destination.** So `resume` must work on an instance that was ACTIVE before:
  `summoned` is already true, and `currentGeneration` jumps from N to N+k.
- **An unreachable destination must fall back to "stay", never revert.** This is
  the B-05 discipline: `spec.quote` is already clamped rather than trusted, and
  `spec.chain` must be too.

**Moving the treasury: decided. No canonical rail.** Robinhood → Base is L2 →
L2, and the only canonical route runs through L1 with a ~week exit. Two rails
carry the handoff, and each does one job:

| job | rail | why |
|---|---|---|
| **authority**: the handoff packet, epoch and active pointer | **LayerZero**, ≥3 DVNs | authenticated. B has to know the packet came from A's port |
| **value**: the recovered ETH | **Across**, the same rails the Uniswap app uses for ETH bridging (with Relay as a second route) | fast and cheap. Unfilled deposits refund on-chain on the origin (Across) |

**The value rail cannot carry authority.** In Across, a relayer calls the fill
on the destination SpokePool with deposit data **it supplies itself**; the
destination can't check that the deposit exists on the origin. Anyone can
"fill" a fake deposit whose message says "resume generation N+1", paying out of
their own pocket. So B's receiver treats every arriving ETH as **anonymous
value** and every instruction as **LZ-only**. It resumes when it holds an
authenticated packet (`expectedValue`, epoch, obligations) **and** enough
received ETH. Any excess just adds to the treasury.

Measured 2026-09-22, ETH Robinhood → ETH Base:

| | Across | Relay | LZ packet (authority) |
|---|---|---|---|
| route | native ETH ✅ (`isNative: true`) | ETH ✅ (solver currencies ETH, USDG) | 4663 eid 30416 → Base eid 30184 |
| max per deposit | **8.18 ETH** now (10 ETH → `AMOUNT_TOO_HIGH`); the reverse direction allows 237.5 ETH | quoted **30 ETH** fine | — |
| fee | **0.033%** (1 ETH → 0.000334 ETH) | **0.12%** | executor 9.52e13 + 3 DVNs ~1.9e12 wei ≈ **$0.27** |
| fill | ~1 s | ~2 s | minutes |
| origin contract | SpokePool `0xD29C…7978` (4663), `0x09ae…bEC64` (Base) | receiver `0x4cd0…bc31` | EndpointV2 |
| if it isn't filled | on-chain refund to the depositor after `fillDeadline` | a single deposit step to Relay's receiver, **no on-chain escrow in the returned path**; delivery and refund rely on Relay operationally | retry / re-send (F7) |

- **Chunk anything above the per-deposit limit.** The receiver accumulates
  chunks, so value may arrive in several deposits over minutes to hours.
- **Owner choice:** resume at 100% received, or at a floor (say 90%) and add the
  remainder as it lands. Check whether the progressive seeder can take
  late-arriving value.
- **If the treasury has rotated to USDG,** Across has a USDG → USDC route and
  Relay's solvers hold USDG. The quote asset on B would differ; this is the same
  denomination question the rotation work already handles.

**What moves and what stays**

| obligation | handoff treatment |
|---|---|
| LP quote value | **moves** (bridged, above) |
| gen N+1 token | **born on B** with fresh fixed supply, so no token crosses |
| gen-N holders migrating 1:1 | tokens **stay on A**. Burn/lock on A → claim on B. Batch it: one Merkle root per epoch over the canonical route (no added trust, ~a week), plus an optional **capped** fast lane. A forged claim can drain only B's migration reserve. A's registry must do the burn (F14: nobody else can) |
| OG floor | **moves**, sized into B's reserve exactly as relaunch sizes it today. HELD frens lock to B from mainnet in 10 min. Frens vaulted on A **rehome** via the hub. Treasury-held OGs rehome in the packet |
| NFT collection floors of generations born on A | NFTs **stay on A**. Either carve their backing out at exit into A's `CauldronVault` as ETH (the code exists and is wired off today; those floors then stop growing), or redeem cross-chain. **Owner decision** |
| accrued dividends | stay claimable on A; new fees accrue on B |
| perps | force-closed at exit (the existing `openCount() == 0` invariant). A's PerpVault becomes withdraw-only; B starts a fresh one. "Stake & chill" auto-migration becomes manual |
| treasury rotation / sibling pools / guild positions | must be unwound **before** exit (an exit precondition) |
| governance | the destination vote happens on the active chain. `BrewSpec` (`ICauldron.sol:19-31`) gets a `chain` field |

**Constraints**

- Each destination needs Uniswap v4, or we deploy it ourselves as on Arc.
- The hook's address has to be mined on each chain.
- Each instance is deployed, configured and parked ahead of time.
- Each instance gets its own adversarial pass.

**Code impact, stated plainly**

The registry needs two new transitions: *exit* (relaunch without reseeding) and
*resume* (summon at generation N+k from a packet). It has **8 bytes** free and
**no catch-all fallback** (`CauldronRegistry.sol:1461`), so neither fits in v1.
Two routes:

1. Build roaming into v1 before the Robinhood launch. That means an EIP-170
   fight and a later launch.
2. **Launch v1 as it is and adopt roaming later as a v2 registry through
   `setSuccessor` → `migrateToSuccessor`** (timelocked, with the exit forced
   open). **Recommended, but that route is broken today (F14). Fix it before
   launch.**

**Build before launch, because it's cheap now and impossible later:** F14's
delayed registry override on the mirror, dividend and governor, plus the hub's
active pointer and spoke table. Everything else is v2.

### 3.10 Can roaming be added after launch? (checked 2026-09-23)

**Yes, but through exactly one route.** The protocol lets you swap *policies*;
its *core* can't be upgraded in place.

| layer | upgradeable later? | evidence |
|---|---|---|
| death rule, surtax / gacha / mint-curve policies | ✅ swappable modules | `CauldronHook.sol:2180-2190` |
| seeder, proposal governor | ✅ `onlyOwner` setters, **no timelock** | `CauldronRegistry.sol:333, 585` |
| registry code | ❌ 8 bytes free, no catch-all fallback | `:1461` |
| registry facet (`redemptionExt`) | ❌ **frozen after its first set** | `:190-197` |
| hook code | ❌ unpatchable; only its *registry pointer* moves: propose → **7 days** → execute | `CauldronHook.sol:312, 2237-2270` |
| **whole registry → successor** | ✅ `setSuccessor` → arm → `emergencyDelay` → `migrateToSuccessor`, guardian veto, redemptions forced open during the wait | `CauldronRegistry.sol:505-575` |

Roaming needs new registry entrypoints (exit, resume), so it can only arrive as a
**v2 registry through the successor route.** That is the right shape for an
audited upgrade:

- v2 is audited as its own codebase;
- the switch is public and slow (the registry timelock plus the hook's 7 days);
- every holder can leave at the floor before anything moves.

**The catch: the route has never been exercised end to end, and by reading it
doesn't work today.** 13 contracts bind to the registry and can't follow a
successor:

| pointer kind | contracts | after a successor switch |
|---|---|---|
| set once | `MiFrensGenesis` (the mirror), `MiFrensDividend`, `CauldronGovernor` | the **mirror can't be redeployed** (it is the 4663 collection) → needs a timelocked re-point. Dividend and governor can be redeployed (the old dividend stays claimable) |
| `immutable`, **hold user value or accounting** | `CollectionLedger` (NFT floor entitlements), `MigrationVesting` (escrowed vesting tokens), `PerpVault` (staker capital), `TreasuryGovernor` (mandates), `QuoteRotator` (assets mid-rotation) | each needs a **proven wind-down, re-point, or state import**. Otherwise its users are stranded against a registry that no longer owns the LP |
| `immutable`, stateless or replaceable | `CauldronSeeder`, `CauldronGachaRouter`, `CauldronVault` (supply counter), `PerpEngine` (once flat) | redeploy for v2 |
| `immutable` | `CauldronToken` | v2 can never `burn` a v1-era token → v2 must lock or transfer-to-dead instead |

**Before launch, keep this route open:**

1. **Successor rehearsal (a fork test).** Run v1 → a stub v2 and assert these
   all still work afterwards: OG redeem and treasury resale, legacy NFT floor
   redeem, old-gen migration, vesting claims, perp stake withdrawal, dividend
   claims. That test turns "upgradeable later" from an assumption into a fact.
2. Fix what it shows. At minimum, give the mirror the hook's delayed re-point
   (F14). For the five value-holding contracts, choose re-point or wind-down
   per contract.
3. Give the mainnet hub its active-chain pointer and chain table.

Everything else (roaming v2, the receiver and port, LZ + Across) is built later,
audited on its own scope, and shipped through the successor switch. The switch
itself is part of that audit.

---

## 4. Revised build order

0. ~~Measure the LZ fee~~ **Done** (§1). ~~Confirm LZ on 46630~~ **Done**.
   Still to verify: 46630's parent chain and inbox (presumably Sepolia) for the
   canonical rehearsal.
1. **Harness first, no value.** Assert: (a) HELD `custodyTransfer` reverts;
   (b) exactly one transferable side through every transition **with messages
   dropped, duplicated and reordered**; (c) quorum fails closed under a partial
   roster; (d) a stale RELEASE after a re-lock is rejected.
2. `MiFrensMirror` (fork of `MiFrensGenesis`) + port + `syncOwner` over the
   canonical inbox. **This alone meets requirement (2).**
3. `IgnitionReceiver` + roster over the canonical inbox. Fork-test deposit →
   ignite → summon, and `LaunchSniper` unchanged.
4. Lean mainnet `MiFrensGenesis` + `GenesisHub` vault + `lock`. Adds the floor
   arb from mainnet and OpenSea-Robinhood.
5. `unlock` over the canonical outbox (6.4 days).
6. *Optional:* LZ fast unlock, per-token opt-in, ≥3 DVNs.
7. *Later:* spoke 2.

## 5. Open decisions — updated

| # | decision | status |
|---|---|---|
| 1 | `minOut` on Path 1 | **Dissolved** by F4 |
| 2 | burn-for-iteration | **Recommend no.** Spoke-2 genesis bonus instead (§3.5) |
| 3 | DVN set | **Only if** fast unlock or RIGHTS spokes over LZ. Then ≥3, e.g. LZ Labs + Nethermind + Horizen (all live on both ends) |
| 4 | who funds the roster | Presale proceeds. ≈$15–25 total either rail |
| 5 | sync: buyer or keeper | Permissionless + buyer pays. At ≈$0.07–0.09 a keeper funded from royalties is also affordable |
| 6 | **new:** ship fast unlock at all? | Owner decision. Only the cross-venue spread needs it |
| 7 | **new:** `everMoved` for frens traded during the presale | Carry it from mainnet (keeps today's rule), or reset at ignition (every roster fren enchants free) |
| 8 | **new:** allow RIGHTS-only spokes over LZ? | Owner decision (§3.4) |
| 9 | **new:** roaming in v1, or v2 via the successor path? | Recommend v2, after F14 is fixed (§3.9) |
| 10 | **new:** how the treasury crosses on a roam | **Decided:** LZ for the packet, Across (Relay second) for the ETH (§3.9). Still open: resume at 100% received or at a floor |
| 11 | **new:** NFT floors for generations born on a chain being left | Carve out as ETH on the old chain, or redeem cross-chain (§3.9) |
