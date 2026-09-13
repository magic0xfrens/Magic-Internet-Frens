import { useEffect, useRef, useState } from "react";
import round from "../../indexer/deployments/round.json";

/**
 * Live swap pings straight from the chain, over a websocket.
 *
 * WHY. Everything on the page is driven by polling the indexer, so a trade shows
 * up on the NEXT poll — seconds after it landed, and only after Ponder has
 * indexed the block. The chart feels laggy for a reason that has nothing to do
 * with the chain being slow.
 *
 * A websocket subscription to the PoolManager's Swap topic fires the moment the
 * block is seen. This deliberately does NOT parse the swap or try to replace the
 * indexer as a data source: it returns a nonce that increments on every swap in
 * our pool, and the page uses that to refetch immediately instead of waiting out
 * its interval. The indexer stays the source of truth; this only removes the
 * wait.
 *
 * NOTE: a websocket feed is only useful if it carries the chain OUR pool is on.
 * A mainnet feed for some other network has nothing to say about our trades, however
 * live it looks. WS_URLS is therefore keyed BY CHAIN ID — a chain with no entry
 * simply falls back to interval polling, which is correct rather than broken. To
 * add a chain, add its id and endpoint below; no other change is needed.
 */
const WS_URLS: Record<number, string[]> = {
  11155111: [
    "wss://ethereum-sepolia-rpc.publicnode.com",
    "wss://sepolia.gateway.tenderly.co",
  ],
};

/**
 * Every on-chain moment worth announcing. All computed with `cast keccak` from
 * the contracts' own signatures — never copied from memory, because a wrong
 * topic fails SILENTLY: the subscription simply never fires and the feed looks
 * merely quiet.
 */
const T = {
  SWAP:       "0x40e9cecb9f5f1f1c5b9c97dec2917b7ee92e57ba5563708daca94dd84ad7112f",
  TICKET_WON: "0x815a28d7714bfb45656bbe3915784ef7dc362a81214c0fc345acd6f3d06008df",
  TICKET_LOST:"0x6d6a3ab4fc11e4c40e9e158bd734734c7fde55c273b4d4022a954393798939f6",
  COMMITTED:  "0x195520287a075821816e5be932675619f8d84ced71b19c60c3a5e32a6aa32cbd",
  OPENED_NFT: "0xb43df8a46d3a14f5ef33cd586c8526aa0ddf9441cede7bba37f10081e89a55ff",
  PERP_OPEN:  "0x451ba9f5da6c3cca354859f0ad9c9016fc1084c46fb82e11e64ab1778f79db36",
  PERP_CLOSE: "0x9bedef2f5157c2a58603b19345b17634f86cfcee701cffdb762a1b4d16ce5971",
  LIQUIDATED: "0xf4c6cbfcc96248be8ecbaf76de0fee34f71f2fadd9af537dd38c2657621930d6",
  BADGE:      "0xddd9ec74671af2df8ea4a7740b5c7fc4056acd0a803d23719360bea0c89d7e13",
  // Revealed(uint256 indexed tokenId, uint8 rarity) — emitted by the COLLECTION,
  // not the hook, so it needs the collection in the subscription below.
  REVEALED:   "0x4105048da870d53e5d1897a04b28ff7adcb26454cb905eddf8756d2677d3a7b2",
} as const;

/**
 * The LAUNCH SEEDER's steps.
 *
 * These are announced from the indexer (useSeedProgress), not decoded here — the
 * point of listing them is only to bump the nonce so that feed refetches on the
 * block instead of waiting out its interval.
 *
 * They need their own set because most of them are NOT swaps. A poke that places
 * liquidity emits `ModifyLiquidity`, and `BasePlaced`/`SeedComplete` emit nothing
 * tradeable at all — so without this, exactly the steps the launch page exists to
 * show were the ones that arrived late. A poke that ALSO runs a prime-buy tranche
 * does emit a Swap, which is why prime tranches already felt instant and plain
 * liquidity adds did not.
 */
