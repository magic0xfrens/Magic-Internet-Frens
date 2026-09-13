# H4 — Token / NFT economy (blind red-team, 2026-09-13)

Scope: `CauldronToken.sol`, `cauldron/{CauldronCollection,CollectionLedger,CauldronGachaRouter,MiFrensDividend,MintCurvePolicy,RoyaltyRouter,FeeRouteLib,LegacyBuyLib,DefaultFeeRouter,CauldronFactory,ICreatorToken}.sol`, `render/*`.
Work done in `/tmp/blind-final-h4/contracts/solidity` (decontaminated copy, line numbers 1:1 with the real tree).

---

## 1. Model from code

**Supply.** `CauldronToken` mints its whole supply once in the constructor to the registry and exposes only `burn(from,amount)` gated `onlyRegistry` (CauldronToken.sol:58). No allowance is consulted; the two reachable callers both bind `from` — `CauldronRegistry.claimByBurn` passes `msg.sender` (CauldronRegistry.sol:1310) and `PoolOps.autoMigrateBatch` only touches holders who set the `autoMigrate` opt-in flag (PoolOps.sol:1402-1409).

**NFT.** `CauldronCollection.mint` is `minter`-only (the hook) and capped at `maxSupply` (CauldronCollection.sol:207-217); it mints UNREVEALED and records `mintBlockOf`. `reveal`/`revealBatch` (≤50) roll `keccak256(blockhash(mb), tokenId, address(this))`; an expired seed re-anchors **once** (`reanchored`, :253/:301) and then commits tier 0. `burnFromVault`/`custodyTransfer` are vault/deployer gated. Badges live in a separate id range above `LIQUIDATOR_ID_BASE`.

**Gacha.** `CauldronGachaRouter.play/playLiq/playChurn/openReady` are permissionless; they pull the generation quote (native XOR ERC20, `_pullQuote`), swap through the V4 pool tagging `hookData` with the player, then call the hook's opener-gated `commitCrystals` + permissionless `resolveTickets`. Ticket outcomes are seeded by `blockhash(commitBlock)` (CauldronHook.sol:2388-2406).

**Floor / claims.** `CollectionLedger.{credit,redeem,buyback,crystallize}` are `onlyRegistry`; `credit` and `crystallize` silently drop credits to a dead-end generation rather than reverting. Volume-collection secondary royalties go to a per-brew `RoyaltyRouter` (CauldronFactory.sol:81-82) which forwards ETH into `CauldronHook.fundLegacyBuffer`. Genesis royalties + the guild share of swap/perp fees go to `MiFrensDividend` (ETH `receive()`, ERC20 `fundToken` funder-gated, `adopt` open for already-known assets).

**Fee routing.** `FeeRouteLib` (linked library, delegatecalled by the hook) splits guild/floor/stakers, checks `to.code.length` before every send and never reverts; failures return `leftover` which the hook buffers into the relaunch reserve. `LegacyBuyLib.buyStep` (also delegatecalled) market-buys with a per-pool tick reference in a namespaced slot.

---

## 2. Findings

```
id: K4a   severity: High   confidence: VERIFIED
subsystem: royalty routing / volume-collection floor
file:line: cauldron/RoyaltyRouter.sol:35-46 —
    contract RoyaltyRouter {
        address public immutable hook;
        constructor(address _hook) { require(_hook != address(0), "hook"); hook = _hook; }
        receive() external payable {
            if (msg.value > 0) ILegacyBuffer(hook).fundLegacyBuffer{value: msg.value}();
        }
    }
file:line: cauldron/CauldronFactory.sol:81-82 —
        RoyaltyRouter router = new RoyaltyRouter(c.hook);
        col.setRoyalty(address(router), c.royaltyBps);
title: Any secondary sale settled in an ERC20 pays its EIP-2981 royalty to a
       contract with no ERC20 path at all, permanently stranding it.
precondition: None beyond a deployed brew. `deployBrew` makes a RoyaltyRouter the
  2981 receiver of EVERY volume collection. Blur settles exclusively in WETH;
  Seaport collection offers are routinely WETH/USDC. Those marketplaces pay the
  royalty with a plain `transfer` to the receiver address.
sequence:
  1. factory.deployBrew(...)                        -> collection + RoyaltyRouter R
  2. royaltyInfo(id, price) -> (R, 5%)              (verified in the PoC)
  3. marketplace: WETH.transfer(R, 0.05 ether)      (any ERC20-settled sale)
  4. every plausible recovery selector on R fails:  adopt(address),
     rescueToken(address,address,uint256), sweep(address),
     withdraw(address,uint256), owner(), transferOwnership(address),
     fundLegacyBuffer(). R has no owner, no sweep, no fallback, no delegatecall.
attacker_cost: 0 — this is not an attack, it is the default path for a whole
  class of marketplace. No attacker required.
damage: 100% of the royalty on every non-native secondary sale, permanently
  locked. At 5% royalty this is 5% of all ERC20-denominated secondary volume of
  every generation's collection, forever. The value is also NOT delivered to the
  floor it was supposed to back, so the collection's per-gen token floor
  under-accrues by the same amount.
poc: contracts/solidity/test/attacks/K4a_RoyaltyErc20Strand.t.sol   needs_fork: no
notes: `MiFrensDividend.adopt` (cauldron/MiFrensDividend.sol:323) was added for
  EXACTLY this hazard on the genesis side, and its own docstring at :306-316
  spells the failure out ("5% of every non-native secondary sale landed in a
  contract with no owner, no sweep, no rescue and no crediting path"). The
  volume-collection receiver never got the equivalent. RoyaltyRouter.sol:23-26
  asserts "THIS CONTRACT MUST NEVER HOLD ETH, and it never does" — true of ETH,
  and silent about the ERC20 case it cannot handle.
verified: PASS, `forge test --match-path test/attacks/K4a* -vv`
  logs: `stranded WETH royalty (wei): 5000000000000000000`
```

