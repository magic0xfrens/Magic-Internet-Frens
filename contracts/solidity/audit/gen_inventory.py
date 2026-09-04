#!/usr/bin/env python3
"""Emit the annotated function inventory as LaTeX longtables."""
import json, re, sys

INV = json.load(open('/tmp/aud/inventory.json'))

# key: (scope, name) -> (role, reads/writes, external calls)
A = {}


def a(scope, name, role, state="--", calls="--"):
    A[(scope, name)] = (role, state, calls)


# ─────────────────────────── CauldronRegistry ────────────────────────────────
R = "CauldronRegistry"
a(R, "constructor", "Wires poolManager/positionManager/hook into SHARED STORAGE (not immutables, so the facet reads them under delegatecall) and fixes emergencyAdmin/emergencyDelay.", "W poolManager, positionManager, hook, emergencyAdmin, emergencyDelay", "--")
a(R, "setRedemptionExt", "One-shot wiring of the delegatecall facet; rejects EOAs (an empty target would make every forwarded redemption a silent no-op).", "W redemptionExt", "ext.code.length")
a(R, "setReserveCeiling", "Per-iteration reserve ceiling (tick offset, default $\\approx69\\times$), bounded [4000,138000].", "W nextReserveCeilingOffset", "--")
a(R, "setSeeder", "Wires the progressive streamer and propagates it to the hook's in-swap nudge.", "W seeder", "hook.setSeeder")
a(R, "setSeedWindow", "Launch window for the NEXT summon/relaunch; 0 = atomic. Bounded [60s, 7d].", "W nextSeedWindow", "--")
a(R, "enchantFee", "View: token fee a MOVED fren pays to re-enchant = floor $\\times$ enchantFeeMultBps.", "R genesisReserveOutstanding, genesisShares, enchantFeeMultBps", "--")
a(R, "armEmergency", "Announces a custody action on-chain; starts the timelock AND forces the redemption exit open.", "W emergencyReadyAt", "--")
a(R, "setGuardian", "Sets the veto-only safety role (owner pre-handoff, emergencyAdmin after).", "W guardian", "--")
a(R, "vetoEmergency", "Guardian-only cancel of an armed action. Can only block, never move funds.", "W emergencyReadyAt", "--")
a(R, "setRedemptionPaused", "Fast circuit-breaker on the OG redemption path (emergencyAdmin, not timelocked).", "W redemptionPaused", "--")
a(R, "setEnchantFeeMult", "Tunes the re-enchant multiple, capped at $100\\times$.", "W enchantFeeMultBps", "--")
a(R, "emergencyWithdrawLP", "BREAK-GLASS: pulls a generation's active+reserve LP to the admin. Timelocked.", "R generationToken; via \\_removeLiquidity", "PoolOps.removeAll, ISeeder.withdrawAll, IERC20.transfer, admin.call")
a(R, "emergencySweep", "BREAK-GLASS: sweeps the registry's ETH or an ERC20 to the admin. Timelocked.", "--", "IERC20.transfer, admin.call")
a(R, "setSuccessor", "Telegraphs the V2 pointer. Does not move custody.", "W successor", "--")
a(R, "setClaimGate", "Routes instant 1:1 migration through the vesting escrow (0 = off).", "W claimGate", "--")
a(R, "migrateToSuccessor", "V2 HANDOFF: transfers the active+reserve position NFTs' OWNERSHIP (no LP teardown) plus loose token/ETH. Armed+timelocked+vetoable.", "R generationPositionId, generationReservePositionId, generationToken", "IERC721.transferFrom, IERC20.transfer, successor.call")
a(R, "receive", "Accepts ETH (vault sweeps, hook releases, prime-buy funding).", "--", "--")
a(R, "setGovernor", "Points relaunch at the proposal governor.", "W governor", "--")
a(R, "setMinLifetime", "Grace period a newborn brew gets before it can be relaunched.", "W minLifetime", "--")
a(R, "setFactory", "Collection/vault factory (required before summon).", "W factory", "--")
a(R, "setNftMaxSupply", "Default per-brew NFT cap.", "W nftMaxSupply", "--")
a(R, "setRoyalty", "EIP-2981 receiver + rate ($\\le10\\%$) stamped into every brew's collection.", "W royaltyDividend, royaltyBps", "--")
a(R, "setGenesisMetadata", "Iteration-1 art source (renderer or baseURI).", "W genesisMode, genesisBaseURI, genesisRenderer", "--")
a(R, "setGenesisBonus", "Reserves a slice of gen-1 supply for the founding guild; pre-summon only, $\\le30\\%$.", "W mifrens, genesisBonusBps, genesisShares", "--")
a(R, "setAirdropReserve", "Carves an OG-airdrop tranche sent off-LP at summon; capped at 20\\% of supply.", "W airdropWallet, airdropReserve", "--")
a(R, "setPrimeFunder", "Authorises the prime-buy funder (survives the ownership handoff).", "W primeFunder", "--")
a(R, "fundPrimeBuy", "Funder pre-loads personal ETH for the genesis first-block market buy.", "W primeBuyEth", "--")
a(R, "sweepPrimeBuy", "Funder reclaims un-spent prime-buy ETH.", "W primeBuyEth", "msg.sender.call")
a(R, "summon", "GENESIS. Deploys gen-1 token (CREATE2), sizes the genesis bonus, sends the airdrop tranche, seeds the pool (progressive or green-candle), executes the prime buy, deploys the collection.", "W summoned, currentGeneration, currentToken, generationToken, genesisSharePerFren, genesisReserveOutstanding, lastSummonAt, primeBuyEth, \\_seedBuyUnlocked", "PoolOps.creatureFor/deployToken/createAndSeed*/primeBuy, IERC20.transfer, factory.deployBrew, hook.setCollection/setVault")
a(R, "relaunch", "PERMISSIONLESS REBIRTH. Checks death + grace + governance, force-closes perps, tears down the dead LP+seeder, burns recovered supply, drains tickets, closes the vault, pulls hook fees, sizes the new active/reserve split, deploys+seeds the newborn, re-wires the collection and the engine.", "W currentGeneration, currentToken, generationToken/Proposer/Parent, lastSummonAt, genesisReserveOutstanding, genesisPending", "hook.isDead/resolveTickets/relaunchETH/releaseRelaunchETH/forceClosePerps/setActiveProposer/setNftCurveFrom, governor.winner/markConsumed, IVaultClose.close, PoolOps.*, ISeeder.withdrawAll, CauldronToken.burn, factory.*")
a(R, "\\_perpHousekeep", "Best-effort perp relaunch housekeeping: force-close-all (pre-death) or syncGeneration (post-rebirth). try/catch so it can never brick the rebirth.", "--", "hook.perpEngine, hook.forceClosePerps, IPerpSync.syncGeneration")
a(R, "\\_deployCollection", "Deploys a brew's collection+vault via the factory and points the hook at them.", "W generationCollection, generationVault", "factory.deployBrew, hook.setCollection, hook.setVault")
a(R, "\\_continueMiFrens", "Iteration \\#2 special case: CONTINUES the canonical MiFrens collection (new vault only, hook becomes minter).", "W generationCollection, generationVault", "factory.deployVault, IMiFrensContinuable.setVault/setMinter, hook.setCollection/setVault")
a(R, "claimByBurn", "1:1 MIGRATION. Burns the caller's previous-gen balance and releases the same amount from the out-of-range reserve. Deliberately NOT nonReentrant so the perp engine can migrate during relaunch.", "R claimGate, generationToken, generation reserve refs", "hook.perpEngine, PoolOps.migrateOne $\\to$ CauldronToken.burn + PositionManager.modifyLiquidities")
a(R, "enableAutoMigrate", "Opt into keeper-executed migration; free for fren holders, 0.069\\,ETH otherwise.", "W autoMigrate", "IERC721.balanceOf")
a(R, "autoMigrateBatch", "Keeper batch migration for opted-in holders. Disabled while the vesting gate is on.", "R autoMigrate, claimGate", "PoolOps.autoMigrateBatch")
a(R, "redeemOgFren", "Thin DELEGATECALL forwarder to {RedemptionExt}. Must not be nonReentrant (the facet's guard uses the same slot).", "--", "delegatecall redemptionExt")
a(R, "buyTreasuryOgFren", "Forwarder to {RedemptionExt}.", "--", "delegatecall redemptionExt")
a(R, "donateToReserve", "Forwarder to {RedemptionExt}.", "--", "delegatecall redemptionExt")
a(R, "materializeLegacyReserve", "Forwarder to {RedemptionExt}.", "--", "delegatecall redemptionExt")
a(R, "\\_forwardToExt", "Raw-assembly DELEGATECALL of the full calldata into the facet, bubbling returndata/reverts; rejects a zero target.", "R redemptionExt", "delegatecall")
a(R, "setCollectionLedger", "Wires the legacy-floor cap table (0 = feature off).", "W collectionLedger", "--")
a(R, "\\_flushLegacyAtRelaunch", "At death, sweeps the hook's un-materialised buyback tokens, BURNS them, and credits the dying collection's ledger as a pure number.", "W genesisPending", "PoolOps.materializeLegacy")
a(R, "recycleCollectionNFT", "Recycles a volume-collection NFT for its ledger floor, paid from the shared live reserve; NFT moves to the treasury.", "R collectionLedger, generationCollection, reserve refs", "PoolOps.recycleCollection $\\to$ ledger.redeem + collection.custodyTransfer + reserve claim")
a(R, "buyCollectionNFT", "Buys a treasury-held collection NFT at $2\\times$ floor; payment is added to the reserve and ratchets the floor.", "same as above", "PoolOps.buyCollection")
a(R, "\\_removeLiquidity", "Removes BOTH positions of a retired generation and unwinds the seeder's mini-positions; returns (eth, tokens) recovered.", "R generationPoolKey/PositionId/ReservePositionId, seeder", "PoolOps.removeAll, ISeeder.seeding/withdrawAll")
a(R, "\\_deployToken", "CREATE2 token deploy delegated to PoolOps (keeps the 3.2\\,KB creation blob out of the registry).", "--", "PoolOps.deployToken")
a(R, "\\_createPoolAndSeedWithBuy", "ATOMIC seed: green-candle path. Arms \\_seedBuyUnlocked around the PoolManager re-entry.", "W \\_seedBuyUnlocked", "PoolOps.createAndSeedWithBuy")
a(R, "\\_seedGeneration", "Dispatches between the PROGRESSIVE handoff and the ATOMIC green-candle seed.", "R seeder, nextSeedWindow", "PoolOps.createAndSeedProgressive / \\_createPoolAndSeedWithBuy")
a(R, "\\_recordSeed", "Persists poolId/key/positionIds/reserve ticks for a generation.", "W generationPoolId/PoolKey/PositionId/ReservePositionId, reserveTickLower/Upper", "--")
a(R, "unlockCallback", "PoolManager unlock entry, accepted ONLY from the manager and ONLY while a seed/prime buy is armed.", "R poolManager, \\_seedBuyUnlocked", "PoolOps.executeBuy")
a(R, "hasClaimed", "Legacy view over the (now unused) per-generation claimed map.", "R claimed", "--")

