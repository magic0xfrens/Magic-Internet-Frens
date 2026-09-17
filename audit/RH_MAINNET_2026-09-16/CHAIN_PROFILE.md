# Robinhood Chain (4663) — Pre-Deployment Chain Profile

**Phase P0.5 — characterization only. No attacks run.** All probes are read-only public JSON-RPC and public docs.
Measured 2026-09-15, heads ~63,917,000–63,924,000. Every line is tagged VERIFIED / DERIVED / UNKNOWN.

## THE CHAIN-ID ANSWER (unambiguous — this is load-bearing for a Critical elsewhere)

**Robinhood Chain mainnet is chain id `4663`. This is VERIFIED, not inferred.**

- `cast chain-id --rpc-url https://rpc.mainnet.chain.robinhood.com` → **`4663`**, answered by a live
  `nitro/v3.11.4-rc.3` node at head ~63.9 M. The chain is up and I transacted reads against it throughout this profile.
- On-chain self-report: `ArbSys.arbChainID()` (precompile `0x…064`) → **`4663`**.
- Canonical registry `ethereum-lists/chains` `eip155-4663.json` → `"chainId": 4663, "networkId": 4663`, name
  "Robinhood Chain".

**`46646` is NOT a chain id at all** — `eip155-46646.json` returns `404: Not Found`. It is a typo that propagated
through our docs. The **testnet is `46630`** (`https://rpc.testnet.chain.robinhood.com`, per Robinhood's own docs —
DERIVED, not probed by me). So the `docs/protocol/09-FRONTEND.md:46` ambiguity *"4663 for mainnet and 46646 for
testnet"* is resolved: **the mainnet half was right, the testnet half was wrong, and neither needed to stay open.**

**Bearing on the frontend Critical.** Another agent verified that `src/config/deployments.ts` hard-codes only
`{11155111, 5042002}`, so a Robinhood manifest loads under the Sepolia key. My independent read of
`src/config/chains.ts:29-36` (§0c) is the other half of that same defect and confirms it:
`CHAIN_ID = SELECTED_CHAIN_ID !== sepolia.id ? SELECTED_CHAIN_ID : ENV_CHAIN_ID` — `SELECTED_CHAIN_ID` comes from
`deployments.ts`, and `ENV_CHAIN_ID` falls back to **5042002 (Arc)**, never to 4663. **There is no value of any env var
documented in `11-OPERATIONS.md` that makes this frontend target 4663.** The correct id to add is **4663** — that
number is now settled and the fix should not wait on further chain research.

> **Tooling note (affects reproducibility):** the machine's `curl` (LibreSSL 3.3.6) and `python3` (broken CA store —
> `https://example.com` also fails `CERTIFICATE_VERIFY_FAILED`) are unreliable TLS clients here. `cast` (Foundry
> 1.4.4-nightly) and `curl` against non-Cloudflare hosts worked. Distinguish carefully between a *local* CA failure
> and a *server-side* `handshake_failure` — that distinction is what produced Finding 1 below.

---

## Summary table

| # | Area | Verdict | Status |
|---|---|---|---|
| 0 | **Our own docs** | **3 of 4 repo claims are WRONG** (RPC host, testnet id, env var name) | **VERIFIED** |
| 1 | Identity & liveness | chainId **4663** = mainnet. Nitro `v3.11.4-rc.3`, ArbOS 116. Block time **~0.10 s** | VERIFIED |
| 2 | Native currency | **ETH, 18 decimals** | VERIFIED (registry) + DERIVED (wei-scale balance) |
| 3 | Finality & reorgs | Single Robinhood sequencer. 0 reorgs seen. `finalized` lags head **~9,648 blocks (~16 min)** | VERIFIED |
| 4 | Mempool & ordering | **Pending user swaps ARE publicly readable.** No priority-fee auction (`maxPriorityFeePerGas = 0`) | VERIFIED |
| 5 | Uniswap v4 | All 6 addresses in our docs **confirmed on-chain and cross-wired**. v2 + v3 + v4 all live | VERIFIED |
| 6 | Flashloans | **Uniswap v4 PoolManager holds 21,218.79 ETH** — flash-accounting source, live today | VERIFIED |
| 7 | Bridges & capital | Canonical Arbitrum bridge. ~$2.5 B bridged / ~$738 M TVL (reported, not probed) | DERIVED / UNKNOWN |
| 8 | RPC providers | **2 usable independent endpoints**, agreeing. **No public archive anywhere** | VERIFIED |