const SEED_TOPICS: ReadonlySet<string> = new Set([
  "0x9b9d34c9805ae2709c69a9ccaf8ff13fe3b2167bdd9ce45d9f5ced93b6ac4196", // SeedStarted(uint256,uint256,uint256,uint64)
  "0x86466ded471dd23c877d652a7154dee80b1c736c369a5a813f2a13883c3b1cfb", // BasePlaced(uint256,uint128)
  "0x17720a756e6231101c16b3521fafc972de5b997ec65d082c5fc8f48ca84517f6", // Poked(uint256,uint256,int24)
  "0x08ef350cfdfd206357bb28d42ee3a5f807329713f0c4ac1d415b576cf86dc0d1", // SeedComplete(uint256)
  "0xec39f70e32c16a30591b6a3afbd12571aa7aa9d393f240eea0f05f551256b8b1", // PrimeBought(uint256,uint256,uint256,uint256,uint256)
]);

export type EventKind =
  //  `gacha-volume` is a ROLL-UP, not a chain event: N crystal spins collapsed
  //  into one row. Individual spin swaps are real buys, but rendering each one
  //  as "Bought $TOKEN" buried every organic trade under a wall of identical
  //  lines (see the feed before this: nine consecutive 0.0072 Ξ rows).
  | "buy" | "sell" | "gacha-volume" | "gacha-commit" | "gacha-win" | "gacha-miss"
  | "perp-open" | "perp-close" | "liquidation" | "badge" | "revealed";

/** A swap seen on the wire, decoded far enough to show instantly. */
let nextId = 1;

export interface LiveSwap {
  kind: EventKind;
  /** Who did it, when the event names them. */
  who?: string;
  /** Pre-formatted detail for the toast (count, leverage, pnl…). */
  detail?: string;
  /** Monotonic id so a list can key on it. */
  id: number;
  /** tx hash + log index — dedupes the same log across a reconnect. */
  key: string;
  /** true = someone BOUGHT the token (quote went in). */
  isBuy: boolean;
  /** Quote-side size, in wei. Approximate by design — see below. */
  quoteWei: bigint;
  /** Token-side size, in wei. */
  tokenWei: bigint;
  /** Quote per token, derived from the swap's own post-trade sqrtPriceX96 — so
   *  the chart can move on the tick the block lands, before the indexer has
   *  built the candle. */
  price: number;
  /** The swap's on-chain sender. A crystal spin is routed through the gacha
   *  router, so this is what distinguishes a roll from an organic trade. */
  sender?: string;
  /** Roll-up only: how many spins this row represents. */
  spins?: number;
  /** Roll-up only: quote-side volume those spins generated, in wei. */
  rollupWei?: bigint;
  /** Roll-up only: the share of it routed to the NFT floor, in wei. */
  floorWei?: bigint;
  /** Wall-clock ms the log was seen. */
  ts: number;
  txHash: string;
}