# ─────────────────────────── CauldronBase ────────────────────────────────────
B = "CauldronBase"
a(B, "floorPerFren", "LIVE per-fren redemption value = genesisReserveOutstanding / genesisShares. Shared by the registry AND the facet.", "R genesisReserveOutstanding, genesisShares", "--")
a(B, "\\_redeemBlocked", "THE EXIT GUARANTEE: blocked only while the breaker is on AND nothing is armed.", "R redemptionPaused, emergencyReadyAt", "--")
a(B, "constructor", "Ownable(msg.sender). Declares the whole shared storage layout the delegatecall pair depends on.", "--", "--")

# ─────────────────────────── CauldronHook ────────────────────────────────────
H = "CauldronHook"
a(H, "constructor", "BaseHook validates the mined address flags; sets deathThreshold, nftContract, treasury, explicit owner.", "W deathThreshold, nftContract, treasury", "Hooks.validateHookPermissions")
a(H, "getHookPermissions", "Declares afterInitialize + before/afterSwap + both return-delta flags.", "--", "--")
a(H, "\\_afterInitialize", "Marks ANY pool that names this hook as tracked and anchors its anti-snipe window. No allow-list (finding C-01).", "W trackedPools, \\_lastUpdateBlock, poolInitBlock", "--")
a(H, "\\_afterSwap", "The heart: legacy buyback trigger, progressive poke, volume + crystal credit, hint-free perp liquidation sweep, native gacha, and the SELL-leg ETH fee via return delta.", "W volume buckets, cumulativeVolume, nftCredit, lifetimeVolumeOf, totalLifetimeVolume", "seeder.pokeInSwap, perpEngine.sweepLiquidations, self.nativeGachaStep, self.legacyBuyStep, poolManager.take, quest.call")
a(H, "\\_maybeLegacyBuyback", "Gas-bounded, result-ignored self-call that market-buys the token when the buffer is full. Uses the CURRENT swap's PoolKey (finding C-01).", "R legacyRegistry, legacyBuffer, legacyThreshold", "self.legacyBuyStep")
a(H, "\\_maybePoke", "Gas-bounded, result-ignored nudge of the progressive seeder from inside the swap (keeperless streaming).", "R seeder", "seeder.pokeInSwap")
a(H, "legacyBuyStep", "SELF-ONLY. Spends the buffered ETH on a nested exact-input buy, holds the tokens, and books legacyOwedToReserve.", "W legacyBuffer, legacyOwedToReserve, \\_inSelfBuy", "poolManager.swap/settle/take")
a(H, "fundLegacyBuffer", "Permissionless top-up of the buyback buffer (the NFT-royalty entry point).", "W legacyBuffer", "--")
a(H, "sweepLegacyReserve", "Registry-only handover of the held buyback tokens so they can be deposited into the reserve and credited atomically.", "W legacyOwedToReserve", "IERC20.balanceOf/transfer")
a(H, "\\_beforeSwap", "Charges the ETH fee on exact-input BUYS via a beforeSwapDelta. Correctly requires currency0 == address(0).", "--", "\\_takeEthFee")
a(H, "\\_routePerpFee", "Perp-swap fee split: 30\\% to the OG dividend, 70\\% to the side-attributed staker pot; failures roll into relaunchETH.", "W relaunchETH", "guild.call, perpEngine.creditPerpFee/creditPerpFeeToken")
a(H, "\\_routeEthFee", "Organic fee split: proposer slice off the top (PULL), then guild/floor/relaunch with a pluggable IFeeRouter and a built-in fallback; legacyBps carved into the buyback buffer.", "W proposerOwed, legacyBuffer, relaunchETH", "feeRouter.route (try/catch), guild.call, vault.call")
a(H, "snipeSurtaxBps", "Anti-sniper surtax with a pluggable policy, clamped to MAX\\_SNIPE\\_BPS.", "R surtaxPolicy, snipeMaxBps, snipeWindowBlocks", "surtaxPolicy.surtaxBps (try/catch)")
a(H, "\\_defaultSurtaxBps", "Built-in linear decay plus a blockhash-derived jitter (predictable one block ahead --- finding L-02).", "R poolInitBlock, snipeMaxBps, snipeWindowBlocks", "--")
a(H, "\\_takeEthFee", "Takes the total ETH fee (base + surtax, clamped to 99\\%) out of the PoolManager and routes it. Takes key.currency0 WITHOUT checking it is ETH (finding C-01).", "--", "poolManager.take, \\_routePerpFee/\\_routeEthFee, guild.call")
a(H, "setSnipeParams", "Owner-tunable anti-snipe window + peak surtax.", "W snipeWindowBlocks, snipeMaxBps", "--")
a(H, "\\_recordVolume", "24-bucket rolling volume ring keyed on block number.", "W \\_volumeBuckets, \\_lastBucketIndex, \\_lastUpdateBlock", "--")
a(H, "getVolume24h", "Sums the ring; returns 0 once a full day of blocks has passed with no update.", "R \\_volumeBuckets, \\_lastUpdateBlock", "--")
a(H, "isDead", "The relaunch gate. Delegates to a pluggable IDeathChecker with a fallback to the built-in volume rule.", "R trackedPools, deathThreshold, deathChecker", "deathChecker.isDead (try/catch)")
a(H, "\\_getCurrentBucket", "block.number-derived hourly bucket index.", "--", "--")
a(H, "\\_getHolderTaxRate", "Tiered tax from the NFT contract, keyed on the SWAP SENDER (the router, not the trader --- finding L-04).", "R nftContract, defaultTaxBps", "INFTContract.getHolderTaxRate (try/catch)")
a(H, "setDefaultTaxBps", "Flat fee, capped at MAX\\_TAX\\_BPS (10\\%).", "W defaultTaxBps", "--")
a(H, "releaseRelaunchETH", "Registry-only pull of the whole relaunch reserve. Reverts if the send fails --- the DoS surface of finding C-01.", "W relaunchETH", "registry.call")
a(H, "withdrawTokenFees", "Permissionless push of accumulated ERC20 fees to the treasury. DEAD: accumulatedTokenFees is never written (finding I-01).", "W accumulatedTokenFees", "IERC20.transfer")
a(H, "setDeathThreshold", "Owner-tunable 24h volume floor.", "W deathThreshold", "--")
a(H, "forceClosePerps", "Registry-only. Sets the transient relaunch-close flag so the engine's settlement swaps skip the fee/buyback, then force-closes every dead position.", "W \\_inRelaunchClose", "IPerpForceClose.forceCloseAllDead (try/catch)")
a(H, "setLegacyBuyback", "Configures the live buyback (registry or hook owner).", "W legacyRegistry, legacyBps, legacyThreshold", "--")
a(H, "setDeathChecker", "Swaps the death RULE without an upgradeable proxy.", "W deathChecker", "--")
a(H, "setPolicies", "Swaps the surtax / odds / mint-curve policy modules.", "W surtaxPolicy, oddsPolicy, curvePolicy", "--")
a(H, "setFeeRouter", "Swaps the fee-split STRUCTURE (amounts only; the hook still does the sends).", "W feeRouter", "--")
a(H, "setNftContract", "Points the tiered-tax lookup at an NFT contract.", "W nftContract", "--")
a(H, "setTreasury", "ERC20 fee recipient.", "W treasury", "--")
a(H, "setRegistry", "One-shot registry wiring, documented as \"locked forever\" --- defeated by setRegistryOverride (finding M-01).", "W registry", "--")
a(H, "setRegistryOverride", "Owner may RE-POINT the registry at will (the V2 handoff hook). Also the drain path in finding M-01.", "W registry", "--")
a(H, "trackPool", "Owner may mark an arbitrary pool tracked.", "W trackedPools, \\_lastUpdateBlock", "--")
a(H, "setCollection", "Registry-only. Points the hook at the live collection, anchors the mint curve baseline, bumps the credit epoch, auto-wires badges.", "W collection, mintBaseline, creditEpoch", "ICauldronCollection.totalMinted, \\_wireLiquidator")
a(H, "\\_wireLiquidator", "Best-effort wiring of the collection's Liquidatoor minter to the perp engine.", "--", "ICollectionLiquidator.setLiquidatorMinter (try/catch)")
a(H, "setVault", "Registry-only floor-vault pointer (0 under the unified-floor model).", "W vault", "--")
a(H, "setQuest", "Optional post-mintout engagement contract.", "W quest", "--")
a(H, "setSeeder", "Registry/owner wiring of the in-swap progressive nudge (0 disables it).", "W seeder", "--")
a(H, "setPerpEngine", "Registry/owner wiring of the hook-native perp engine; re-wires badge minting.", "W perpEngine", "\\_wireLiquidator")
a(H, "setFloorBps", "Share of the post-guild fee that backs the NFT floor.", "W floorBps", "--")
a(H, "setGuild", "Points the permanent OG-dividend sink.", "W guild", "--")
a(H, "setGuildBps", "Owner-tunable guild share, capped at 5\\% --- BELOW the deployed default of 15\\% (finding I-02).", "W guildBps", "--")
a(H, "setActiveProposer", "Registry pushes the winning proposal's author each relaunch.", "W activeProposer", "--")
a(H, "setProposerBps", "Proposer incentive, capped at MAX\\_PROPOSER\\_BPS (5\\% of the fee).", "W proposerBps", "--")
a(H, "claimProposerFees", "PULL withdrawal of accrued proposer earnings (CEI + nonReentrant).", "W proposerOwed", "msg.sender.call")
a(H, "setNftCurve", "Owner-tunable rising mint curve (base, step).", "W volumePerNFT, nftPriceStep", "--")
a(H, "setCreditUntaggedSwaps", "Toggles crediting raw (non-router) swaps to tx.origin.", "W creditUntaggedSwaps", "--")
a(H, "setNftCurveFrom", "Registry-only flat curve taken from the winning BrewSpec's volumePerNFT.", "W volumePerNFT, nftPriceStep", "--")
a(H, "nftPriceAt", "Credit cost of the k-th crystal (pluggable curve policy, zero-guarded).", "R curvePolicy, volumePerNFT, nftPriceStep", "curvePolicy.priceAt (try/catch)")
a(H, "creditOf", "Player's spendable credit in the current epoch.", "R nftCredit, creditEpoch", "--")
a(H, "\\_curvePos", "Curve position = minted + reserved $-$ baseline (counting reserved stops concurrent commits sharing a slot).", "R collection, outstandingOf, mintBaseline", "ICauldronCollection.totalMinted")
a(H, "crystalsReady", "How many crystals a player can open right now.", "R nftCredit", "\\_curvePos, nftPriceAt")
a(H, "costOfNextCrystals", "Total credit for the next N crystals at today's prices.", "--", "nftPriceAt")
a(H, "oddsForPlay", "Win probability from ETH play size, clamped to ODDS\\_HARD\\_CAP\\_BPS.", "R oddsPolicy, maxOddsBps, oddsFullVolumeWei", "oddsPolicy.oddsBps (try/catch)")
a(H, "outstandingTickets", "Unresolved crystals across all players.", "R outstandingCrystals", "--")
a(H, "mintedOut", "Whether the live collection is sold out.", "R collection", "ICauldronCollection.totalMinted/maxSupply")
a(H, "progress", "UI view: banked credit, next threshold, crystals ready.", "R nftCredit", "nftPriceAt")
a(H, "commitCrystals", "Opener-gated commit: spends credit and enqueues a FIFO lottery batch whose outcome is rolled later from the commit block's hash.", "W nftCredit, committedOf, pendingOf, outstandingCrystals, outstandingOf, batches", "ICauldronCollection.totalMinted/maxSupply")
a(H, "\\_commitCrystals", "Shared commit body (router + native in-swap paths); never reverts when sold out.", "same as above", "--")
a(H, "resolveTickets", "Permissionless FIFO resolution; a win mints the batch's collection, a miss builds the pity counter.", "W batchCursor, batches[].resolved, pendingOf, outstandingCrystals, missStreak, opened", "ICauldronCollection.mint")
a(H, "\\_resolveTickets", "Resolution body. Uses blockhash(commitBlock) with a DETERMINISTIC fallback after 256 blocks (finding M-04).", "same as above", "--")
a(H, "nativeGachaStep", "Self-only in-swap gacha for raw (non-router) buys: commit + resolve, gas-bounded and result-ignored.", "--", "\\_commitCrystals, \\_resolveTickets")
a(H, "setOpener", "Authorises a gacha router (and, in production, the registry) to open crystals + carry honest hookData.", "W isOpener", "--")
a(H, "setTaxExempt", "Flags a fee-exempt player (the launch snipe wallet and the registry's own reseed buy).", "W taxExempt", "--")
a(H, "\\_isExemptPlayer", "Exemption is honoured only when the SENDER is a trusted opener, closing the hookData-spoof hole.", "R isOpener, taxExempt", "--")
a(H, "setOddsParams", "Odds curve size + pity threshold.", "W oddsFullVolumeWei, pityThreshold", "--")
a(H, "setMaxOdds", "Max win chance from bet size, hard-capped.", "W maxOddsBps", "--")
a(H, "setWeights", "Buy/sell credit weighting, capped at $3\\times$.", "W buyWeightBps, sellWeightBps", "--")
a(H, "receive", "Accepts raw ETH (fee takes land here); NOT counted into any tracked bucket.", "--", "--")