---

## 0. Our own docs are wrong — report this first

### Finding 0a — the RPC host in `docs/MAINNET_LAUNCH.md:10` does not exist (CRITICAL for deploy)

`docs/MAINNET_LAUNCH.md:10` says, under a heading literally titled **"Robinhood Chain params (confirmed)"**:

> `chainId **4663**, RPC `https://rpc.chain.robinhood.com``

That host resolves but **refuses TLS**. Three independent TLS stacks, same server-side alert:

```
$ host rpc.chain.robinhood.com
rpc.chain.robinhood.com has address 18.67.250.97   (+ .56 .31 .95 — AWS CloudFront)

$ curl -v https://rpc.chain.robinhood.com          # LibreSSL 3.3.6
* Connected to rpc.chain.robinhood.com (18.67.250.95) port 443
* LibreSSL/3.3.6: error:1404B410:SSL routines:ST_CONNECT:sslv3 alert handshake failure

$ cast chain-id --rpc-url https://rpc.chain.robinhood.com     # rustls
Error: error sending request for url (https://rpc.chain.robinhood.com/)

$ python3 urllib ...                                          # OpenSSL 3.6.4
ERR: URLError [SSL: SSLV3_ALERT_HANDSHAKE_FAILURE] sslv3 alert handshake failure
```

`handshake_failure` with SNI set on a CloudFront edge = **no distribution serves that hostname**. Contrast with a host
that *does* serve TLS, where the same broken-CA python fails differently (`CERTIFICATE_VERIFY_FAILED`, i.e. a cert
*was* presented). The correct endpoint, which answers immediately:

```
$ cast chain-id  --rpc-url https://rpc.mainnet.chain.robinhood.com   -> 4663
$ cast client    --rpc-url https://rpc.mainnet.chain.robinhood.com
nitro/v3.11.4-rc.3-7d5ac27/linux-arm64/go1.25.14
```
**VERIFIED.** Corroborated by the canonical registry (§1) and by Robinhood's own support docs. **Fix `docs/MAINNET_LAUNCH.md:10`
and `VITE_CHAIN_RPC_URL` before deploy — the documented host cannot be connected to at all.**

### Finding 0b — "46646 for testnet" is wrong; the real testnet is 46630 (and the 4663 ambiguity is RESOLVED)

`docs/protocol/09-FRONTEND.md:46` and `:325` record an unresolved ambiguity: *"sources have shown 4663 for mainnet and
46646 for testnet"*, *"Not verified: the correct Robinhood Chain id (4663 vs 46646)"*.

```
$ curl .../ethereum-lists/chains/master/_data/chains/eip155-4663.json
{ "name": "Robinhood Chain", "chain": "ETH",
  "rpc": ["https://rpc.mainnet.chain.robinhood.com", "https://robinhood-rpc.publicnode.com", ...],
  "nativeCurrency": { "name": "Ether", "symbol": "ETH", "decimals": 18 },
  "shortName": "robinhoodchain", "chainId": 4663, "networkId": 4663,
  "infoURL": "https://docs.robinhood.com/chain" }

$ curl .../eip155-46646.json
404: Not Found
```
**VERIFIED: 4663 is mainnet.** **46646 is not a registered chain id at all** — it appears to be a typo that propagated
through our docs. Robinhood's own documentation gives testnet as **46630** / `https://rpc.testnet.chain.robinhood.com`
(DERIVED — from Robinhood support + docs.robinhood.com via search, not probed by me). 4663 also spells "HOOD" on a keypad.

### Finding 0c — `docs/protocol/11-OPERATIONS.md:25` documents an env var the code no longer reads

The brief and `11-OPERATIONS.md:25` both say `VITE_ROBINHOOD_CHAIN_ID` falls back to 4663. The code says otherwise
(`src/config/chains.ts:29-36`, read directly):