```
id: K4b   severity: Medium   confidence: VERIFIED
subsystem: crystal gacha randomness
file:line: CauldronHook.sol:2388-2394 —
            bytes32 bh = blockhash(b.commitBlock);
            ...
            if (bh == 0) {
                b.commitBlock = uint48(block.number);
                break; // FIFO: resume from here on the next call
            }
file:line: CauldronHook.sol:2406 —
                uint256 roll = uint256(keccak256(abi.encodePacked(bh, player, bi, r))) % 10_000;
title: A player can convert a low-odds crystal into a guaranteed win by never
       resolving a losing batch and letting its seed expire, an UNLIMITED number
       of times.
precondition: The batch must survive 256 blocks unresolved. `resolveTickets` is
  permissionless and is called by every router play and every native in-swap
  gacha step, so the grind needs a quiet window in the gacha queue. 256 blocks is
  ~51 min on L1 and ~8 min on the 2s-block L2s this is deployed to
  (cauldron-arc style targets), which makes it routinely reachable off-peak, and
  trivially reachable for the FIRST players of a fresh generation.
sequence:
  1. player: gachaRouter.play(...)  -> hook.commitCrystals -> Batch{commitBlock=B}
  2. at block B+1 EVERY input to the roll is public: `blockhash(B)`, `player`,
     the batch index and the ticket index. The player computes the outcome.
  3. if it WINS: resolveTickets(30). Done.
  4. if it LOSES: do nothing. At B+257 anybody's resolveTickets(30) hits
     `bh == 0`, rewrites `b.commitBlock = block.number` and BREAKS. Fresh seed,
     nothing consumed, no counter incremented.
  5. goto 2. There is no `reanchored`-style cap on this path.
attacker_cost: one `resolveTickets(30)` transaction per 256 blocks (~30-60k gas).
  No capital at risk; the crystal's credit was already spent at step 1.
damage: the honest win rate (`oddsForPlay`, ≤ maxOddsBps) becomes 100%. In the
  PoC a 900 bps (9%) ticket minted an NFT after 11 free re-anchors. Each extra
  NFT dilutes `CollectionLedger.floorPerNFT` for every honest holder and consumes
  a slot of `maxSupply` that was supposed to cost the curve price at that rung.
poc: contracts/solidity/test/attacks/K4b_GachaReanchorGrind.t.sol   needs_fork: no
notes: `CauldronCollection._reveal` fixes the identical mechanism on the REVEAL
  side and caps it at one re-anchor (cauldron/CauldronCollection.sol:253, :301-302)
  with a docstring that describes this exact grind ("the draw stops being
  unknowable the moment block `mb` is mined, and NOTHING OBLIGES THE HOLDER TO
  REVEAL... they had a fresh draw for the price of one transaction"). The ticket
  queue's twin at CauldronHook.sol:2391 has no such cap; its comment claims
  "the roll is always unknowable", which is true of the SEED and false of the
  OUTCOME, because the player chooses whether the roll is ever committed.
  Secondary effect: the `break` means a head batch stuck in this state also
  stalls every batch behind it for one block per call (liveness nuisance, not a
  brick — it clears on the next block).
verified: PASS, `forge test --match-path test/attacks/K4b* -vv`
  logs: `honest odds (bps): 900` / `free re-anchors used: 11` /
        `NFTs minted from ONE crystal: 1`
  The loop's ground truth is read from the hook itself
  (`require(hook.outstandingTickets() == 1, "batch resolved, not re-anchored")`),
  not from a local counter, and block advance is asserted via
  `vm.getBlockNumber()` so the viaIR cheatcode-sinking hazard cannot fake it.
```