# ─────────────────────────── CauldronToken ───────────────────────────────────
T = "CauldronToken"
a(T, "constructor", "Mints the ENTIRE fixed supply once, to the registry. No mint() exists; supply can only ever shrink.", "W generation, birthBlock, registry, balances", "ERC20.\\_mint")
a(T, "burn", "Registry-only burn --- used for dead-LP recovery, 1:1 migration, and the legacy flush.", "W totalSupply, balances", "--")

# ─────────────────────────── RedemptionExt ───────────────────────────────────
E = "RedemptionExt"
a(E, "redeemOgFren", "RECYCLE an OG fren for its live floor share. Effects first (debit reserve, move NFT to treasury), then pull tokens from the reserve LP.", "W genesisReserveOutstanding (registry's)", "IERC721.ownerOf, IMiFrensContinuable.custodyTransfer, PoolOps.claimFromReserve")
a(E, "buyTreasuryOgFren", "Buys a treasury-held fren for $2\\times$ floor, paid in the live token, which is added to the reserve (floor ratchet).", "W genesisReserveOutstanding", "IERC721.ownerOf, \\_pullGrow, custodyTransfer")
a(E, "donateToReserve", "Permissionless floor growth; the re-enchant fee routes through here.", "W genesisReserveOutstanding", "\\_pullGrow")
a(E, "materializeLegacyReserve", "Permissionless: sweeps the hook's held buyback tokens INTO the reserve and credits the ledger in one step (Invariant R by construction).", "W genesisPending", "PoolOps.materializeLegacy")
a(E, "\\_pullGrow", "transferFrom + addToReserve + reserve accounting; emits FloorGrew.", "W genesisReserveOutstanding", "IERC20.transferFrom, PoolOps.addToReserve")

# ─────────────────────────── PoolOps ─────────────────────────────────────────
P = "PoolOps"
a(P, "creatureFor", "The cycling gen-1/fallback creature name+symbol table (kept out of the registry for EIP-170).", "--", "--")
a(P, "\\_approve", "ERC20 approve to Permit2 + Permit2 approve to the PositionManager (300s expiry).", "--", "IERC20.approve, IPermit2Ops.approve")
a(P, "\\_sqrtPrice", "Babylonian sqrt of (tokenAmount $\\ll$ 192)/ethAmount. Reverts on ethAmount == 0.", "--", "--")
a(P, "createAndSeed", "Reference two-position seed (no buy): init pool, mint the full-range active position, mint the out-of-range reserve.", "--", "poolManager.initialize, \\_seedActive, \\_seedReserve")
a(P, "createAndSeedProgressive", "PROGRESSIVE handoff: places ledger B (reserve) in full, approves ledger A to the seeder and starts the campaign. activePositionId stays 0.", "--", "poolManager.initialize, \\_seedReserve, IERC20.approve, ISeeder.startSeed")
a(P, "createAndSeedWithBuy", "GREEN CANDLE: seed 100\\% of supply at a discount, buy exactly the reserve back out (a real first-block trade), re-park it out of range below the post-buy spot.", "--", "poolManager.initialize/unlock/getSlot0, \\_seedActive, \\_seedReserve")
a(P, "executeBuy", "Unlock body for the seed/prime buy, running in the REGISTRY's context; tags hookData with the registry so the hook waives the fee.", "--", "poolManager.swap/settle/take")
a(P, "primeBuy", "Owner-funded exact-input market buy whose output goes straight to the treasury (net demand, zero dilution).", "--", "poolManager.unlock")
a(P, "deployToken", "CREATE2 token deploy (salt = generation) with address(this) = the registry.", "--", "new CauldronToken")
a(P, "\\_seedActive", "Mints the full-range ACTIVE position (ETH + tradeable tokens) and sweeps excess ETH back.", "--", "\\_approve, pm.nextTokenId, pm.modifyLiquidities")
a(P, "\\_seedReserve", "Mints the single-sided RESERVE position below the launch tick (pure token1).", "--", "ReserveLib.liquidityForTokenOut, \\_approve, pm.modifyLiquidities")
a(P, "removeAll", "Removes 100\\% of a position, takes both currencies, burns the NFT; returns balance deltas.", "--", "pm.getPositionLiquidity, pm.modifyLiquidities")
a(P, "claimFromReserve", "Pulls EXACTLY `amount` from the reserve to a recipient --- but CAPS at the position's liquidity and returns silently short (finding H-03).", "--", "ReserveLib.liquidityForTokenOut, pm.getPositionLiquidity, pm.modifyLiquidities")
a(P, "addToReserve", "Single-sided top-up of the reserve position; returns the amount actually consumed.", "--", "\\_approve, pm.modifyLiquidities")
a(P, "migrateOne", "Burn old + claim the same from the reserve. Shared by claimByBurn and the keeper batch.", "--", "ICauldronBurn.burn, claimFromReserve")
a(P, "autoMigrateBatch", "Keeper loop over opted-in holders; reads the opt-in flag via a self-call so it resolves to the registry.", "--", "IAutoFlag.autoMigrate, IERC20.balanceOf, migrateOne")
a(P, "doLegacyNote", "Splits a live buyback between the forged tranche's ledger and the OG genesis reserve when iteration \\#2 continues MiFrens.", "--", "IColMinted.totalMinted, ILedgerOps.credit")
a(P, "materializeLegacy", "Sweeps the hook's buyback tokens and either deposits them into the reserve (live) or burns them and carries the value as a number (relaunch flush).", "--", "ILegacyHookOps.legacyRegistry/sweepLegacyReserve, addToReserve, ICauldronBurn.burn, doLegacyNote")
a(P, "crystallizeCollection", "At death, freezes a collection's supply and folds the final swept-ETH sizing into its token entitlement.", "--", "ILedgerOps.crystallized/crystallize, IVaultRedeemedOps.outstanding")
a(P, "recycleCollection", "Debits the ledger, moves the NFT to the treasury, pays the floor from the live reserve. Calls collection.custodyTransfer --- which the factory-deployed collection rejects (finding H-01).", "--", "ICollectionOps.ownerOf/custodyTransfer, ILedgerOps.redeem, claimFromReserve")
a(P, "buyCollection", "Buys a treasury NFT at $2\\times$ floor, adds the payment to the reserve, ratchets the ledger, hands the NFT over.", "--", "ILedgerOps.floorPerNFT/buyback, IERC20.transferFrom, addToReserve, custodyTransfer")