```js
const RAW_CHAIN_ID = Number(import.meta.env.VITE_CHAIN_ID);
//  Default 5042002 (Arc testnet) because that is where the second deployment actually lives
const ENV_CHAIN_ID = Number.isSafeInteger(RAW_CHAIN_ID) && RAW_CHAIN_ID > 0 ? RAW_CHAIN_ID : 5042002;
const CHAIN_ID = SELECTED_CHAIN_ID !== sepolia.id ? SELECTED_CHAIN_ID : ENV_CHAIN_ID;
```

The variable is **`VITE_CHAIN_ID`**, and the fallback is **5042002 (Arc testnet)**, not 4663. An operator who follows
`11-OPERATIONS.md` verbatim sets a variable nothing reads and ships a frontend silently pointed at **Arc**.
**VERIFIED** for the code text quoted above (file read directly; `grep -rn 46646` over the repo returns only the two
doc lines plus a stale comment at `chains.ts:73`). *Residual check for the fixer: confirm `VITE_ROBINHOOD_CHAIN_ID`
/`_RPC_URL`/`_EXPLORER` appear nowhere in `src/` before rewriting the ops doc.*

**Also good news:** `chains.ts:17-22` already carries an explicit warning that native decimals must not be assumed 18
and are validated rather than trusted. That design choice is correct and is vindicated below — though for 4663 the
answer happens to be 18.

---

## 1. Identity & liveness — VERIFIED

```
$ R=https://rpc.mainnet.chain.robinhood.com
$ cast chain-id      --rpc-url $R        -> 4663
$ cast client        --rpc-url $R        -> nitro/v3.11.4-rc.3-7d5ac27/linux-arm64/go1.25.14
$ cast block-number  --rpc-url $R        -> 63917542
$ cast gas-price     --rpc-url $R        -> 68378000        (0.0684 gwei)
$ cast call 0x...064 "arbOSVersion()(uint256)"  -> 116       (ArbSys precompile)
$ cast call 0x...064 "arbChainID()(uint256)"    -> 4663
```

Head block header:
```
number         63917542
hash           0x9f3ec964ab494b2f6e5f6c71bc0cc11cbd906f6a6edc51197f62a45751284d35
parentHash     0x2a747f23209bec32b11fc9a0b091ea870637b131f60f16def45e3412354a31de
timestamp      1789502094 (Tue, 15 Sep 2026 19:54:54 +0000)
miner          0xA4b000000000000000000073657175656e636572     <- ASCII "sequencer"
gasLimit       1125899906842624        gasUsed 1776014       baseFeePerGas 67554000
```

**Block time — measured, two spans:**
| span | Δt | per block |
|---|---|---|
| head vs head−50 | 5 s | **0.100 s** |
| head vs head−5000 | 515 s | **0.103 s** |

**VERIFIED: ~100 ms blocks** (~600 blocks/min, ~864,000/day). The `miner` field is the Arbitrum canonical sequencer
address — a single sequencer, not a validator set. **DERIVED: 46646 is not a live chain** (not in the registry, 404).

## 2. Native currency — ETH, 18 decimals — VERIFIED

- Registry `eip155-4663.json` (fetched, §0b): `"nativeCurrency": {"name":"Ether","symbol":"ETH","decimals":18}` — **VERIFIED**.
- **DERIVED cross-check by magnitude** — the strongest empirical evidence I have:
  `cast balance 0x8366a39c…40951` (v4 PoolManager) = `21218792358543988970098` wei = **21,218.79 ETH**. If the native
  were 6-decimal, that same integer would denote 2.1 × 10^16 units — an absurd figure for one contract. The wei-scale
  is self-consistent with 18.
- `ArbGasInfo.getPricesInWei()` → `[0, 0, 1377680000000, 20000000, 48884000, 68884000]`; the total (6.888e7 wei
  ≈ 0.069 gwei) matches `eth_gasPrice` 68378000 independently — **VERIFIED**, consistent with wei/18.
- Arbitrum Orbit normalizes the native unit to 18 decimals at the L2 level regardless of the L1 gas token, and this
  chain uses plain ETH — **DERIVED**.