```
id: K4c   severity: Medium   confidence: DERIVED
subsystem: gacha router — churn path
file:line: cauldron/CauldronGachaRouter.sol:369-372 —
    function playChurn(uint256 quoteIn, uint256 loops, uint256 openMax)
        external
        payable
        nonReentrant
        returns (uint256 opened)
file:line: cauldron/CauldronGachaRouter.sol:518-520 —
    function _limit(bool zeroForOne) private pure returns (uint160) {
        return zeroForOne ? 4295128740 : 1461446703485210103287273052203988822378723970341;
    }
title: `playChurn` has NO slippage parameter and swaps at the extreme tick, so a
       sandwicher can take almost the whole spend across up to 10 round trips.
precondition: none — `playChurn` is permissionless and the signature simply has
  nowhere to put a bound. Contrast `play`/`playLiq`, which take `minTokenOut` and
  `minQuoteOut` and enforce them (CauldronGachaRouter.sol:427-428, :316).
sequence:
  1. victim: playChurn{value: X}(0, 10, 0)
  2. attacker front-runs with a large buy, pushing sqrtP to the attacker's chosen
     level. `_limit(true)` is MIN_SQRT_LIMIT and `_limit(false)` is
     MAX_SQRT_LIMIT, so neither leg of `_churn` (:465-508) refuses any price.
  3. the victim's 10 buy->sell round trips each fill at the manufactured price;
     the attacker back-runs.
  4. the router returns `ethLeftover` and pays it out with no minimum
     (CauldronGachaRouter.sol:386, `_payQuote`).
attacker_cost: flash-loanable capital for one block + gas. Profit is bounded by
  the victim's `quoteIn` and grows with `loops`.
damage: up to ~100% of a single caller's churn spend per victim. Protocol
  invariants are untouched; the loss is entirely the user's.
poc: not written — a faithful PoC needs a live PoolManager and an adversarial
  bundle; I ran out of budget before building the fork rig. Recorded as DERIVED
  from the two quoted line ranges, both read in full.
```

```
id: K4d   severity: Low   confidence: DERIVED
subsystem: royalty routing (gas)
file:line: cauldron/RoyaltyRouter.sol:44-46 (quoted in K4a)
title: The royalty receiver's `receive()` makes an unbounded external call into
       `CauldronHook.fundLegacyBuffer`, so a marketplace that pays royalties with
       a gas-stipended `transfer`/`send` reverts the whole secondary sale.
precondition: a marketplace using `.transfer()` (2300 gas) or a low `call` gas
  cap for royalty payouts. Seaport and Blur use full-gas `call`, so this is a
  compatibility hazard rather than a live break today.
sequence: marketplace settles a sale -> `payable(R).transfer(royalty)` -> R's
  receive() cannot afford `ILegacyBuffer(hook).fundLegacyBuffer{value:}()`
  (which writes `relaunchETH` or `legacyBuffer`, CauldronHook.sol:1174-1180)
  -> revert -> the sale reverts.
attacker_cost: n/a (configuration, not an attack).  damage: secondary trading
  blocked on that venue for that collection.
poc: none.   needs_fork: no
```

---

## 3. Refutations — surfaces I attacked hard that held

1. **`MiFrensDividend.adopt` as a theft primitive.** I tried to make `adopt`
   (cauldron/MiFrensDividend.sol:323-340) pay a caller twice, or to make it
   re-distribute the `owedAsset` bank. It holds: `owedAsset` credits never
   decrement `accountedOf` (only `_tryPush` on a SUCCESSFUL send does,
   :393-399), so banked balances satisfy `held <= booked` and `adopt` reverts
   `NotShare`. I also tried `castSpell` -> `adopt` -> `claimTokens` -> transfer
   in one transaction: `_castSpell` sets `debtOfAsset[tokenId][a] = acc` for
   every basket asset BEFORE the adopt raises it (:487-497), so the joiner gets
   exactly its 1/activeShares of the newly adopted delta, never history.
2. **`CollectionLedger` round-trip extraction.** `redeem` rounds the payout DOWN
   (:167, `payout = entitledTokens[gen] / n`) and `buyback` requires the registry
   to have taken `2x floor` (:174-181). Redeem-then-buyback loses `~floor` per
   cycle; buyback-then-redeem loses `~floor` per cycle. No direction profits, and
   `totalEntitled` tracks the sum on every branch.
3. **`CauldronToken.burn` ignoring allowance.** It does, but both reachable
   callers bind `from`: `CauldronRegistry.claimByBurn` passes `msg.sender`
   (CauldronRegistry.sol:1310) after a balance check at :1305, and
   `PoolOps.autoMigrateBatch` skips any holder without the `autoMigrate` opt-in
   (PoolOps.sol:1402). `migrateOne` also pays the SAME `from` 1:1 and reverts if
   the reserve is short (PoolOps.sol:1369-1379), so even a forced migration is
   value-neutral.