export function useLiveSwaps(livePoolId?: string): { nonce: number; connected: boolean; recent: LiveSwap[] } {
  const [nonce, setNonce] = useState(0);
  //  A ROLLING LIST, not a single `latest`. Exposing one value dropped events:
  //  React batches state updates, so several swaps arriving in the same tick
  //  collapsed into one and a busy pool showed a single toast. The gacha router
  //  fires a buy and a sell back to back, which is exactly that case.
  //  Holds 80, not the handful the toasts need: the activity drawer reads the
  //  same list as a scrollable history, so the cap is set by what is worth
  //  keeping in view rather than by what is currently on screen.
  const [recent, setRecent] = useState<LiveSwap[]>([]);
  const [connected, setConnected] = useState(false);
  const wsRef = useRef<WebSocket | null>(null);
  //  Held in a ref on purpose: the subscription effect runs once with [] deps,
  //  and re-running it on every pool-id change would drop and rebuild the socket
  //  mid-launch - exactly when the tape matters most.
  const livePoolRef = useRef<string | undefined>(livePoolId);
  livePoolRef.current = livePoolId;

  useEffect(() => {
    const urls = WS_URLS[round.chainId] ?? [];
    if (urls.length === 0) return;

    //  Read the CURRENT pool id at message time, not at subscribe time. The
    //  manifest's `poolIds` is baked in at build, and a pool id changes at every
    //  summon and every relaunch - so pinning to it meant the live tape filtered
    //  against the PREVIOUS generation's dead pool and silently showed nothing
    //  until the app was rebuilt. `livePoolId` comes from the indexer, which
    //  reads it off the registry, so it follows a rebirth on its own.
    const poolIds = livePoolRef.current
      ? [livePoolRef.current.toLowerCase()]
      : (round.poolIds ?? []).map((p: string) => p.toLowerCase());
    const pm = round.contracts.poolManager;
    let closed = false;
    let attempt = 0;
    let retry: ReturnType<typeof setTimeout> | undefined;

    const connect = () => {
      if (closed) return;
      // Rotate endpoints on reconnect: a single provider dropping us should not
      // silently end live updates for the session.
      const url = urls[attempt % urls.length];
      attempt += 1;

      let ws: WebSocket;
      try { ws = new WebSocket(url); } catch { return schedule(); }
      wsRef.current = ws;

      ws.onopen = () => {
        setConnected(true);
        //  Two subscriptions, because the interesting events live in different
        //  places: swaps come from the PoolManager, everything else (gacha,
        //  perps, liquidations) from our own hook and engine. Filtering by our
        //  addresses keeps unrelated v4 traffic off the socket.
        ws.send(JSON.stringify({
          jsonrpc: "2.0", id: 1, method: "eth_subscribe",
          params: ["logs", { address: pm, topics: [T.SWAP] }],
        }));
        //  The live COLLECTION is included so opening a crystal announces
        //  itself: Revealed is emitted by the collection, not the hook, so
        //  without it a reveal was the one action that happened silently.
        const ours = [
          round.contracts.hook,
          round.contracts.perpEngine,
          round.contracts.collection,
          // The launch seeder, so liquidity steps ping as fast as trades do.
          (round.contracts as Record<string, string>).seeder,
        ].filter(Boolean);
        if (ours.length > 0) {
          ws.send(JSON.stringify({
            jsonrpc: "2.0", id: 2, method: "eth_subscribe",
            params: ["logs", { address: ours }],
          }));
        }
      };

      ws.onmessage = (e) => {
        try {
          const m = JSON.parse(e.data as string);
          const log = m?.params?.result;
          if (!log?.topics) return;
          // topics[1] is the poolId. Filter here rather than in the
          // subscription: v4 emits every pool's swaps from one address, and
          // subscribing to all of them would wake the page on unrelated trades.
          const topic0 = String(log.topics[0] ?? "").toLowerCase();
          const raw = String(log.data ?? "").slice(2);
          const word = (n: number) => {
            const w = raw.slice(n * 64, (n + 1) * 64);
            return w.length === 64 ? BigInt("0x" + w) : 0n;
          };
          const signedWord = (n: number) => {
            const w = word(n);
            return w >= (1n << 255n) ? w - (1n << 256n) : w;
          };
          const addrTopic = (n: number) => "0x" + String(log.topics[n] ?? "").slice(-40);
          const eth = (v: bigint) => {
            const f = Number(v) / 1e18;
            return f < 0.0001 ? "<0.0001" : f.toFixed(4);
          };

          let kind: EventKind | null = null;
          let quoteWei = 0n, tokenWei = 0n, price = 0;
          let who: string | undefined;
          let detail: string | undefined;

          if (topic0 === T.SWAP) {
            // Only OUR pool: v4 emits every pool's swaps from one address.
            const pid = String(log.topics[1] ?? "").toLowerCase();
            //  NO KNOWN POOL = DROP. This used to be `poolIds.length > 0 &&
            //  ...`, so an empty list accepted EVERY v4 swap on the chain as if
            //  it were ours. That was unreachable while the manifest always
            //  carried an id; now that the id is empty until ignition, it would
            //  have filled the launch tape with strangers' trades.
            if (poolIds.length === 0 || !poolIds.includes(pid)) return;

            //  The event carries the SWAPPER's balance delta (PoolManager emits
            //  the same delta it accounts to msg.sender), so a NEGATIVE quote
            //  leg means they paid quote in — a buy.
            const q = signedWord(0);
            const t = signedWord(1);
            kind = q < 0n ? "buy" : "sell";
            quoteWei = q < 0n ? -q : q;
            tokenWei = t < 0n ? -t : t;
            // price = 1 / (sqrtP / 2^96)^2 — quote is currency0 by construction.
            const sqrtP = word(2);
            if (sqrtP > 0n) { const r = Number(sqrtP) / 2 ** 96; price = r > 0 ? 1 / (r * r) : 0; }
            detail = `${eth(quoteWei)} ${"" }`;
          } else if (topic0 === T.COMMITTED) {
            kind = "gacha-commit"; who = addrTopic(1);
            detail = `${word(0)} crystal${word(0) === 1n ? "" : "s"}`;
          } else if (topic0 === T.TICKET_WON) {
            kind = "gacha-win"; who = addrTopic(1);
            detail = `fren #${word(0)}`;
          } else if (topic0 === T.TICKET_LOST) {
            kind = "gacha-miss"; who = addrTopic(1);
          } else if (topic0 === T.OPENED_NFT) {
            kind = "gacha-commit"; who = addrTopic(1);
            detail = `${word(0)} forged`;
          } else if (topic0 === T.PERP_OPEN) {
            kind = "perp-open"; who = addrTopic(2);
            // (isLong, collateral, size, leverage)
            detail = `${signedWord(0) !== 0n ? "LONG" : "SHORT"} ${word(3)}x · ${eth(word(1))}`;
          } else if (topic0 === T.PERP_CLOSE) {
            kind = "perp-close"; who = addrTopic(2);
            const pnl = signedWord(1);
            detail = `${pnl >= 0n ? "+" : "-"}${eth(pnl < 0n ? -pnl : pnl)}`;
          } else if (topic0 === T.LIQUIDATED) {
            kind = "liquidation"; who = addrTopic(2);
            detail = `${eth(word(0))} penalty`;
          } else if (topic0 === T.REVEALED) {
            kind = "revealed";
            // rarity is the only data word; the tier names live in the UI.
            detail = `#${BigInt(String(log.topics[1] ?? "0x0"))}`;
          } else if (topic0 === T.BADGE) {
            kind = "badge"; who = addrTopic(2);
            detail = `badge #${word(0)}`;
          }
          // Seeding steps: no toast from here (useSeedProgress writes the copy
          // from indexed data), just wake the page so it refetches immediately.
          // Must come BEFORE the `kind` gate, which drops everything it cannot
          // decode into an EventKind.
          if (SEED_TOPICS.has(topic0)) { setNonce((n) => n + 1); return; }
          if (!kind) return;

          const hash = String(log.transactionHash ?? "");
          const key = `${hash}:${String(log.logIndex ?? "")}`;
          setRecent((prev) => {
            if (prev.some((x) => x.key === key)) return prev;
            return [{
              id: nextId++, key, kind, isBuy: kind === "buy",
              quoteWei, tokenWei, price, ts: Date.now(), txHash: hash, who, detail,
            }, ...prev].slice(0, 80);
          });
          setNonce((n) => n + 1);
        } catch { /* malformed frame — ignore */ }
      };

      ws.onerror = () => { setConnected(false); };
      ws.onclose = () => { setConnected(false); schedule(); };
    };

    // Backoff caps at 30s so a provider outage does not turn into a reconnect
    // storm from every open tab.
    const schedule = () => {
      if (closed || retry) return;
      const delay = Math.min(30_000, 1_000 * 2 ** Math.min(attempt, 5));
      retry = setTimeout(() => { retry = undefined; connect(); }, delay);
    };

    connect();
    return () => {
      closed = true;
      if (retry) clearTimeout(retry);
      try { wsRef.current?.close(); } catch { /* already gone */ }
    };
  }, []);

  return { nonce, connected, recent };
}