**This is NOT the Arc situation.** Arc's USD-denominated gas token broke volume recording (recorded as zero); 4663 is
ordinary 18-decimal ETH and that failure mode does not apply. **UNKNOWN (minor):** I did not probe WETH. Robinhood's
docs list WETH at `0x7943e237c7F95DA44E0301572D358911207852Fa` (DERIVED, unprobed) — one `cast call
0x7943… "decimals()(uint8)"` would close it to VERIFIED.

## 3. Finality & reorgs — VERIFIED (no reorg observed)

**Architecture:** Arbitrum Orbit L2, **settles to Ethereum L1**, DA via EIP-4844 blobs, **sequencer operated by
Robinhood** (single, centralized; L2BEAT documents it as centralized). Mainnet launched 2026-07-01. *(DERIVED — from
Robinhood docs + ecosystem sources; the single-sequencer part is corroborated on-chain by the `miner` field, VERIFIED.)*

**Reorg poll — 45 rounds over ~2.5 min, tracking the hash at head−10:**
```
rounds=45  heights_tracked=43  hash_changes=0
first_seen = 63920777 : 0x31ed55580d35f4b53a8a70b67f2ce8272430bc35068cc556b0509825927e4b32
RECHECK  same height, end of run  : 0x31ed55580d35f4b53a8a70b67f2ce8272430bc35068cc556b0509825927e4b32   (identical)
```
**VERIFIED: zero reorgs at depth 10 across the observation window.** This is a *negative result over ~2.5 minutes* —
it does not prove reorgs cannot happen, only that none did.

**Finality tags (this is the number the indexer needs):**
```
latest    0x3cf6258 = 63922776
safe      0x3cf4abb = 63916731    ->  6,045 blocks behind  ~10.1 min
finalized 0x3cf3ca8 = 63913128    ->  9,648 blocks behind  ~16.1 min
```
**DERIVED — indexer guidance:** soft-confirmed head is stable in practice (a single sequencer with no competing
proposer has nothing to reorg *against*), but a sequencer failure or an L1 reorg of a batch can rewrite anything newer
than `finalized`. **Ponder should follow `latest` for latency but must treat ~9,650 blocks (~16 min) as the
theoretical max reorg depth**, and — given our Sepolia incident where a routine reorg took the read layer down for
~25 min — its block-hash-disagreement handler **must not be FATAL**. At 100 ms blocks, a 16-minute rollback is ~9,650
blocks, which is a far larger *block count* than any L1 runbook assumes even though it is a short wall-clock window.

## 4. Mempool & ordering — VERIFIED, and the answer is nuanced

**Standard mempool introspection is disabled:**
```
txpool_content                    -> -32601 method does not exist/is not available
txpool_status                     -> -32601 method does not exist/is not available
eth_newPendingTransactionFilter   -> -32601 method does not exist/is not available
parity_pendingTransactions        -> -32601 method does not exist/is not available
```

**But `eth_getBlockByNumber("pending", true)` returns FULL transaction objects, including real user swaps:**
```
pending# 63923914  total 5  system 1  REAL_USER 4
   from 0xa2a6f8d8…78a2  to 0x8876789976decbfcbbbe364623c63652db8c0904  sel 0x3593564c  value 0xa530664294945
   from 0x4cdcedd6…0aaf  to 0x8876789976decbfcbbbe364623c63652db8c0904  sel 0x3593564c  value 0x0
   from 0xcad97616…e850  to 0xfd03abca…b7f0  sel 0x260595cf
pending# 63923934  total 7  system 1  REAL_USER 6
```
`0x8876789976…0904` is the **Universal Router** and `0x3593564c` is `execute(bytes,bytes[],uint256)` — those are
**live, unconfirmed Uniswap swaps with full calldata, readable by anyone over the public RPC.** Tx count moves
(0x9 → 0xa → 0x18 → 5 → 7), so it is a live view, not a cached artifact. **VERIFIED.**

**Ordering:**
```
eth_maxPriorityFeePerGas -> 0x0
```
**VERIFIED: there is no priority-fee auction.** Arbitrum Nitro sequencers order **first-come-first-served by arrival at
the sequencer**; the `pending` block is the block the sequencer is *already assembling*, so the transactions visible in
it have **already been assigned their positions**.