4. **`MintCurvePolicy` calibration mismatch.** The docstring's claim that
   `CauldronGovernor.propose` bounds `nftSupply` and pins it to the policy's own
   `supply()` is TRUE and I verified it, not just read it:
   CauldronGovernor.sol:532-545 (`if (nftSupply < MIN_NFT_SUPPLY || nftSupply >
   MAX_NFT_SUPPLY) revert`, then `if (calibrated != 0 && nftSupply != calibrated)
   revert SupplyOutOfRange();`) reading `calibrated` from the live hook's
   `curvePolicy()` at :394. The discarded `base`/`step` arguments at
   MintCurvePolicy.sol:119 are therefore inert.
5. **`FeeRouteLib` codeless-recipient hole.** All three send helpers
   (`_move`:105, `_fundGuild`:139, `_deliver`:165) and both external ones
   (`send`:201, `deliver`:231) check `to.code.length == 0` BEFORE the native
   branch, so a codeless recipient cannot absorb ether with a success signal. I
   looked specifically for the one-branch-only variant the comments describe as
   the first cut; it is not present on any of the five.
6. **`hookData` shape mismatch between `_play` and `_churn`.** `_play` encodes
   `(address,uint256[])` and `_churn` encodes `(address)`
   (CauldronGachaRouter.sol:404, :472). The hook only ever decodes the first word
   (`abi.decode(hookData, (address))`, CauldronHook.sol:879, :2479, guarded by
   `hookData.length >= 32`), so the short churn payload does not revert.

---

## 4. Leads (HYPOTHESIS — exact next step given)

- **L1 — `adopt` timing windfall.** `MiFrensDividend.adopt` (:323) distributes an
  entire pushed-in ERC20 balance to whoever is enchanted AT THAT INSTANT. Nothing
  forces it to be called promptly, so a holder who watches `activeShares` and
  fires `adopt` when it dips takes an outsized share of months of accumulated
  royalties. *Next step:* instrument `activeShares` over a simulated season and
  measure the best achievable multiple vs. the time-weighted fair share; if the
  multiple exceeds ~2x for a single caller, this is a Medium.
- **L2 — `_curvePos` underflow across a collection re-set.**
  `CauldronHook._curvePos()` (:2199) is `minted + outstandingOf[collection] -
  mintBaseline`, checked arithmetic, and `setCollection` (:2049) sets
  `mintBaseline = totalMinted()` for a collection that may already carry
  unresolved tickets (the iteration-#2 MiFrens continuation path). *Next step:*
  drive `setCollection(C)` -> commit N tickets -> `setCollection(address(0))` ->
  `setCollection(C)` and check whether any ordering can leave
  `mintBaseline > minted + outstandingOf[C]`, which would revert
  `crystalsReady`/`commitCrystals`/`progress` for the whole generation.
- **L3 — `LegacyBuyLib` reference staleness across a long quiet period.**
  `_syncRef` (:309) only advances when `buyStep` is called, and `buyStep` is only
  reached once the buffer clears `legacyThreshold`. A generation that trends hard
  while the buffer sits under the threshold leaves `ref` far from spot; the first
  buyback then refuses (`lim >= sp`, :208) and catches up at MAX_TICK_DEV=1000
  ticks per BLOCK OF BUYBACK ATTEMPTS. *Next step:* on a fork, hold the buffer
  below threshold across a 3x price move and count how many blocks of trading the
  buyback stays refused; if the catch-up is not automatic, the floor stops
  accruing silently.
- **L4 — `CauldronCollection.setTransferValidator` as a collection-wide brick.**
  `_update` (:167-176) calls `ITransferValidator(v).validateTransfer(...)` with no
  gas cap and no try/catch, for MINTS as well as transfers. A validator that
  reverts (or is later self-destructed / repointed to a reverting contract) makes
  every mint AND every transfer revert, including the hook's win-mint inside
  `afterSwap`. It is `deployer`-gated (the registry), so this is a governance
  risk, not permissionless. *Next step:* confirm whether any registry/timelock
  path can set it to an address chosen by a passing proposal, and whether the
  hook's gas-bounded self-call swallows the resulting revert or wedges the queue.

---

## Reproduce

```
cd contracts/solidity
export FOUNDRY_PROFILE=cauldron FOUNDRY_DISABLE_NIGHTLY_WARNING=1
forge test --match-path 'test/attacks/K4*' -vv
# 2 passed, 0 failed
```
Neither PoC contains `return;` or `vm.skip` at the top level
(`grep -n "return;" test/attacks/K4*.t.sol` -> no hits); all conditional logic
lives in internal helpers returning locals that the `test_*` bodies assert on.