# ─────────────────────────── CauldronSeeder ──────────────────────────────────
S = "CauldronSeeder"
a(S, "constructor", "Binds the registry, the (unused) PositionManager and the PoolManager.", "W registry, positionManager, poolManager", "--")
a(S, "receive", "Accepts ETH (ledger-A funding and pool takes).", "--", "--")
a(S, "startSeed", "Registry-only campaign start: pulls ledger-A tokens, receives ledger-A ETH, places the base + floor slice. Does NOT reset `complete`/`\\_basePlaced` (finding H-02).", "W \\_key, token, gen, startTs, window, seedFloorWad, ethTotal, tokenTotal, minStepWad, baseWad, \\_spacing, \\_bandWidth, seeding, placedWad", "IERC20.transferFrom, poolManager.unlock")
a(S, "poke", "Permissionless standalone nudge (self-unlock). Un-accelerable: the target is a pure function of elapsed time.", "W placedWad, complete", "poolManager.unlock, \\_advance")
a(S, "pokeInSwap", "Hook-only in-swap nudge: places DIRECTLY because the caller already holds the unlock.", "W placedWad, complete", "\\_placeStep, \\_advance")
a(S, "\\_pendingStep", "The throttled step to deploy now; returns 0 when not seeding, complete, or below minStepWad.", "R seeding, complete, placedWad, startTs, window", "SeedLib.deployedTargetWad")
a(S, "\\_advance", "Snaps placedWad to the schedule target and flips `complete` at 100\\%.", "W placedWad, complete", "poolManager.getSlot0")
a(S, "unlockCallback", "PoolManager-only dispatcher for the PLACE and WITHDRAW bodies.", "--", "\\_placeStep / \\_teardown")
a(S, "\\_placeStep", "Places one ASK (token, below spot) + one BID (ETH, above spot) band via CORE modifyLiquidity, laying the two-sided base on the first placement.", "W ranges, \\_basePlaced", "poolManager.getSlot0/modifyLiquidity, \\_settle, \\_track")
a(S, "\\_teardown", "Removes every tracked range and forwards all recovered + un-streamed funds to the registry.", "W \\_lastEthOut, \\_lastTokenOut", "poolManager.getPositionInfo/modifyLiquidity, IERC20.transfer, to.call")
a(S, "\\_placeBase", "Lays baseWad of ledger A as ONE two-sided full-range position so the book is continuous and perps have spot-straddling depth.", "W ranges", "poolManager.getSlot0/modifyLiquidity")
a(S, "\\_settle", "Pays owed currencies and takes owed-to-us ones; settles currency1 first so the synced-currency slot is reset before the native settle.", "--", "poolManager.sync/settle/take, IERC20.transfer")
a(S, "\\_track", "Records a distinct (lo,hi) range once; reverts BandCap at MAX\\_RANGES = 64 so teardown gas stays bounded.", "W ranges", "--")
a(S, "withdrawAll", "Registry-only teardown at death; ends the campaign and clears the range set.", "W ranges, seeding, complete", "poolManager.unlock")
a(S, "rescue", "Registry-only escape hatch for loose ledger-A funds. UNREACHABLE: the registry exposes no caller (finding I-03).", "W seeding", "IERC20.transfer, to.call")
a(S, "deployedWad", "Fraction of the stream budget deployed so far.", "R placedWad", "--")
a(S, "rangeCount", "Number of distinct tracked ranges.", "R ranges", "--")
a(S, "isComplete", "Whether the campaign has finished streaming.", "R complete", "--")