**DERIVED — what this means for a sandwich (confidence: moderate-high on the mechanism, moderate on exploitability):**
- **Ordering cannot be *bought*.** Paying more gas buys you nothing; `maxPriorityFeePerGas` is 0 and Nitro ignores
  priority for ordering. A classic "outbid the victim" sandwich **does not work here**.
- **Ordering can be *raced*.** FCFS makes this a pure **latency** game. A searcher co-located with the sequencer can
  win the race to be first; a remote party over public HTTPS cannot reliably, because the whole opportunity window is
  one ~100 ms block and an HTTPS round-trip consumes a large fraction of it.
- **Back-running is clearly feasible.** You can read a pending swap and land your own tx in a subsequent block. That
  is enough for **arbitrage against our pool after a large trade**, and for **liquidation racing**.
- **Front-running a tx you have already seen in `pending` is NOT possible by fee**, and is possible by latency only if
  you beat it to the sequencer — i.e. only if you saw it somewhere *earlier* than the pending block.
- **The privacy assumption "nobody can see my pending swap on this chain" is FALSE.** Anything our protocol does that
  relies on a transaction's *contents* being unobservable before inclusion (commit-reveal shortcuts, gacha
  randomness derived from user-supplied data, un-slipped swaps) is exposed. **A later phase should write back-run and
  latency-race attacks, and should refute fee-based sandwiches specifically.**

**UNKNOWN:** whether Robinhood offers or tolerates a private-orderflow / MEV-protect lane, and the sequencer's exact
inclusion policy under load. What would close it: Robinhood Chain sequencer documentation, or a timing experiment
(out of scope for a read-only phase).

## 5. Uniswap v4 — VERIFIED, all six addresses correct and cross-wired

Official source fetched: `raw.githubusercontent.com/Uniswap/contracts/main/deployments/4663.md` (HTTP 200). Every
address in `docs/MAINNET_LAUNCH.md:16-22` matches that file **exactly**. On-chain probe (`cast code` length in hex chars):

| Contract | Address | code | `poolManager()` |
|---|---|---|---|
| **PoolManager** | `0x8366a39cc670b4001a1121b8f6a443a643e40951` | 48021 | — |
| PositionManager | `0x58daec3116aae6d93017baaea7749052e8a04fa7` | 47757 | `0x8366a39C…40951` ✓ |
| Permit2 | `0x000000000022d473030f116ddee9f6b43ac78ba3` | 18307 | — |
| UniversalRouter | `0x8876789976decbfcbbbe364623c63652db8c0904` | 49095 | — |
| StateView | `0xf3334192d15450cdd385c8b70e03f9a6bd9e673b` | 7065 | `0x8366a39C…40951` ✓ |
| V4Quoter | `0x8dc178efb8111bb0973dd9d722ebeff267c98f94` | 12239 | `0x8366a39C…40951` ✓ |

```
PoolManager.owner()                 -> 0x2BAD8182C09F50c8318d769245beA52C32Be46CD
PoolManager.extsload(slot 0)        -> 0x...0000002bad8182c09f50c8318d769245bea52c32be46cd   (owner in slot 0)
PoolManager.protocolFeeController() -> 0x6d0009504D129CF5002Dba61D9Ae8575AA79314c
```
`extsload(bytes32)` answering, and returning the owner in slot 0, is a **positive v4 PoolManager identification** —
`extsload` exists only on v4. **VERIFIED.**

**Routability — VERIFIED and good.** Beyond v4, chain 4663 has a full Uniswap stack deployed by Uniswap themselves:
Uniswap Interface Multicall, QuoterV2, TickLens, NFTDescriptor, NonfungiblePositionManager, SwapRouter02, **v2 Factory
+ Router02**, **v3 Factory**, Permit2, Calibur Entry, ERC7914 Detector, UniversalRouter. `cast code` confirms
v2Factory `0x8bceaa40…937f` (27720), v3Factory `0x89e5db8b…9eba` (43806), SwapRouter02 `0xcaf681a6…5cb2` (48996),
Multicall3 `0xcA11bde0…CA11` (7618) all have code.
```
UniV2Factory.allPairsLength() -> 42890
```
A live v2 with **42,890 pairs** plus a canonical UniversalRouter means our hooked pool is reachable by the standard
Uniswap frontend/API path. **A hook here is not dead on arrival.**

