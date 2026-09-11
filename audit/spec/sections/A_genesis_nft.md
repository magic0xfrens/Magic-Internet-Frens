# Area A — Genesis & NFT Collection

Sources read in full: `contracts/solidity/cauldron/MiFrensGenesis.sol` (718 lines), `contracts/solidity/cauldron/CauldronCollection.sol` (432), `contracts/solidity/cauldron/CauldronGachaRouter.sol` (448), `contracts/solidity/cauldron/MintCurvePolicy.sol` (114), `contracts/solidity/cauldron/ILiquidatorMintable.sol` (48). Skimmed: `contracts/solidity/render/LiquidatoorRenderer.sol`. Grepped callers: `contracts/solidity/CauldronRegistry.sol`, `contracts/solidity/CauldronFactory.sol`, and (for the money/authority chain the task asked to trace) `contracts/solidity/CauldronHook.sol`.

Legend: **INTENT** = what NatSpec/comments/names claim. **ACTUAL** = what the traced code does. **DELTA** = a place they disagree (see `## Open deltas`; not fixed here, not security-judged).

---

## A1 — Presale (`MiFrensGenesis.mint(uint256)` + cancel/refund)

**Purpose.** Sell the OG "rare" tranche (tokenIds `1..GENESIS_SUPPLY`) for ETH; the raised ETH is the *only* funding source for genesis ignition (no owner withdraw path exists).

**Entrypoints.**
- `MiFrensGenesis.mint(uint256 quantity)` — `external payable nonReentrant`, no authority modifier (open to any address). `MiFrensGenesis.sol:262`.
- `MiFrensGenesis.cancelPresale()` — `if (msg.sender != deployer) revert NotAuthorized();` `MiFrensGenesis.sol:290`.
- `MiFrensGenesis.refund()` — `external nonReentrant`, no authority gate beyond `cancelled` state. `MiFrensGenesis.sol:300`.

**Preconditions (`mint`).** `!finalized` (`MiFrensGenesis.sol:263`, else `PresaleOver`); `!cancelled` (`:264`, else `AlreadyCancelled`); `quantity != 0` (`:265`); `minted + quantity <= GENESIS_SUPPLY` (`:266`, else `ExceedsSupply`); `msg.value == PRICE * quantity` exactly (`:267`, else `WrongPrice`); `balanceOf(msg.sender) + quantity <= MAX_PER_WALLET` (`:268`, else `PerWalletCap`).

**Behavior (`mint`).** `paid[msg.sender] += msg.value` is recorded for a possible refund (`:270`). `minted` is cached in memory, ids `first..first+quantity-1` are minted in a loop; each is marked `revealed[id] = true` **immediately** (genesis tranche is never in the unrevealed state) before `_mint` (`:276-281`); `minted` is written back once (`:282`); `Bought(buyer, quantity, first)` emitted (`:283`).

**Behavior (`cancelPresale`).** Only pre-`finalized` (`:291`, else `PresaleOver`), only once (`:292`, else `AlreadyCancelled`); sets `cancelled = true`, emits `PresaleCancelled` (`:293-294`).

**Behavior (`refund`).** Requires `cancelled` (`:301`, else `NotCancelled`). `amount = paid[msg.sender]`, reverts `NothingToRefund` if zero (`:302-303`). `paid[msg.sender]` is zeroed **before** the external call (CEI, `:304`), then `msg.sender.call{value: amount}("")`, reverting `RefundFailed` on failure (`:305-306`); emits `Refunded` (`:307`). NFTs already minted to the caller are **not** reclaimed or burned — comment at `:297-299` states they are left in place as "orphaned art" since the collection never launches.

**Postconditions & invariants.** `minted` monotonically increases and never exceeds `GENESIS_SUPPLY` while unfinalized. Every genesis-tranche id is `revealed == true` at mint (no reveal step ever applies to ids `1..GENESIS_SUPPLY`). Once `cancelled`, `mint` can never succeed again (`AlreadyCancelled` check precedes nothing that could clear it). `paid[addr]` sums every ETH contribution by `addr` across possibly-many `mint` calls, and is the exact refundable amount.