# ─────────────────────────── PerpEngine ──────────────────────────────────────
PE = "PerpEngine"
a(PE, "constructor", "Binds poolManager/hook/registry/mifrens, seeds the tier table, the TWAP ring and the synced generation.", "W dividend, treasury, nftBeneficiary, tierDepthWei, tierLeverage, lastFundingAt, observations, obsIndex, lastObsTs, lastTick, syncedGeneration, syncedToken", "registry.currentGeneration/currentToken, poolManager.getSlot0")
a(PE, "totalEth", "ETH the ETH-vault owns = free PLV + lent to open longs (insurance excluded).", "R plv, longOiEth", "--")
a(PE, "freeEth", "Instantly withdrawable ETH.", "R plv", "--")
a(PE, "totalTokenAssets", "Token the token-vault owns = free inventory + lent to shorts.", "R plvToken, shortOiToken", "--")
a(PE, "freeToken", "Instantly withdrawable token inventory.", "R plvToken", "--")
a(PE, "\\_key", "Rebuilds the live PoolKey from registry.currentToken() on every call.", "--", "registry.currentToken")
a(PE, "\\_sqrtP", "Spot sqrtPrice of the live pool.", "--", "poolManager.getSlot0")
a(PE, "\\_currentTick", "Spot tick of the live pool.", "--", "poolManager.getSlot0")
a(PE, "poke", "Permissionless keeper entry that refreshes the TWAP observation and accrues funding.", "--", "\\_pokeFunding")
a(PE, "\\_writeObs", "Writes a TWAP observation, throttled to OBS\\_INTERVAL so the ring cannot be flooded.", "W tickCumulative, observations, obsIndex, lastObsTs, lastTick", "\\_currentTick")
a(PE, "twapTick", "Time-weighted average tick over twapWindow, falling back to the oldest observation if it still spans MIN\\_TWAP.", "R observations, tickCumulative, lastObsTs, lastTick, twapWindow", "--")
a(PE, "markSqrtPriceX96", "The manipulation-resistant liquidation mark (TWAP tick; spot only at genuine cold start).", "--", "twapTick, \\_sqrtP")
a(PE, "activeEthDepth", "ETH-equivalent depth at the current tick; drives leverage tiers, notional caps and the per-block liquidation cap.", "--", "poolManager.getLiquidity/getSlot0")
a(PE, "maxLeverage", "Depth-tiered leverage, clamped by maxLeverageCeiling.", "R tierDepthWei, tierLeverage, maxLeverageCeiling", "activeEthDepth")
a(PE, "\\_quoteAt", "token $\\to$ ETH at a given sqrtPrice.", "--", "--")
a(PE, "\\_quoteEth", "token $\\to$ ETH at SPOT (funding sizing --- spot-manipulable, see finding L-05).", "--", "\\_sqrtP")
a(PE, "\\_quoteMark", "token $\\to$ ETH at the TWAP MARK (liquidation trigger).", "--", "markSqrtPriceX96")
a(PE, "\\_pokeFunding", "Accrues the global funding index from the signed OI imbalance $\\times$ elapsed time.", "W lastFundingAt, fundingIndex", "\\_writeObs, \\_quoteEth")
a(PE, "\\_fundingDelta", "Signed funding P\\&L for one position, notional pinned to entry and bounded to $\\pm$maxFundingBps of collateral.", "R fundingIndex, maxFundingBps", "--")
a(PE, "fundingDelta", "UI view of the above.", "--", "--")
a(PE, "openLong", "2-arg overload forwarding to the 3-arg openLong.", "--", "openLong")
a(PE, "openLong", "Opens a LONG: takes the open fee, borrows ETH from the PLV, buys token (real price impact), books the position, then best-effort sweeps liquidations.", "W plv, longOiEth, positions, nextId, openCount, \\_openIds, \\_openPos", "\\_guardOpen, \\_pokeFunding, \\_takeFee, \\_swapExactIn, \\_book, \\_sweepAfterOpen")
a(PE, "openShort", "Opens a SHORT: borrows token inventory, sells it (price down), holds ETH backing.", "W plvToken, shortOiToken, positions, openCount, \\_openIds", "\\_guardOpen, \\_ethToToken, \\_swapExactIn, \\_book, \\_sweepAfterOpen")
a(PE, "close", "Trader-only close with slippage protection.", "--", "\\_pokeFunding, \\_settle")
a(PE, "liquidate", "Permissionless keeper liquidation, gated on the TWAP mark and the per-timestamp notional cap.", "W liqBlock, liqEthThisBlock", "\\_quoteMark, \\_underwaterVal, activeEthDepth, \\_settle")
a(PE, "liquidateInSwap", "Hook-only single in-swap liquidation; never reverts the triggering swap.", "W \\_liqReentry, \\_inLocked", "\\_pokeFunding, \\_tryLiquidate")
a(PE, "liquidateManyInSwap", "Hook-only batch in-swap liquidation, capped at MAX\\_LIQ\\_PER\\_SWAP.", "same", "\\_tryLiquidate")
a(PE, "sweepLiquidations", "Hook-only HINT-FREE sweep fired from every swap; scans a rotating window and credits tx.origin.", "--", "\\_doSweep")
a(PE, "selfSweep", "Self-only post-open sweep entry so it can be wrapped in try/catch with its own unlock.", "--", "\\_doSweep")
a(PE, "\\_sweepAfterOpen", "Gas-reserved best-effort sweep after an open.", "--", "this.selfSweep (try/catch)")
a(PE, "\\_doSweep", "Bounded rotating-window scan (SWEEP\\_SCAN checks, MAX\\_LIQ\\_PER\\_SWAP kills).", "W sweepCursor, \\_liqReentry, \\_inLocked", "\\_tryLiquidate")
a(PE, "\\_tryLiquidate", "Liquidates one position if genuinely underwater at the mark and within the cap; otherwise a silent no-op.", "W liqBlock, liqEthThisBlock", "\\_quoteMark, \\_underwaterVal, \\_settle")
a(PE, "forceCloseDead", "Permissionless solvent close once the token is dead; pays the caller a keeper reward.", "--", "\\_isDead, \\_pokeFunding, \\_settle")
a(PE, "forceCloseAllDead", "Closes the whole open set oldest-first (bounded to 96). Reverts wholesale if ANY position's payout send fails (finding H-04).", "--", "\\_settle")
a(PE, "syncGeneration", "Re-arms the engine on a new generation: migrates the dead inventory 1:1, re-points plvToken, resets the TWAP ring. Requires openCount == 0.", "W plvToken, shortOiToken, longOiEth, observations, tickCumulative, obsIndex, lastObsTs, lastTick, syncedGeneration, syncedToken", "registry.claimByBurn (try/catch), IERC20.balanceOf")
a(PE, "isLiquidatable", "View: is the position underwater at the mark?", "--", "\\_underwater")
a(PE, "\\_underwater", "Underwater test at the TWAP mark.", "--", "\\_quoteMark, \\_underwaterVal")
a(PE, "\\_underwaterVal", "Underwater test given a pre-computed mark value (long: value $<$ debt + buffer; short: buy-back cost + buffer $>$ backing).", "R maintenanceBps", "--")
a(PE, "\\_settle", "THE settlement core: unwinds the position through a real pool swap, repays/absorbs, applies funding, takes the liquidation penalty, pays keeper + trader.", "W positions, openCount, longOiEth/shortOiToken, plv, plvToken, insuranceEth", "\\_swapExactIn/\\_buyExactOut, \\_replenishPlv/\\_absorbPlvLoss, \\_routeFee, \\_sendEth, \\_awardBadge")
a(PE, "\\_run", "Routes a swap through a fresh unlock or directly, depending on \\_inLocked.", "--", "poolManager.unlock / \\_execSwap")
a(PE, "\\_swapExactIn", "Exact-input swap helper.", "--", "\\_run")
a(PE, "\\_buyExactOut", "Exact-output buy (makes the short inventory whole).", "--", "\\_run")
a(PE, "unlockCallback", "PoolManager-only unlock entry.", "--", "\\_execSwap")
a(PE, "\\_execSwap", "Swap body: performs the pool swap tagged with nftBeneficiary and settles both legs.", "--", "poolManager.swap, \\_settleCur, \\_take")
a(PE, "\\_guardOpen", "Blocks opens before the warmup, once the token is dead, or above the depth-tiered leverage.", "--", "registry.lastSummonAt, \\_isDead, maxLeverage")
a(PE, "\\_isDead", "Reads the hook's death verdict, defaulting to \"alive\" on revert.", "--", "IPerpHook.isDead (try/catch)")
a(PE, "\\_takeFee", "Charges the 6.9\\% open fee (halved for fren holders) and routes it.", "--", "mifrens.balanceOf, \\_routeFee")
a(PE, "\\_checkNotional", "Caps a single position's notional at maxNotionalBps of depth (bounded slippage).", "--", "activeEthDepth")
a(PE, "\\_book", "Writes the position and adds it to the enumerable open set.", "W nextId, openCount, positions, \\_openIds, \\_openPos", "--")
a(PE, "\\_removeOpen", "Swap-and-pop removal from the open set.", "W \\_openIds, \\_openPos", "--")
a(PE, "\\_ethToToken", "ETH $\\to$ token at spot.", "--", "\\_sqrtP")
a(PE, "\\_routeFee", "Carves LP yield + insurance (side-attributed) then splits the remainder dividend/treasury. Uses a REVERTING send (finding H-04).", "W plv, tokYieldEth, tokYieldCumulative, insuranceEth", "\\_sendEth")
a(PE, "\\_sendEth", "Raw ETH send that REVERTS on failure --- the griefing primitive behind finding H-04.", "--", "to.call")
a(PE, "\\_replenishPlv", "Long bad debt: refills plv from insurance up to the buffer.", "W insuranceEth, plv", "--")
a(PE, "\\_absorbPlvLoss", "Short bad debt: absorbs the overspend from insurance then LP principal (saturating).", "W insuranceEth, plv", "--")
a(PE, "\\_awardBadge", "HYBRID trophy: gas-bounded in-swap mint, else a claimable credit. A zero collection address returns success and silently loses the badge (finding L-06).", "W badgesOwed", "IPerpHook.collection, ILiquidatorMintable.mintLiquidator")
a(PE, "claimLiquidatorBadges", "Claims owed badges into the LIVE collection, bounded by n.", "W badgesOwed", "IPerpHook.collection, mintLiquidator")
a(PE, "\\_settleCur", "Settles a currency leg (native via value, ERC20 via sync+transfer+settle).", "--", "poolManager.sync/settle, \\_safeTransfer")
a(PE, "\\_take", "poolManager.take wrapper.", "--", "poolManager.take")
a(PE, "\\_safeTransfer", "Return-value-tolerant ERC20 transfer.", "--", "token.call")
a(PE, "fundPlv", "Owner-only, SHARE-LESS permanent ETH donation to the PLV.", "W plv", "--")
a(PE, "fundPlvToken", "Owner-only, share-less token inventory donation.", "W plvToken", "IERC20.transferFrom")
a(PE, "fundInsurance", "Permissionless insurance top-up.", "W insuranceEth", "--")
a(PE, "creditPerpFee", "Hook-only: credits a redirected perp BUY fee into the ETH PLV.", "W plv", "--")
a(PE, "creditPerpFeeToken", "Hook-only: credits a redirected perp SELL fee into the segregated token-side pot.", "W tokYieldEth, tokYieldCumulative", "--")
a(PE, "\\_creditPerp", "Shared body; hook-gated, pure accounting so it is safe to nest mid-swap.", "W plv / tokYieldEth", "--")
a(PE, "fundFromVault", "Vault-only ETH deposit into the PLV.", "W plv", "--")
a(PE, "withdrawPlvTo", "Vault-only pull of FREE ETH.", "W plv", "\\_sendEth")
a(PE, "withdrawTokYieldTo", "Vault-only pull from the segregated short-side yield pot.", "W tokYieldEth", "\\_sendEth")
a(PE, "fundTokenFromVault", "Vault-only token deposit into the short inventory.", "W plvToken", "IERC20.transferFrom")
a(PE, "withdrawPlvTokenTo", "Vault-only pull of FREE token inventory.", "W plvToken", "\\_safeTransfer")
a(PE, "setFees", "Open fee / OG discount / liq penalty / dividend share / keeper cut, all bounded.", "W openFeeBps, ogDiscountBps, liqPenaltyBps, divShareBps, keeperBps", "--")
a(PE, "setRisk", "Warmup, leverage ceiling, maintenance, notional and OI caps, funding rate. Enforces warmup $\\ge$ MIN\\_TWAP.", "W warmup, maxLeverageCeiling, maintenanceBps, maxNotionalBps, maxOiBps, fundingRateBpsPerDay", "--")
a(PE, "setTwapWindow", "Tunes the liquidation-mark averaging window down to a 1s floor.", "W twapWindow", "--")
a(PE, "setTiers", "Depth$\\to$leverage tier table; requires levs.length == depths.length + 1.", "W tierDepthWei, tierLeverage", "--")
a(PE, "setRouting", "Dividend + treasury sinks.", "W dividend, treasury", "--")
a(PE, "setNftBeneficiary", "Where perp-volume gacha creatures accrue.", "W nftBeneficiary", "--")
a(PE, "setGuards", "TWAP window, per-block liquidation cap, funding cap.", "W twapWindow, maxLiqBps, maxFundingBps", "--")
a(PE, "setVault", "Wires the community PLV. DRAIN GUARD: cannot be re-pointed while depositor funds are staked.", "W vault", "--")
a(PE, "setVaultSplit", "LP-yield / insurance shares of routed fees.", "W vaultYieldBps, insuranceBps", "--")
a(PE, "setVaultLimits", "Utilisation cap + insurance circuit-breaker floor.", "W maxUtilBps, insuranceFloor", "--")
a(PE, "setMinCollateral", "Dust filter on opens, capped at 1 ETH.", "W minCollateral", "--")
a(PE, "skimInsurance", "Owner may skim insurance ABOVE insuranceFloor --- which defaults to 0 (finding M-05).", "W insuranceEth", "\\_sendEth")
a(PE, "positionHealth", "UI view: mark value, debt/backing, liquidatable.", "--", "\\_quoteMark, \\_underwater")
a(PE, "receive", "Accepts ETH (pool takes, keeper refunds).", "--", "--")

# ─────────────────────────── PerpVault ───────────────────────────────────────
V = "PerpVault"
a(V, "constructor", "Binds the engine and the registry (for currentToken).", "W engine, registry", "--")
a(V, "assetsEth", "ETH backing LIVE shares = engine.totalEth() $-$ queued exits.", "R pendingEth", "engine.totalEth")
a(V, "assetsTok", "Token backing live shares = engine.totalTokenAssets() $-$ queued exits.", "R pendingTok", "engine.totalTokenAssets")
a(V, "depositEth", "Mints ETH-side shares at the pre-deposit price with a $10^6$ virtual-share offset, then funds the engine.", "W ethShares, ethShareOf", "engine.fundFromVault")
a(V, "withdrawEth", "Burns shares, pays up to the engine's free ETH, queues the remainder (CEI).", "W ethShareOf, ethShares, pendingEth, pendingEthOf", "engine.freeEth/withdrawPlvTo")
a(V, "claimPendingEth", "Claims a queued ETH exit as liquidity frees up.", "W pendingEthOf, pendingEth", "engine.freeEth/withdrawPlvTo")
a(V, "\\_syncTokYield", "Folds newly-accrued short-side yield into the per-share accumulator. SKIPS the fold at zero shares WITHOUT advancing the watermark (finding H-05).", "W accEthPerTokShare, lastTokYieldCum", "engine.tokYieldCumulative")
a(V, "\\_settleTok", "Banks a user's earned-so-far ETH before their share count changes.", "W tokRewardOwed", "--")
a(V, "\\_resetTokDebt", "Rebases a user's reward baseline to their current share count.", "W tokRewardDebt", "--")
a(V, "depositToken", "Stakes the live token to back shorts; pulls from the user and pushes into the engine.", "W tokShares, tokShareOf, tokRewardDebt", "registry.currentToken, \\_pull, \\_approve, engine.fundTokenFromVault")
a(V, "claimTokYield", "Claims accrued short-side ETH reward from the segregated pot.", "W tokRewardOwed", "engine.withdrawTokYieldTo")
a(V, "withdrawToken", "Burns token shares, pays up to free inventory, queues the rest.", "W tokShareOf, tokShares, pendingTok, pendingTokOf", "engine.freeToken/withdrawPlvTokenTo")
a(V, "claimPendingToken", "Claims a queued token exit.", "W pendingTokOf, pendingTok", "engine.freeToken/withdrawPlvTokenTo")
a(V, "ethPosition", "UI view: redeemable / instantly available / queued ETH.", "--", "engine.freeEth")
a(V, "tokenPosition", "UI view for the token side.", "--", "engine.freeToken")
a(V, "pendingTokYield", "UI view of accrued-but-unclaimed short-side ETH.", "--", "engine.tokYieldCumulative")
a(V, "\\_pull", "Return-value-tolerant transferFrom.", "--", "token.call")
a(V, "\\_approve", "Return-value-tolerant approve.", "--", "token.call")