**UNKNOWN:** whether the deployed PoolManager bytecode matches our pinned `v4-core` commit
`46c6834698c48bc4a463a86d8420f4eb1d7f3b75` (Thu Apr 2 2026). Uniswap's `4663.md` records deployments on
**Wed May 27 / Fri May 22 / Tue May 26 2026** — *after* our pin, so a v4-core drift between April and May is possible.
What would close it: `forge build` our `v4-core` pin and diff the runtime bytecode against `cast code`, or read the
verified source on the explorer. **This is worth doing before deploy** — a PoolManager newer than our pin could have
changed hook-callback semantics.

## 6. Flashloan availability — a live source exists TODAY — VERIFIED

**The dominant, immediately-available flashloan source is Uniswap v4 itself:**
```
cast balance 0x8366a39cc670b4001a1121b8f6a443a643e40951
  -> 21218792358543988970098 wei = 21,218.79 ETH
```
v4's `unlock()` flash accounting lets any contract take the PoolManager's balance within one transaction and settle at
the end. **That is ~21,218 ETH of native flash-loanable capital, on-chain, right now, fee-free**, plus every ERC-20 the
PoolManager holds (not enumerated). Uniswap **v2 flash swaps** across 42,890 pairs are a second, independent source.
**VERIFIED.** *(Absence of a lending market is NOT safety — v4 alone is a larger flashloan than most Aave markets.)*

**Probed and NOT found:**
```
MorphoBlue vanity 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb -> NO CODE
Aave V3 Pool (mainnet addr) 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2 -> NO CODE
Balancer V2 Vault 0xBA12222222228d8Ba445958a75a0704d566BF2C8 -> has code (4220 hexchars, ~2.1 KB)
   but getProtocolFeesCollector() -> "ABI decoding failed: buffer overrun"
   => NOT the real Balancer Vault (the real one is ~25 KB). Do not treat as a flashloan source.
```