**Edge cases.** `quantity == 0` is rejected explicitly (`ExceedsSupply`, reused error) rather than silently no-op-ing (`:265`). A `refund()` call with `amount == 0` (never bought, or already refunded) reverts rather than no-op-sending zero ETH. `cancelPresale` is irreversible — there is no "un-cancel" path in the file.

**Events.** `Bought(indexed buyer, quantity, firstTokenId)` `:219`. `PresaleCancelled()` `:150`. `Refunded(indexed buyer, amount)` `:151`.

**DENOMINATION: ETH-only** — `PRICE` is an immutable wei amount (`MiFrensGenesis.sol:118`), `mint` requires `msg.value == PRICE * quantity` (`:267`), `refund` pays native ETH via `.call{value: amount}` (`:305`). By design/INTENT this generation predates the quote-allowlist system: `CauldronRegistry.sol:675-677` — "`generationQuote[1]` stays `address(0)` = native ETH. Generation 1 launches from the presale before any proposal exists to name a quote." Not flagged as a delta on its own (see `## Open deltas`, D5, for the scope caveat this creates against the protocol's broader any-quote claim).

---

## A2 — Mint, supply caps, price curve

Two structurally different mint paths share the name `mint` (overloaded) in `MiFrensGenesis`, plus one equivalent in `CauldronCollection`.

**(a) Presale mint** — `MiFrensGenesis.mint(uint256 quantity)`, covered fully in A1. ETH-priced, immediate, no gacha.

**(b) Volume mint** — `MiFrensGenesis.mint(address to)` `MiFrensGenesis.sol:474`, and `CauldronCollection.mint(address to)` `CauldronCollection.sol:207`.

**Purpose.** Mint the next sequential art token to `to`, funded not by direct payment but by swap-volume "credit" tracked in `CauldronHook`; called only when a gacha ticket wins (see A4).

**Entrypoints & authority.**
- `MiFrensGenesis.mint(address to)`: `if (msg.sender != minter) revert OnlyMinter();` `MiFrensGenesis.sol:475`. `minter` is wired by `CauldronRegistry._continueMiFrens` → `IMiFrensContinuable(col).setMinter(address(hook))`, `CauldronRegistry.sol:1146`.
- `CauldronCollection.mint(address to)`: `if (msg.sender != minter) revert OnlyMinter();` `CauldronCollection.sol:208`. `minter` is an immutable set at construction to `c.hook`, `CauldronFactory.sol:71-73` / `CauldronCollection.sol:37,155`.

**Preconditions.** `minted >= MAX_SUPPLY` → `MintedOut` (`MiFrensGenesis.sol:476`); `totalMinted >= maxSupply` → `MintedOut` (`CauldronCollection.sol:209`).

**Behavior.** Genesis: `tokenId = minted + 1; minted++;` then `mintBlockOf[tokenId] = uint48(block.number)` (commit for later reveal) then `_mint(to, tokenId)`, emits `VolumeMinted(to, tokenId, 0)` — rarity `0` is provisional until `reveal()` (`MiFrensGenesis.sol:477-482`). Collection: `tokenId = ++totalMinted` (1-indexed) then identical commit/mint/emit `Minted(to, tokenId, 0)` (`CauldronCollection.sol:210-214`). **Neither function is `payable` and neither reads `msg.value`** — the collection contracts never touch money for this path.

**Supply caps.** `MiFrensGenesis`: constructor requires `maxSupply_ >= genesisSupply_ && maxSupply_ < LIQUIDATOR_ID_BASE` (`MiFrensGenesis.sol:239`, else `ExceedsSupply`) — keeps the art tranche below the badge id range (A5). `CauldronCollection`: constructor requires `maxSupply_ != 0 && maxSupply_ < LIQUIDATOR_ID_BASE` (`CauldronCollection.sol:148`, else `BadConfig`).

**Price curve (`MintCurvePolicy`).** `priceAt(uint256 k, uint256, uint256)` returns `base + (spread * k * k) / (k + knee)` — quadratic near `k=0`, asymptotically linear for large `k` (`MintCurvePolicy.sol:95-100`, shape documented `:11-24`). `totalToMintOut()` sums the whole ladder on-chain so a deployment can verify its calibration rather than trust the constructor argument (`:108-113`). Consumed by `CauldronHook.nftPriceAt(uint256 k)`: tries `curvePolicy.priceAt(k, volumePerNFT, nftPriceStep)` in a `try/catch`, rejects a zero result ("a zero cost would let credit mint infinite NFTs"), and falls back to `volumePerNFT + k * nftPriceStep` if no policy is set or the call reverts (`CauldronHook.sol:2011-2020`). "Price" here is spent from `nftCredit[creditEpoch][player]`, accumulated from swap volume, not paid directly to the mint call.

**Postconditions & invariants.** `minted`/`totalMinted` strictly increase by 1 per call and never exceed the respective cap. `MintCurvePolicy.sol:30-42` documents (and the file's own comment states is asserted by a test named `F13`) that the curve's core economic invariant — `cost(n) > mean(cost[0..n-1])`, i.e. each new NFT's fee contribution to the floor exceeds the per-NFT dilution it causes — holds independent of the fee rate, the token price, **and the quote asset** ("`r` cancels. So does the token price, and so does the quote asset.", `:39`).

**Edge cases.** `MintedOut` is a hard stop with no queue/refund — a gacha win rolled after mint-out simply cannot call `mint` (see A4, "sold-out crystals resolve as misses").

**Events.** `VolumeMinted(indexed to, indexed tokenId, rarity)` `MiFrensGenesis.sol:221`. `Minted(indexed to, indexed tokenId, rarity)` `CauldronCollection.sol:120`.

**DENOMINATION:**
- Presale (a): **ETH-only** (see A1).
- Volume mint (b): **quote-agnostic** — `mint(address)` in both contracts is non-`payable`, has no `address(0)`/native-asset sentinel, and moves no value; the "price" it is gated behind is credit tracked by `CauldronHook`, which is normalized to USD (1e18) once an oracle is wired (`CauldronHook.sol:705`, `_toUsd`) or left in raw quote units otherwise, and `MintCurvePolicy.sol:30-42` proves its floor-safety invariant is independent of which quote asset is live. No `msg.value`/`payable`/hardcoded-decimal evidence found in either `mint(address)` body.

---

## A3 — Reveal (`reveal`, `revealBatch`)

**Purpose.** Roll the gacha rarity of a volume-minted (unrevealed) token from an on-chain, mint-time-unknowable seed, and flip its metadata from placeholder to final.

**Entrypoints.**
- `reveal(uint256 tokenId)` → `_reveal` — no explicit modifier; ownership enforced inside `_reveal`. `MiFrensGenesis.sol:487` / `CauldronCollection.sol:219`.
- `revealBatch(uint256[] calldata tokenIds)` — bounds `0 < n <= 50` else `BadBatch`, then loops `_reveal`. `MiFrensGenesis.sol:507-513` / `CauldronCollection.sol:239-245`.

**Preconditions (`_reveal`).** `ownerOf(tokenId) == msg.sender`, else reverts `OnlyMinter` (name reused — see D2 in Open deltas) (`MiFrensGenesis.sol:516` / `CauldronCollection.sol:248`). If already `revealed[tokenId]`, the function is a silent no-op (`:517` / `:249`). Otherwise `block.number > mintBlockOf[tokenId]` required, else `NotReady` — "seed not known yet" (`:518-519` / `:250-251`).

**Behavior.** `bh = blockhash(mintBlockOf[tokenId])`. **Expired-seed re-anchor:** if `bh == 0` (blockhash unavailable, i.e. commit block is >256 blocks old), the function does **not** revert — it re-anchors `mintBlockOf[tokenId] = block.number`, emits `ReAnchored(tokenId, newMintBlock)`, and returns quietly, leaving the token still unrevealed for a later call (`:521-536` / `:253-268`, "we must NOT revert here — a revert would roll the re-anchor back, leaving the token stuck"). Otherwise: `rarity = _rollRarity(keccak256(bh, tokenId, address(this)))`, `rarityOf[tokenId] = rarity`, `revealed[tokenId] = true`, emits `Revealed(tokenId, rarity)` (`:537-540` / `:269-272`). `_rollRarity(seed)`: `r = seed % 10_000`, walks the 4-entry cumulative-bps table `rarityCumBps` (default `[7900, 9400, 9900, 10000]`, tiers `0=Common,1=Rare,2=Epic,3=Ultra`) returning the first bucket `r` falls under, defaulting to `0` (`:550-556` / `:276-282`).

**Randomness source.** The token's **own** mint block's future hash — recorded at mint time (`mintBlockOf[tokenId] = uint48(block.number)`, `MiFrensGenesis.sol:480` / `CauldronCollection.sol:212`), unknowable to the minter, and (per comment) deliberately not `block.prevrandao` because "Arbitrum/Orbit `prevrandao` is a constant (1)" (`MiFrensGenesis.sol:213-216` / `CauldronCollection.sol:106-111`).

**Postconditions & invariants.** A batch call skips already-revealed ids rather than reverting (`:502-503`/comment), so a caller may pass an unfiltered wallet. Randomness is per-token independent — "N independent draws," no shared seed to grind (`:498-501`/comment).

**Edge cases.** `revealBatch` bounds `n` to `[1,50]` so a caller "cannot build a batch that runs out of gas midway and wastes the whole fee" (`:509-511` / `:241-243`). A stale/expired seed inside a batch re-anchors that one token and the loop continues to the next id (per docstring, `:505`).

**Genesis-tranche scope.** Only volume-minted tokens (`tokenId > GENESIS_SUPPLY`) are ever unrevealed — confirmed at `tokenURI`: `if (tokenId > GENESIS_SUPPLY && !revealed[tokenId]) return unrevealedURI;` (`MiFrensGenesis.sol:632`). Genesis-tranche ids are set `revealed = true` at mint (A1, `:278`), so `reveal`/`revealBatch` are functional no-ops for them (ownership check would pass, but `revealed[tokenId]` is already `true` so the body is skipped at `:517`/`:249`).

**Events.** `Revealed(indexed tokenId, rarity)` `MiFrensGenesis.sol:222` / `CauldronCollection.sol:121`. `ReAnchored(indexed tokenId, newMintBlock)` `MiFrensGenesis.sol:225` / `CauldronCollection.sol:124`.

**DENOMINATION: quote-agnostic** (trivially) — no `msg.value`/`payable` anywhere in `reveal`, `revealBatch`, or `_reveal` in either contract.

---

## A4 — Gacha (`CauldronGachaRouter.openReady` + commit/readiness scheme)

**Purpose.** `openReady` opens already-earned lottery "crystals" (no fresh swap) at fair, on-chain-derived odds; the broader router (`play`/`playLiq`/`playChurn`) is how credit is earned in the first place by routing an ETH↔token swap through the pool.

**Entrypoints.**
- `CauldronGachaRouter.openReady(uint256 maxCount)` — `external nonReentrant`, no explicit authority modifier on the router itself (`CauldronGachaRouter.sol:261`).
- Underlying authority actually enforced one hop down: `CauldronHook.commitCrystals` requires `isOpener[msg.sender]`, else `NotOpener` (`CauldronHook.sol:2121`). `isOpener` is set via `CauldronHook.setOpener(address who, bool allowed)`, gated `msg.sender == registry || msg.sender == owner()` (`CauldronHook.sol:2279-2283`) — i.e. the router only works once governance/registry has whitelisted it as an opener; that wiring call itself was not found inside the four files read for this area.

**Preconditions (`openReady`).** `ready = hook.crystalsReady(msg.sender)`, clamped to `MAX_MINTS_PER_CALL` (30) and to the caller's `maxCount` (`CauldronGachaRouter.sol:262-264`); if `ready == 0`, returns `0` with no state change (`:265`).

**Behavior.** `creditToOpen = hook.costOfNextCrystals(ready)` (`:267`); `bw = hook.buyWeightBps()`; `playWei = bw > 0 ? (creditToOpen * 10_000) / bw : creditToOpen` — converts the credit being spent back into an ETH-notional "play size" for the odds curve (`:268-269`). This value is **deliberately not** passed through `_playInCurveUnits` (the router's oracle-conversion helper) — comment at `:271-275` explains it is "ALREADY in curve units" because it derives from the hook's own `costOfNextCrystals`. `opened = hook.commitCrystals(msg.sender, ready, playWei)` enqueues lottery tickets (`:276`); `hook.resolveTickets(MAX_MINTS_PER_CALL)` immediately resolves matured tickets (`:277`); emits `Played(msg.sender, playWei, opened)` (`:278`).

**Commit/readiness scheme (`CauldronHook.sol`).**
- `commitCrystals(player, maxCount, playWei)` (`:2116-2131`) → `_commitCrystals` (`:2136-2185`): computes `room = maxSupply - totalMinted - outstandingOf[collection]` (`:2144-2148`, returns `0` — never reverts — if sold out); walks `nftPriceAt(startPos + n)` spending `nftCredit[epoch][player]` until it can't afford the next slot or hits `MAX_MINTS_PER_CALL` (`:2153-2162`); pushes one `Batch{player, collection, commitBlock: block.number, oddsBps, count: n, resolved: 0}` (`:2176-2183`). **Nothing mints at commit time** (comment `:2111`).
- `resolveTickets(maxCount)` (`:2196-2202`) → `_resolveTickets` (`:2208-2262`): FIFO over `batches[batchCursor..]`; stops (no revert) at a batch committed this block (seed not yet known, `:2216`); on an expired seed (`blockhash == 0`) re-anchors `commitBlock` to now and breaks, matching `reveal()`'s M-03 pattern (`:2225-2228`); per ticket, `roll = keccak256(bh, player, batchIndex, ticketIndex) % 10_000` (`:2239`); win if `(forced-by-pity || roll < oddsBps) && minted < max` (`:2240-2241`) — **a sold-out collection always resolves remaining tickets as misses**, regardless of roll (comment `:2193`); a win calls `ICauldronCollection(col).mint(player)` (`:2249`, this is the entrypoint from A2(b)); a genuine miss increments `missStreak[player]` unless sold out (`:2253`).
- `pityThreshold` (default `8`, `CauldronHook.sol:417`) forces a win after that many consecutive misses (`:2240`), reset to `0` on any win (`:2247`).

**Postconditions & invariants.** `nftCredit[epoch][player]` decreases by exactly the sum of spent curve prices. `outstandingOf[collection]`/`outstandingCrystals`/`pendingOf`/`committedOf` are incremented at commit and decremented at resolve — bounding total possibly-winning tickets against remaining supply so resolution can never mint past `maxSupply` (comment `:2144-2145`).

**Edge cases.** `openReady` with `ready == 0` is a pure no-op returning `0`. `resolveTickets` never reverts; it simply stops early at an unresolved seed and resumes on a later call (FIFO cursor `batchCursor`).

**Events.** `Played(indexed player, playWei, opened)` `CauldronGachaRouter.sol:151`. `CrystalsCommitted(indexed player, count, oddsBps)` declared `CauldronHook.sol:513`, emitted `:2184`. `TicketWon`/`TicketLost` declared `CauldronHook.sol:514-515`. `OpenerSet(indexed who, allowed)` declared `CauldronHook.sol:516`, emitted `:2282`.

**DENOMINATION: partially — see evidence below.**
- `openReady` itself: **quote-agnostic** — non-`payable`, moves no `msg.value`, only spends already-tracked credit.
- The credit-earning legs (`play`, `playLiq`, `playChurn`) that feed `openReady`: **ETH-only**, and this is a real intent/actual gap. `CauldronGachaRouter._key()` hardcodes `currency0: Currency.wrap(address(0))` (`CauldronGachaRouter.sol:171-178`), and the file's own header comment asserts this as a protocol-wide truth: "ETH is always currency0 (address(0) sorts first)" (`:49-50`). That is **not** actually true of the protocol: `CauldronHook.sol:207-208` / `:263-264` / `:385-386` / `:843-844` construct every real pool key as `currency0: Currency.wrap(quote)` where `quote` is the generation's **rotatable** `generationQuote[gen]`, and `CauldronRegistry.sol:271-287` (`setAllowedQuote`) plus `:877-878,897,918,951` (`relaunch`) show `quote` can be any treasury-allowlisted, non-ETH asset (the only structural invariant is that the quote sorts *below* the token by address, `CauldronRegistry.sol:279-283` — not that it is literally `address(0)`). `play`/`playLiq`/`playChurn` are all `payable`, read `msg.value` as the buy leg (`CauldronGachaRouter.sol:223,290,335` region), and settle exclusively via `poolManager.settle{value: amount}()` (`:418`). For a generation whose quote has rotated away from native ETH, this router either targets a pool that does not exist at that key, or a stale/foreign one — see `## Open deltas`, D1. By contrast, the hook's **native in-swap** gacha path (`CauldronHook.nativeGachaStep`, `CauldronHook.sol:2270-2274`) is quote-agnostic, since it is invoked from `afterSwap` using whatever the pool's actual (rotatable) key is.

---

## A5 — Liquidatoor badges (`mintLiquidator`, `mintLiquidatorWithStats`, `LIQUIDATOR_ID_BASE`)

**Purpose.** Strike an uncapped, always-revealed trophy NFT to whoever is credited with a perp liquidation, in a token-id namespace fully separate from the art tranche.

**Entrypoints & authority.**
- `mintLiquidator(address to)` `MiFrensGenesis.sol:365` / `CauldronCollection.sol:336`, and `mintLiquidatorWithStats(address to, LiqStats calldata st)` `MiFrensGenesis.sol:370` / `CauldronCollection.sol:342` — both funnel into `_mintLiquidator`, gated `if (msg.sender != liquidatorMinter) revert OnlyLiquidatorMinter();` (`MiFrensGenesis.sol:378` / `CauldronCollection.sol:350`).
- Who may **set** `liquidatorMinter`: `MiFrensGenesis.setLiquidatorMinter` — deployer, registry, **or** the wired volume `minter` (`MiFrensGenesis.sol:351-354`). `CauldronCollection.setLiquidatorMinter` — the `deployer` (= registry) **or** `minter` (`CauldronCollection.sol:306-309`).
- **Actual wiring chain:** `CauldronHook._wireLiquidator(_collection)` — `if (_collection == address(0) || perpEngine == address(0)) return; try ICollectionLiquidator(_collection).setLiquidatorMinter(perpEngine) {} catch {}` (`CauldronHook.sol:1900-1903`) — best-effort, `try/catch`, never bricks a summon. Called from `setCollection` (`:1889`, every summon/relaunch) and `setPerpEngine` (`:1934`, whenever the engine changes). So in practice `liquidatorMinter` always ends up being the currently-wired `PerpEngine`, re-wired automatically — no manual admin step is needed each relaunch.

**Preconditions.** Only `msg.sender == liquidatorMinter` may mint (both contracts, cited above); no other precondition (no supply cap check — see below).

**Behavior.** `tokenId = LIQUIDATOR_ID_BASE + (++liquidatorMinted)` — a monotonic, uncapped counter (`MiFrensGenesis.sol:379` / `CauldronCollection.sol:351`). `isLiquidatoor[tokenId] = true` (`:380`/`:352`). Stats are only written if non-empty: `if (st.victim != address(0)) _liqStats[tokenId] = st;` (`:382`/`:355`) — "only pay for the write when there is something to record." `_mint(to, tokenId)`, emits `LiquidatoorMinted(to, tokenId)` (`:384-385`/`:357-358`).

**tokenId namespace split.** `LIQUIDATOR_ID_BASE = 1_000_000` (constant, `MiFrensGenesis.sol:181` / `CauldronCollection.sol:74`). Collision-safety is enforced structurally, not just by convention: both constructors reject `maxSupply_ >= LIQUIDATOR_ID_BASE` (`MiFrensGenesis.sol:239` / `CauldronCollection.sol:148`), so the art tranche (`1..maxSupply`) can never reach the badge range. `isGenesis(tokenId)` is derived purely as `tokenId != 0 && tokenId <= GENESIS_SUPPLY` (`MiFrensGenesis.sol:610-612`) — a badge id (`>= 1,000,001`) is structurally never Genesis, and per comment (`:178-180`) "never draws the genesis fee dividend."

**Postconditions & invariants.** `liquidatorMinted` strictly increases by 1 per mint; badge ids never repeat and never collide with art ids by construction.

**Edge cases.** Badge minting is **uncapped** — there is no `maxLiquidator` check anywhere in either `_mintLiquidator`, unlike the art tranche's `MintedOut` guard (A2). A stats-free `mintLiquidator` leaves `_liqStats[tokenId]` as the zero struct; `liqStats(tokenId)` (`MiFrensGenesis.sol:388-390` / `CauldronCollection.sol:360-363`) returns that zero struct rather than reverting.

**Metadata.** `tokenURI` special-cases `isLiquidatoor[tokenId]`: uses `liquidatorRenderer` if set, else `string.concat(liquidatorURI, tokenId.toString())` (`MiFrensGenesis.sol:623-629` / `CauldronCollection.sol:402-409`). The renderer is wired once, at collection creation, by `CauldronFactory.deployBrew` (`CauldronFactory.sol:86-88`) because both the hook and registry are near the EIP-170 size ceiling (`CauldronFactory.sol:26-31`).

**Events.** `LiquidatoorMinted(indexed to, indexed tokenId)` `MiFrensGenesis.sol:206` / `CauldronCollection.sol:96`.

**DENOMINATION: partially — see evidence below.**
- The mint calls themselves are **quote-agnostic**: `mintLiquidator`/`mintLiquidatorWithStats` are non-`payable`, no `msg.value` anywhere in either `_mintLiquidator`.
- The **stats payload they carry is ETH/wei-hardcoded**: `LiqStats.collateralWei`/`bountyWei` are documented "ETH they had staked"/"ETH paid to the liquidator" and `entryPrice`/`liqPrice` "ETH per token (wei)" (`ILiquidatorMintable.sol:23-27`). `render/LiquidatoorRenderer.sol` renders these via `_gwei(uint256 wei_)` (divides by `1e9`, `LiquidatoorRenderer.sol:283-291`, comment `:280-282`: "Token prices here are ~1e-9 ETH...gwei is also the unit the app quotes prices in") and `_eth(uint256 wei_)` (divides by `1e18`, `:296-298`) — both assume 18-decimal, ETH-denominated magnitudes with no reference to what asset the `PerpEngine` actually collateralizes/quotes in. If a perp position's collateral or mark price is ever denominated in a 6-decimal USDG or a differently-scaled synthetic rather than native ETH, these struct fields and the renderer's fixed divisors would misrepresent the recorded magnitude (e.g. a 6-decimal amount divided by `1e9`/`1e18` renders as near-zero). Neither `ILiquidatorMintable.sol` nor `LiquidatoorRenderer.sol` reference a quote asset, a decimals parameter, or an oracle.

---

## Open deltas

- **D1 — Gacha router hardcodes native ETH as the pool's quote leg, contradicting the protocol's actual rotatable-quote pool construction.** `CauldronGachaRouter._key()` sets `currency0: Currency.wrap(address(0))` unconditionally (`CauldronGachaRouter.sol:171-178`), and the file's header comment asserts "ETH is always currency0" as a protocol truth (`CauldronGachaRouter.sol:49-50`) — but `CauldronHook.sol:207-208` (mirrored at `:263-264`, `:385-386`, `:843-844`) constructs the real pool key as `currency0: Currency.wrap(quote)` where `quote = generationQuote[gen]`, and `CauldronRegistry.sol:271-287` / `CauldronRegistry.sol:877-878,897,918,951` show that quote is proposer-chosen and rotatable to any treasury-allowlisted, non-ETH asset. `play`/`playLiq`/`playChurn` remain `payable`-and-`msg.value`-only (`CauldronGachaRouter.sol:223`, `:335`, settle at `:418`), so on any generation whose quote has rotated off native ETH, the router either misses the real pool or hits a stale one.

- **D2 — `_reveal`'s ownership guard reverts the same error name (`OnlyMinter`) used elsewhere for a different meaning.** `MiFrensGenesis.sol:516` / `CauldronCollection.sol:248` revert `OnlyMinter` when `ownerOf(tokenId) != msg.sender` (a reveal-caller-must-own-the-token check), while the *same* error name is used at `MiFrensGenesis.sol:475` / `CauldronCollection.sol:208` to mean "caller is not the wired volume-minter hook." Purely a naming/documentation mismatch (not judged as a security issue here) — a revert trace or off-chain error-message table keyed on error name cannot distinguish the two causes.

- **D3 — Undocumented governance-weight asymmetry between the two badge-minting contracts.** `MiFrensGenesis` is `ERC721Votes` (`MiFrensGenesis.sol:48`) with `_update`/`_increaseBalance` applying uniformly to every token id including badges (`:647-712`), and its own comment states a badge "carries ONE governance vote, exactly like a volume-minted MiFren" (`:176-178`). `CauldronCollection` is plain `ERC721` with no Votes extension anywhere in its import list or inheritance (`CauldronCollection.sol:4-9,24`) — badges minted there carry no governance weight at all. Neither contract's badge-specific NatSpec (`mintLiquidator`/`mintLiquidatorWithStats`/`ILiquidatorMintable.sol`) states this asymmetry.

- **D4 — `LiqStats` fields and their renderer hardcode ETH/wei, with no link to the perp engine's actual quote asset.** `ILiquidatorMintable.sol:23-27` types/names `collateralWei`, `bountyWei`, `entryPrice`, `liqPrice` as ETH-denominated wei quantities; `render/LiquidatoorRenderer.sol:283-298` (`_gwei`, `_eth`) divides these by fixed `1e9`/`1e18` with no decimals parameter or oracle reference. This is inconsistent with the treasury's documented any-quote generality (`CauldronRegistry.sol:271-287`, `setAllowedQuote`) that the rest of this spec's DENOMINATION SPINE was asked to verify against.

- **D5 — Scope caveat on the "any treasury-approved quote" claim for genesis.** `MiFrensGenesis.mint(uint256)` (A1, `MiFrensGenesis.sol:262-284`) and `CauldronRegistry.summon()` (`CauldronRegistry.sol:649-660`, "This is the ONLY function that requires external ETH") are unconditionally ETH-only. This is INTENTIONAL and documented — `CauldronRegistry.sol:675-677` states the any-quote system applies from generation 2 onward, since generation 1 "launches from the presale before any proposal exists to name a quote" — but it means a blanket claim that "every feature works with any treasury-approved LP quote" does not hold for A1/A2(a) without this generation-1 carve-out being stated alongside it.