# ─────────────────────────── MigrationVesting ────────────────────────────────
MV = "MigrationVesting"
a(MV, "constructor", "Binds the registry, the governance owner, the initial window (bounded 1h--14d) and the instant-tier oracle.", "W vestWindow, stakerOracle", "--")
a(MV, "startVest", "Pulls the caller's dead-gen tokens, migrates 1:1 through the registry, books a linear grant, and auto-releases if the wallet is instant-tier.", "W \\_grants", "IERC20.transferFrom, registry.claimByBurn, \\_release")
a(MV, "vestBatch", "Keeper batch: books grants for every holder who has approved the escrow. Best-effort per holder.", "W \\_grants", "IERC20.balanceOf/allowance, \\_pullAndVest")
a(MV, "\\_pullAndVest", "Pull + migrate + book, verifying the live-token delta actually landed.", "W \\_grants", "IERC20.transferFrom/balanceOf, registry.claimByBurn, \\_isInstant")
a(MV, "claim", "Releases everything currently vested across the caller's grants.", "W \\_grants", "\\_release")
a(MV, "claimFor", "Permissionless release TO the beneficiary (keeper convenience).", "W \\_grants", "\\_release")
a(MV, "\\_release", "Pays vested-minus-released per grant and prunes drained grants (swap-pop). Per-grant token pinning survives a mid-vest relaunch.", "W \\_grants", "IERC20.transfer")
a(MV, "\\_vestedOf", "Linear schedule; window 0 = instant.", "--", "--")
a(MV, "\\_isInstant", "Consults the staker oracle; a reverting oracle means \"not instant\" (the safe outcome).", "--", "stakerOracle.isInstant (try/catch)")
a(MV, "claimable", "Total claimable across a holder's grants.", "--", "--")
a(MV, "locked", "Total still locked across a holder's grants.", "--", "--")
a(MV, "grantCount", "Number of open grants.", "--", "--")
a(MV, "grantAt", "Reads one grant.", "--", "--")
a(MV, "setVestWindow", "Governance-tunable window for FUTURE grants (existing grants keep their snapshot).", "W vestWindow", "--")
a(MV, "setStakerOracle", "Swaps the instant-tier policy.", "W stakerOracle", "--")

# ─────────────────────────── CauldronGovernor ────────────────────────────────
G = "CauldronGovernor"
a(G, "constructor", "Binds the MiFrens checkpointed-voting electorate.", "W mifrens", "--")
a(G, "setRegistry", "One-shot, owner-gated wiring of the registry allowed to consume winners.", "W registry", "--")
a(G, "propose", "Guild-gated proposal of the next brew (name, ticker, metadata, NFT supply, mint-out target). NO bound on nftSupply (finding C-02).", "W proposalCount, \\_proposals", "mifrens.getVotes")
a(G, "displayName", "\"$\\langle$name$\\rangle$ by Magic Internet Frens\".", "--", "--")
a(G, "vote", "One vote per address per proposal, weighted by CHECKPOINTED power at the proposal's snapshot block.", "W hasVoted, \\_proposals[].votes, \\_leaderId, \\_leaderVotes", "mifrens.getPastVotes")
a(G, "winner", "Returns the LIVE leader --- there is no voting deadline, so it is front-runnable (finding M-02).", "--", "\\_bestUnconsumed")
a(G, "hasProposals", "Whether any unconsumed proposal has votes.", "--", "\\_bestUnconsumed")
a(G, "markConsumed", "Registry-only retirement of a summoned proposal; recomputes the leader lazily.", "W \\_proposals[].consumed, \\_leaderId, \\_leaderVotes", "--")
a(G, "getProposal", "Full proposal record.", "--", "--")
a(G, "\\_bestUnconsumed", "Cached leader if still valid, else a full recompute.", "--", "--")
a(G, "\\_recomputeLeader", "O(n) scan for the highest-voted unconsumed proposal.", "--", "--")

# ─────────────────────────── CollectionLedger ────────────────────────────────
CL = "CollectionLedger"
a(CL, "constructor", "Binds the sole mutator (the registry).", "W registry", "--")
a(CL, "outstanding", "Entitled NFT count = supply (live mint count or frozen snapshot) $-$ retired.", "R crystallized, frozenSupply, retired", "--")
a(CL, "floorPerNFT", "Tokens one NFT of a generation can redeem right now.", "R entitledTokens", "--")
a(CL, "credit", "Registry-only: grows a collection's entitlement (live buyback / royalty inflow).", "W entitledTokens, totalEntitled", "--")
a(CL, "redeem", "Registry-only: pays one NFT its floor (round DOWN), retires it, debits the pot.", "W entitledTokens, retired, totalEntitled", "--")
a(CL, "buyback", "Registry-only: credits a $2\\times$-floor resale and un-retires the NFT (floor ratchet).", "W entitledTokens, retired, totalEntitled", "--")
a(CL, "crystallize", "Registry-only one-time freeze of a dead collection's supply plus a final entitlement fold.", "W crystallized, frozenSupply, entitledTokens, totalEntitled", "--")

# ─────────────────────────── CauldronVault ───────────────────────────────────
CV = "CauldronVault"
a(CV, "outstanding", "NFTs this vault backs = eligible minted (above floorOffset) $-$ redeemed.", "R redeemed, floorOffset", "collection.totalMinted")
a(CV, "constructor", "Binds the collection, the registry and the genesis floorOffset.", "W collection, registry, floorOffset", "--")
a(CV, "receive", "Accepts fee ETH (unused under the unified-floor model, where hook.setVault(0) is wired).", "--", "--")
a(CV, "floorPerNFT", "balance / outstanding.", "--", "outstanding")
a(CV, "redeem", "Burns an eligible NFT for its equal share of the pooled ETH. Always reverts under the unified model (no ETH ever arrives).", "W redeemed", "collection.ownerOf/burnFromVault, msg.sender.call")
a(CV, "close", "Registry-only: stops redemption and sweeps the remaining ETH into the next launch.", "W closed", "registry.call")

# ─────────────────────────── CauldronCollection ──────────────────────────────
CC = "CauldronCollection"
a(CC, "constructor", "Fixes the minter (the hook), the DEPLOYER (the FACTORY --- finding H-01), maxSupply (must stay below the badge id range), metadata and royalty.", "W minter, deployer, maxSupply, mode, renderer, \\_baseTokenURI, royalty", "ERC2981.\\_setDefaultRoyalty")
a(CC, "\\_update", "ERC-721C: routes every mint/transfer/burn through the transfer validator when one is set.", "--", "ITransferValidator.validateTransfer")
a(CC, "getTransferValidator", "ERC-721C discovery.", "--", "--")
a(CC, "getTransferValidationFunction", "ERC-721C discovery.", "--", "--")
a(CC, "setTransferValidator", "Deployer-gated --- unreachable in production (finding H-01).", "W transferValidator", "--")
a(CC, "supportsInterface", "ERC165 over ERC721 + ERC2981 + ICreatorToken.", "--", "--")
a(CC, "mint", "Minter-only art mint; records the mint block for the commit-reveal rarity roll.", "W totalMinted, mintBlockOf", "ERC721.\\_mint")
a(CC, "reveal", "Owner-only rarity reveal from blockhash(mintBlock), with a deterministic fallback after 256 blocks (finding M-03).", "W rarityOf, revealed", "--")
a(CC, "\\_rollRarity", "Cumulative-bps tier roll.", "R rarityCumBps", "--")
a(CC, "setVault", "One-shot vault wiring (the factory does this at deploy).", "W vault", "--")
a(CC, "setRoyalty", "Deployer-gated royalty re-point (the factory does this at deploy).", "--", "\\_setDefaultRoyalty")
a(CC, "setLiquidatorMinter", "Deployer OR minter (so the hook can auto-wire badges each relaunch).", "W liquidatorMinter", "--")
a(CC, "setMetadata", "Deployer-gated art repoint --- unreachable in production (finding H-01).", "W mode, renderer, \\_baseTokenURI", "--")
a(CC, "setLiquidatorURI", "Deployer-gated badge metadata base --- unreachable in production.", "W liquidatorURI", "--")
a(CC, "mintLiquidator", "Engine-only trophy mint in a separate uncapped id range.", "W liquidatorMinted, isLiquidatoor", "ERC721.\\_mint")
a(CC, "liquidatoorTrait", "Marketplace helper.", "--", "--")
a(CC, "burnFromVault", "Vault-only burn on ETH-floor redemption.", "--", "ERC721.\\_burn")
a(CC, "custodyTransfer", "Approval-free move for the legacy recycle. Gated on `deployer`, which is the FACTORY --- so the registry can never call it (finding H-01).", "--", "ERC721.\\_transfer")
a(CC, "tokenURI", "Badge / unrevealed / renderer / rarity-partitioned baseURI resolution.", "--", "ICollectionRenderer.tokenURI")
a(CC, "setRarityOdds", "Deployer-gated, pre-first-mint odds config --- unreachable in production.", "W rarityCumBps", "--")