**Morpho — reported present, address UNKNOWN.** Multiple ecosystem sources report Morpho as the *dominant* lender on
4663 (~$260 M, ~44% of chain TVL; Robinhood Earn's ~7% USDG product routes into Morpho vaults) — but Morpho is **not**
at its cross-chain vanity address here, and I could not obtain a verified 4663 address. A "flashloan verified on 4663"
claim in a third-party GitHub toolkit is **unsubstantiated** (no `deployments.json`, no addresses, no tx hashes —
tests use mock routers). **Morpho flash loans are zero-fee and can draw the contract's entire token balance**, so if
Morpho *is* deployed, it is a very large additional source. What would close it: `docs.morpho.org` contracts page for
chain 4663, or an explorer search.

**What changes the day we launch:** our own pool's liquidity becomes borrowable through v4 flash accounting, and every
number above is a floor that only grows. Any invariant of ours that assumes an attacker cannot muster N ETH within one
transaction is already false at **N ≤ 21,218**.

## 7. Bridges & real capital — DERIVED / partly UNKNOWN

- **Canonical Arbitrum bridge** is the primary route; deposits land in ~10 min. Third-party routes named by ecosystem
  sources: Stargate/LayerZero, Chainlink CCIP, Relay, Across, LiFi. **DERIVED** (docs/ecosystem, no address probed).
- **Reported chain totals:** DeFiLlama ~**$738.11 M** TVL (2026-09-01) with ~**$2.524 B** bridged; ATH ~$775 M
  (2026-08-06). Artemis (wider methodology incl. Morpho market size) $588.9 M vs DeFiLlama $307.9 M on the same July
  date — **methodologies differ by ~2x, so treat any single figure as soft**. **DERIVED, not probed.**
- **Largest observable holder: UNKNOWN.** Both explorer routes were blocked from this machine — Blockscout
  (`robinhoodchain.blockscout.com/api/v2/stats` and `/api/v2/addresses`) sits behind a **Cloudflare interstitial**
  ("Just a moment...") for `curl`, and returned **HTTP 403** to WebFetch. The largest balance I *did* measure directly
  is the **v4 PoolManager at 21,218.79 ETH**.
- **DERIVED whale bound for later phases:** a hostile actor can plausibly assemble **21,000+ ETH atomically** (flash,
  §6) and, given ~$2.5 B bridged, **capital is not the binding constraint on this chain**. Size attacks against the
  protocol's own liquidity, not against an assumed whale budget.

What would close the UNKNOWN: a browser session on `robinhoodchain.blockscout.com` (the chrome-devtools MCP would
clear the Cloudflare challenge), or `robinscan.io` / `hoodscan.co` / `stonkscan` rich lists, or the L1 Arbitrum bridge
escrow balance read from an Ethereum RPC.

## 8. RPC providers — VERIFIED — only two usable, and no archive anywhere

Registry lists five endpoints. Measured:

| Endpoint | chainId | head | hash @ 63,900,000 | archive @ block 1,000,000 |
|---|---|---|---|---|
| `https://rpc.mainnet.chain.robinhood.com` | 4663 | 63922805 | `0x8a3c1acd…e66a` | ✗ `-32000 metadata is not found` |
| `https://robinhood-rpc.publicnode.com` | 4663 | 63922839 | `0x8a3c1acd…e66a` ✓ **agrees** | ✗ HTTP 403 (paid tier) |
| `https://rpc.ordofi.network` | 4663 | 63922897 | ✗ `block 0x3cf0960 not found` | ✗ `-32000` |
| `https://rpc.arrowrpc.com` | — | — | returns **HTML**, not JSON-RPC | — |
| `wss://robinhood-rpc.publicnode.com` | not tested | | | |

- **VERIFIED: 2 independent endpoints (Robinhood official + PublicNode) agree exactly on the hash at a fixed height
  63,900,000.** That is a real, executable cross-check.
- **VERIFIED: `rpc.arrowrpc.com` is not a working RPC** — it serves HTML. Do not list it as a fallback.
- **VERIFIED: `rpc.ordofi.network` prunes** — it answers `eth_chainId`/`eth_blockNumber` but cannot serve a block only
  ~23,000 blocks (~40 min) old. Useless for indexer recovery; dangerous as a silent fallback.
- **VERIFIED: no public archive access on any free endpoint.** Every provider refused state at block 1,000,000.
  Commercial archive is advertised by QuickNode / Chainstack / SolidRPC / Alchemy (DERIVED, unpriced, untested).

**Impact on our indexer recovery runbook.** The runbook — *"find the provider whose block N+1 parent-hashes to N"* —
assumes several independent providers. Here there are effectively **two**, one of which (PublicNode) 403s on deep history
on the free tier. The runbook is **executable but fragile**, and it is **not executable at all for any block older than
each node's prune window**. Combined with 100 ms blocks (~864,000 blocks/day), a node's retained history is a *very*
short wall-clock window. **Backfill from genesis will require a paid archive provider — budget for it.**

---

## Deploy risks from unknowns

| # | Risk | Severity | What would close it |
|---|---|---|---|
| R1 | `docs/MAINNET_LAUNCH.md:10` RPC host **does not serve TLS**; a deploy script using it fails, or worse, an operator "fixes" it by guessing | **Blocking** | Replace with `https://rpc.mainnet.chain.robinhood.com` (already VERIFIED); re-run the deploy script end-to-end |
| R2 | `11-OPERATIONS.md` documents `VITE_ROBINHOOD_CHAIN_ID`; code reads `VITE_CHAIN_ID` and **defaults to Arc 5042002** — frontend silently points at the wrong chain | **Blocking** | Rewrite the ops table from `src/config/chains.ts`; add a startup assertion that the connected chainId == 4663 |
| R3 | Deployed PoolManager (May 2026) may be **newer than our pinned v4-core** (Apr 2 2026, `46c6834…`); hook callback semantics could differ | **High** | Diff `cast code 0x8366a39c…` against a local build of the pin, or read verified source on the explorer |
| R4 | `finalized` lags head by **~9,650 blocks**; Ponder's FATAL-on-hash-disagreement will hard-stop on any sequencer rollback | **High** | Make the handler retry-with-backoff, not FATAL; set the reorg window to ≥9,650 blocks |
| R5 | Only **2 working public RPCs**, **no free archive**, one silent pruner in the registry | **High** | Buy an archive endpoint before backfill; remove arrowrpc/ordofi from any fallback list |
| R6 | Largest holder / rich list **not observable** from this machine | Medium | Browser session on Blockscout (chrome-devtools MCP) or an alternate explorer |
| R7 | **Morpho's 4663 address unverified** — potentially a large additional zero-fee flashloan source we have not sized | Medium | Morpho docs contracts page for 4663; then `cast code` it |
| R8 | Private-orderflow / MEV-protect lane, and sequencer behaviour under load, **undocumented** | Medium | Robinhood sequencer docs; timing experiment (not a read-only phase) |
| R9 | WETH decimals **not probed** (`0x7943e237…52Fa` per Robinhood docs) | Low | One `cast call … "decimals()(uint8)"` |
| R10 | Reorg observation is only **~2.5 min of negative evidence** | Low | Longer passive monitor during the pre-deploy window |

---

## What a hunter must assume — paste verbatim into later phases

**(a) Is ordering purchasable? NO — but it is raceable, and pending swaps are public.**
- `eth_maxPriorityFeePerGas` returns `0`. Arbitrum Nitro orders **FCFS by arrival at a single Robinhood-run
  sequencer**. **You cannot outbid anyone into an earlier slot. Do not write fee-based sandwich attacks — they are
  refuted on this chain.**
- **BUT:** `eth_getBlockByNumber("pending", true)` returns **full tx objects with calldata**, including live
  UniversalRouter (`0x3593564c`) swaps. Assume **zero pre-inclusion privacy**.
- **Write these instead:** back-running / post-trade arbitrage, liquidation racing, latency races to the sequencer, and
  any attack that only needs to *read* a victim's unconfirmed calldata. Assume a co-located adversary can win a 100 ms
  FCFS race; assume a remote one usually cannot.
- Blocks are **~100 ms**. An attack needing N sequential blocks costs N × 0.1 s, not N × 12 s — multi-block attacks
  that are impractical on L1 are cheap here.

**(b) Is flashloan capital available, and how much? YES — ~21,218 ETH today, fee-free.**
- Uniswap **v4 PoolManager `0x8366a39cc670b4001a1121b8f6a443a643e40951` holds 21,218.79 ETH**, borrowable within one
  transaction via `unlock()` flash accounting, plus its unenumerated ERC-20 balances.
- Uniswap **v2 flash swaps** across **42,890 pairs** are an independent source.
- Aave: **absent**. Balancer V2 Vault: **absent** (address has unrelated code). Morpho: **reported dominant lender
  (~$260 M) but address unverified — treat as probably available, zero-fee, whole-balance**.
- **Assume an attacker's atomic capital is effectively unbounded relative to our pool.** Never rely on "nobody has that
  much ETH."

**(c) Native decimals: 18. Symbol ETH. Real ETH, bridged via the canonical Arbitrum bridge.**
- **The Arc failure mode (non-18 gas token → volume recorded as zero) does not apply to 4663.**
- Still read decimals from config rather than hardcoding — `chains.ts` already validates this and should keep doing so.

**(d) Reorg depth to assume: up to ~9,650 blocks (~16 minutes).**
- `finalized` lags `latest` by **9,648 blocks**; `safe` by **6,045 blocks (~10 min)**.
- Zero reorgs observed at depth 10 over ~2.5 min — the single-sequencer design means routine reorgs are unlikely, but
  a sequencer failure or an L1 batch reorg can rewrite anything newer than `finalized`.
- **Indexers must not treat a block-hash disagreement as fatal.** Anything economically irreversible should wait for
  `finalized`, not `latest`.

**(e) Bonus assumptions.**
- The chain is **centralized**: one Robinhood sequencer. Liveness/censorship is a trust assumption, not a market one.
  Arbitrum's L1 force-inclusion escape hatch presumably applies but was **not verified**.
- Chain is young (mainnet 2026-07-01) and carries **~$2.5 B bridged / ~$738 M TVL** — real money, thin tooling.
- **A documented ecosystem of lookalike RPCs, fake explorers and phishing sites exists around this chain.** Verify
  `eth_chainId == 4663` from any endpoint before trusting it. Our own docs already shipped one non-existent RPC host
  (Finding 0a) — that is exactly the class of mistake this warning is about.
