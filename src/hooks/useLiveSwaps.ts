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
 * NOTE on wss://feed.mainnet.chain.robinhood.com — that feed carries Robinhood
 * Chain MAINNET data. Our pool is on Sepolia, so it has nothing to say about our
 * trades. The idea behind it is right, and this is that idea pointed at the
 * chain we are actually on; when the protocol moves to Robinhood Chain, only the
 * URL below changes.
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
} as const;

export type EventKind =
  | "buy" | "sell" | "gacha-commit" | "gacha-win" | "gacha-miss"
  | "perp-open" | "perp-close" | "liquidation" | "badge";

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
  /** Wall-clock ms the log was seen. */
  ts: number;
  txHash: string;
}

export function useLiveSwaps(): { nonce: number; connected: boolean; recent: LiveSwap[] } {
  const [nonce, setNonce] = useState(0);
  //  A ROLLING LIST, not a single `latest`. Exposing one value dropped events:
  //  React batches state updates, so several swaps arriving in the same tick
  //  collapsed into one and a busy pool showed a single toast. The gacha router
  //  fires a buy and a sell back to back, which is exactly that case.
  const [recent, setRecent] = useState<LiveSwap[]>([]);
  const [connected, setConnected] = useState(false);
  const wsRef = useRef<WebSocket | null>(null);

  useEffect(() => {
    const urls = WS_URLS[round.chainId] ?? [];
    if (urls.length === 0) return;

    const poolIds = (round.poolIds ?? []).map((p: string) => p.toLowerCase());
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
        const ours = [round.contracts.hook, round.contracts.perpEngine].filter(Boolean);
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
            if (poolIds.length > 0 && !poolIds.includes(pid)) return;

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
          } else if (topic0 === T.BADGE) {
            kind = "badge"; who = addrTopic(2);
            detail = `badge #${word(0)}`;
          }
          if (!kind) return;

          const hash = String(log.transactionHash ?? "");
          const key = `${hash}:${String(log.logIndex ?? "")}`;
          setRecent((prev) => {
            if (prev.some((x) => x.key === key)) return prev;
            return [{
              id: nextId++, key, kind, isBuy: kind === "buy",
              quoteWei, tokenWei, price, ts: Date.now(), txHash: hash, who, detail,
            }, ...prev].slice(0, 24);
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