# ─────────────────────────── CauldronFactory ─────────────────────────────────
F = "CauldronFactory"
a(F, "deployBrew", "Deploys collection + vault + royalty router and wires them. The FACTORY becomes the collection's `deployer` (finding H-01).", "--", "new CauldronCollection/CauldronVault/RoyaltyRouter, col.setVault/setRoyalty")
a(F, "deployVault", "Deploys a fresh per-iteration vault for an EXISTING collection (the MiFrens continuation).", "--", "new CauldronVault")

# ─────────────────────────── MiFrensGenesis ──────────────────────────────────
MG = "MiFrensGenesis"
a(MG, "constructor", "Fixes the OG tranche size, art cap (below the badge id range), price and per-wallet cap.", "W GENESIS\\_SUPPLY, MAX\\_SUPPLY, PRICE, MAX\\_PER\\_WALLET, \\_base, deployer", "--")
a(MG, "setRegistry", "One-shot deployer wiring of the registry this presale ignites.", "W registry", "--")
a(MG, "mint", "Presale mint of the OG tranche at an exact price, per-wallet capped; records `paid` for a possible refund.", "W paid, minted, revealed, balances", "ERC721.\\_mint")
a(MG, "cancelPresale", "Deployer safety valve for a stalled presale; opens refunds.", "W cancelled", "--")
a(MG, "refund", "Post-cancel reclaim of 100\\% of what a wallet paid (CEI).", "W paid", "msg.sender.call")
a(MG, "totalMinted", "ICauldronCollection surface.", "R minted", "--")
a(MG, "maxSupply", "ICauldronCollection surface.", "--", "--")
a(MG, "setMinter", "Registry/deployer wiring of the volume hook for the iteration-\\#2 continuation.", "W minter", "--")
a(MG, "setVault", "Registry/deployer wiring of the per-iteration floor vault.", "W vault", "--")
a(MG, "setDividend", "Wires the dividend so genesis transfers break the enchantment.", "W dividend", "--")
a(MG, "setLiquidatorMinter", "Deployer/registry/minter wiring of the badge minter.", "W liquidatorMinter", "--")
a(MG, "setLiquidatorURI", "Deployer-gated badge metadata base.", "W liquidatorURI", "--")
a(MG, "mintLiquidator", "Engine-only trophy mint in the badge id range. NOTE: this collection is ERC721Votes, so a badge carries a governance vote.", "W liquidatorMinted, isLiquidatoor", "ERC721.\\_mint")
a(MG, "liquidatoorTrait", "Marketplace helper.", "--", "--")
a(MG, "custodyTransfer", "REGISTRY-gated approval-free move (the OG recycle). Correctly gated, unlike CauldronCollection's.", "--", "ERC721.\\_transfer")
a(MG, "setFinalizer", "Restricts who may ignite genesis, so the team's atomic summon+buy cannot be front-run.", "W finalizer", "--")
a(MG, "setMetadata", "Deployer-gated art source config.", "W mode, renderer, \\_base", "--")
a(MG, "setRarityOdds", "Deployer-gated gacha odds.", "W rarityCumBps", "--")
a(MG, "setRoyalty", "Deployer-gated EIP-2981 receiver + rate.", "--", "\\_setDefaultRoyalty")
a(MG, "getTransferValidator", "ERC-721C discovery.", "--", "--")
a(MG, "getTransferValidationFunction", "ERC-721C discovery.", "--", "--")
a(MG, "setTransferValidator", "Deployer-gated validator wiring.", "W transferValidator", "--")
a(MG, "mint", "VOLUME mint (the iteration-\\#2 continuation): hook-only, records the mint block for the reveal roll.", "W minted, mintBlockOf", "ERC721.\\_mint")
a(MG, "reveal", "Owner-only rarity reveal with the same 256-block fallback as CauldronCollection (finding M-03).", "W rarityOf, revealed", "--")
a(MG, "burnFromVault", "Vault-only burn on floor redemption.", "--", "ERC721.\\_burn")
a(MG, "\\_rollRarity", "Cumulative-bps tier roll.", "--", "--")
a(MG, "finalize", "IGNITION: forwards the entire treasury into registry.summon(). One-shot, sellout-gated, optionally finalizer-gated.", "W finalized", "registry.summon")
a(MG, "soldOut", "Whether the OG tranche has minted out.", "--", "--")
a(MG, "remaining", "OG tranche remaining.", "--", "--")
a(MG, "isGenesis", "The permanent OG mark, derived from the id and the immutable tranche size.", "--", "--")
a(MG, "ogTrait", "\"Genesis\" or \"Standard\" for metadata.", "--", "--")
a(MG, "tokenURI", "Badge / unrevealed / renderer / baseURI resolution.", "--", "ICollectionRenderer.tokenURI")
a(MG, "\\_update", "ERC721+ERC721Votes diamond resolution, auto-delegation, dividend spell-break and everMoved --- all gated on `tokenId <= GENESIS\\_SUPPLY` (finding M-06).", "W everMoved, voting checkpoints", "ITransferValidator.validateTransfer, IMiFrensDividendHook.onMiFrenTransfer (try/catch)")
a(MG, "\\_increaseBalance", "ERC721Votes plumbing.", "--", "--")
a(MG, "supportsInterface", "ERC165 over ERC721 + ERC2981 + ICreatorToken.", "--", "--")

# ─────────────────────────── MiFrensDividend ─────────────────────────────────
MD = "MiFrensDividend"
a(MD, "constructor", "Reads GENESIS\\_SUPPLY / MAX\\_SUPPLY off the collection and fixes the treasury sink.", "W SHARES, MAX\\_TOKEN, treasury", "IMiFrensShares.GENESIS\\_SUPPLY/MAX\\_SUPPLY")
a(MD, "setRegistry", "One-shot, treasury-gated wiring so a moved fren's re-enchant fee routes into the reserve.", "W registry", "--")
a(MD, "receive", "Fee inflow. Splits across the ENCHANTED set; with no active shares the pot sweeps to the treasury instead of banking up.", "W totalDeposited, accPerShare, residual", "treasury.call")
a(MD, "pending", "Claimable ETH for a fren (0 unless enchanted by its current owner).", "R accPerShare, debtOf, enchantedBy", "mifrens.ownerOf")
a(MD, "isEnchanted", "Whether a fren is currently drawing fees.", "--", "mifrens.ownerOf")
a(MD, "castSpell", "Enchant a fren you own so it joins the earning set.", "--", "\\_castSpell")
a(MD, "castMany", "Batch enchant.", "--", "\\_castSpell")
a(MD, "\\_castSpell", "Join (collect the fee, bump activeShares) or re-point a stale enchantment (settle the prior caster, count unchanged).", "W activeShares, debtOf, enchantedBy, owed", "mifrens.ownerOf, \\_collectEnchantFee")
a(MD, "\\_collectEnchantFee", "Charges MOVED frens (and every forged fren) the reserve-growing re-enchant fee; original OGs are free.", "--", "registry.enchantFee/currentToken/donateToReserve, IERC20.transferFrom/approve")
a(MD, "onMiFrenTransfer", "Collection-only hook: settles the leaver and frees its active share. Only ever fired for GENESIS ids (finding M-06).", "W owed, activeShares, enchantedBy, debtOf", "--")
a(MD, "claim", "Claims one fren's accrued ETH (CEI + nonReentrant).", "--", "\\_claim")
a(MD, "claimMany", "Batch claim.", "--", "\\_claim")
a(MD, "withdrawOwed", "Pull-withdraw of ETH settled when a fren left the active set.", "W owed, totalClaimed", "msg.sender.call")
a(MD, "\\_claim", "Ownership + enchantment checks, debt update before the send.", "W debtOf, totalClaimed", "mifrens.ownerOf, msg.sender.call")

# ─────────────────────────── CauldronGachaRouter ─────────────────────────────
GR = "CauldronGachaRouter"
a(GR, "constructor", "Binds the PoolManager, the hook, the registry and the owner.", "--", "--")
a(GR, "\\_key", "Rebuilds the live PoolKey from registry.currentToken().", "--", "registry.currentToken")
a(GR, "play", "One-click buy and/or sell, tagged with the PLAYER so the hook credits them, then commit + resolve crystals.", "--", "poolManager.unlock, hook.commitCrystals/resolveTickets")
a(GR, "playLiq", "Same as play but carries perp liquidation hints in hookData.", "--", "\\_play")
a(GR, "\\_play", "Body: pulls the sell input, runs the unlock, enforces slippage, commits+resolves (effects), then pays out (interactions).", "--", "\\_safeTransferFrom, poolManager.unlock, hook.commitCrystals/resolveTickets, msg.sender.call")
a(GR, "openReady", "Opens crystals from ALREADY-earned credit; derives an honest play size from the credit spent.", "--", "hook.crystalsReady/costOfNextCrystals/buyWeightBps/commitCrystals/resolveTickets")
a(GR, "playChurn", "Volume amplifier: up to 10 buy$\\to$sell legs in one tx, each credited to the player (each leg pays the hook fee).", "--", "poolManager.unlock, hook.commitCrystals/resolveTickets")
a(GR, "unlockCallback", "PoolManager-only dispatcher for the play and churn bodies.", "--", "\\_churn / inline swap legs")
a(GR, "\\_churn", "The churn loop: alternating exact-input swaps, settling each leg.", "--", "poolManager.swap, \\_settle, \\_take")
a(GR, "\\_limit", "Directional sqrtPrice limits.", "--", "--")
a(GR, "\\_settle", "Native settle-with-value or sync+transfer+settle for the ERC20 leg.", "--", "poolManager.sync/settle")
a(GR, "\\_take", "poolManager.take wrapper.", "--", "poolManager.take")
a(GR, "\\_safeTransfer", "Return-value-tolerant ERC20 transfer.", "--", "token.call")
a(GR, "\\_safeTransferFrom", "Return-value-tolerant ERC20 transferFrom.", "--", "token.call")
a(GR, "rescueETH", "Owner sweep of stray ETH (the router holds nothing between transactions).", "--", "to.call")
a(GR, "receive", "Accepts ETH (sell proceeds land here transiently).", "--", "--")

# ─────────────────────────── LaunchSniper ────────────────────────────────────
LS = "LaunchSniper"
a(LS, "constructor", "Owner binding.", "--", "--")
a(LS, "launch", "ATOMIC ignition + funding buy: finalize the presale (summons gen-1 and seeds the pool) then immediately buy through the gacha router and forward the tokens to the airdrop wallet. Nothing can execute in between.", "--", "presale.soldOut/finalize, registry.currentToken, gachaRouter.play, IERC20.balanceOf/transfer")
a(LS, "sweep", "Owner recovery of stray ETH/tokens.", "--", "owner.call, IERC20.transfer")
a(LS, "receive", "Accepts refunds from the router.", "--", "--")

# ─────────────────────────── small contracts ─────────────────────────────────
a("DefaultFeeRouter", "route", "Reference IFeeRouter reproducing the hook's built-in split; pure, owner-less, custody-free.", "--", "--")
a("RoyaltyRouter", "constructor", "Binds the hook whose buyback buffer these royalties fund.", "--", "--")
a("RoyaltyRouter", "receive", "Forwards marketplace royalty ETH straight into the hook's legacy buyback buffer.", "--", "hook.fundLegacyBuffer")
a("PerpStakerOracle", "constructor", "Binds the PerpVault whose shares define the instant tier.", "--", "--")
a("PerpStakerOracle", "isInstant", "A wallet is instant-tier iff it holds a live ETH- or token-side PLV share.", "--", "perpVault.ethShareOf/tokShareOf")
a("LaunchLib", "displayName", "Hardcoded on-chain branding: \"$\\langle$name$\\rangle$ by Magic Internet Frens\".", "--", "--")

# ─────────────────────────── libraries ───────────────────────────────────────
RL = "ReserveLib"
a(RL, "\\_alignDown", "Aligns a tick DOWN to a spacing multiple (toward $-\\infty$).", "--", "--")
a(RL, "\\_alignUp", "Aligns a tick UP to a spacing multiple (toward $+\\infty$).", "--", "--")
a(RL, "reserveTicks", "The reserve band: from the lowest usable aligned tick up to launchTick $-$ offset, collapsing to one spacing if degenerate. ORIENTATION is load-bearing (below launch $\\Rightarrow$ pure token1).", "--", "--")
a(RL, "liquidityForTokenOut", "Liquidity representing exactly `amount1` for a fully-below-price range, rounding DOWN. Reverts SafeCastOverflow for pathologically low ticks (finding I-05).", "--", "LiquidityAmounts.getLiquidityForAmount1")
SL = "SeedLib"
a(SL, "\\_alignDown", "Tick alignment (down).", "--", "--")
a(SL, "\\_alignUp", "Tick alignment (up).", "--", "--")
a(SL, "deployedTargetWad", "The progressive schedule: linear from seedFloor at start to 100\\% at start+window; window 0 = atomic. Pure function of elapsed time, hence un-accelerable.", "--", "--")
a(SL, "askBand", "The i-th single-sided TOKEN band BELOW the launch tick (what buyers eat).", "--", "--")
a(SL, "bidBand", "The j-th single-sided ETH band ABOVE the launch tick (what sellers hit).", "--", "--")
a(SL, "\\_bandWidth", "Equal band width tiling an offset into n bands, never below one spacing.", "--", "--")
a(SL, "taperWeightWad", "Descending per-band weight, summing to 1e18 bar dust.", "--", "--")

# ─────────────────────────── interface declarations ──────────────────────────
IFACE_NOTE = {
    "ICauldronFactory": "Factory surface the registry drives; declared in CauldronBase so registry and facet see identical types.",
    "IMiFrensContinuable": "The canonical MiFrens surface for the iteration-\\#2 continuation and the OG recycle.",
    "IVaultClose": "Vault close/sweep at relaunch.",
    "IPerpSync": "Perp relaunch housekeeping.",
    "ICollectionLedger": "Legacy cap-table read the registry sizes the new reserve against.",
    "IPositionManager": "Minimal V4 PositionManager surface (declared locally to avoid permit2's solc pin).",
    "IPerpEngineLiq": "In-swap liquidation surface the hook calls from afterSwap.",
    "ICollectionLiquidator": "Badge-minter wiring the hook auto-applies per brew.",
    "ILegacyNote": "Legacy buyback note (superseded by the sweep+credit pair).",
    "IPerpForceClose": "Relaunch force-close surface.",
    "IPerpFeeCredit": "Perp-fee credit surface (ETH side / token side).",
    "ISeederInSwap": "The seeder's in-swap nudge.",
    "ICauldronHookGacha": "Hook gacha surface the router drives.",
    "IRegistryCurrent": "Live-token read.",
    "IBurnableCollection": "Collection surface the ETH floor vault burns through.",
    "ICollectionRenderer": "On-chain art renderer surface.",
    "ICauldronGovernor": "Governor surface the registry consumes on relaunch.",
    "ICauldronCollection": "Mint surface the volume hook drives.",
    "ITransferValidator": "ERC-721C validator the collections defer to.",
    "ICreatorToken": "ERC-721C discovery surface markets recognise.",
    "IDeathChecker": "Pluggable death rule.",
    "ILiquidatorMintable": "Liquidatoor badge mint surface.",
    "ISurtaxPolicy": "Pluggable anti-snipe surtax curve.",
    "IOddsPolicy": "Pluggable gacha odds curve.",
    "ICurvePolicy": "Pluggable mint-cost curve.",
    "IFeeRouter": "Pluggable ETH fee-split STRUCTURE (amounts only; the hook keeps custody).",
    "ISeeder": "Progressive seeder surface shared by PoolOps and CauldronSeeder.",
    "IMiFrensGenesisFinalize": "Presale ignition surface.",
    "IGachaPlay": "Router play surface.",
    "IMiFrensShares": "MiFrens reads the dividend needs.",
    "IReserveRegistry": "Registry reads the dividend needs to price + route the re-enchant fee.",
    "IRegistrySummon": "Registry summon surface the presale ignites.",
    "IMiFrensDividendHook": "Spell-break ping on a genesis transfer.",
    "IVestingRegistry": "Registry migration primitive the escrow wraps.",
    "IStakerOracle": "Pluggable instant-tier policy.",
    "IPerpRegistry": "Registry reads the perp engine needs.",
    "IPerpHook": "Hook reads the perp engine needs.",
    "IPerpShares": "PerpVault share reads.",
    "IPerpEngineVault": "Engine surface the community vault drives.",
    "IVaultRegistry": "Live-token read for the vault.",
    "IPositionManagerOps": "Minimal PositionManager surface used by PoolOps.",
    "ILedgerOps": "Ledger surface PoolOps drives.",
    "IColMinted": "Live mint-count read.",
    "IVaultRedeemedOps": "Vault outstanding/redeemed reads used at crystallisation.",
    "ICollectionOps": "Collection custody surface.",
    "ILegacyHookOps": "Hook legacy-sweep surface.",
    "ICauldronBurn": "Token burn surface.",
    "IAutoFlag": "Auto-migrate opt-in read (self-call under delegatecall).",
    "IPermit2Ops": "Permit2 approve surface.",
    "ILegacyBuffer": "Hook buffer top-up surface.",
}


def esc(s):
    return (s.replace('\\', r'\textbackslash{}') if False else s).replace('_', r'\_').replace('&', r'\&').replace('%', r'\%').replace('#', r'\#')


def camel(s):
    """Insert zero-width break opportunities before interior capitals so a long
    identifier wraps inside the narrow name column instead of overflowing."""
    out = []
    for i, ch in enumerate(s):
        if i and ch.isupper() and s[i - 1].islower():
            out.append(r'\allowbreak{}')
        out.append(ch)
    return ''.join(out)


def brk(s):
    """Allow long slash/comma/dot-separated call lists to wrap in a narrow column."""
    for ch in ('/', ',', '.'):
        s = s.replace(ch, ch + r'\allowbreak{}')
    return s


def ann_for(x):
    key = (x['scope'], x['name'].replace('_', r'\_'))
    if key in A:
        return A[key]
    key2 = (x['scope'], x['name'])
    if key2 in A:
        return A[key2]
    if x['kind'] == 'interface':
        note = IFACE_NOTE.get(x['scope'], 'External surface declaration.')
        return (f"Interface declaration --- {note}", '--', '--')
    return ('(see source)', '--', '--')


out = []
from collections import OrderedDict
groups = OrderedDict()
for x in INV:
    groups.setdefault((x['file'], x['scope'], x['kind']), []).append(x)

total = 0
for (f, sc, kind), items in groups.items():
    total += len(items)
    out.append(r'\subsubsection*{\texttt{%s} \textemdash{} %s \texttt{%s} \hfill \normalfont\small(%d functions)}'
               % (esc(f), esc(kind), esc(sc), len(items)))
    out.append(r'\begin{longtable}{@{}>{\raggedright\arraybackslash}p{0.20\textwidth}p{0.045\textwidth}p{0.042\textwidth}p{0.083\textwidth}>{\raggedright\arraybackslash}p{0.54\textwidth}@{}}')
    out.append(r'\toprule \textbf{Function} & \textbf{Vis.} & \textbf{Mut.} & \textbf{Access} & \textbf{Role, state touched, external calls} \\ \midrule \endhead')
    for x in items:
        role, state, calls = ann_for(x)
        mods = ', '.join(m for m in x['mods'] if m not in ('override', 'virtual')) or '--'
        body = role
        if state != '--':
            body += r' \newline \textit{State:} ' + brk(state)
        if calls != '--':
            body += r' \newline \textit{Calls:} ' + brk(calls)
        out.append(r'\texttt{%s}\,{\tiny L%d} & %s & %s & %s & %s \\' % (
            camel(esc(x['name'])), x['line'], x['vis'][:4], (x['mut'] or '--')[:4],
            camel(brk(esc(mods))), body))
    out.append(r'\bottomrule\end{longtable}')

sys.stderr.write("emitted %d function rows\n" % total)
open('/tmp/aud/inventory.tex', 'w').write('\n'.join(out))
