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

/** keccak256("Swap(bytes32,address,int128,int128,uint160,uint128,int24,uint24)") */
const SWAP_TOPIC = "0x40e9cecb9f5f1f1c5b9c97dec2917b7ee92e57ba5563708daca94dd84ad7112f";

/** A swap seen on the wire, decoded far enough to show instantly. */
let nextId = 1;

export interface LiveSwap {
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
        ws.send(JSON.stringify({
          jsonrpc: "2.0", id: 1, method: "eth_subscribe",
          params: ["logs", { address: pm, topics: [SWAP_TOPIC] }],
        }));
      };

      ws.onmessage = (e) => {
        try {
          const m = JSON.parse(e.data as string);
          const log = m?.params?.result;
          if (!log?.topics) return;
          // topics[1] is the poolId. Filter here rather than in the
          // subscription: v4 emits every pool's swaps from one address, and
          // subscribing to all of them would wake the page on unrelated trades.
          const pid = String(log.topics[1] ?? "").toLowerCase();
          if (poolIds.length > 0 && !poolIds.includes(pid)) return;

          //  Decode just enough for an INSTANT toast, then let the indexer
          //  deliver the authoritative numbers a moment later. v4 packs
          //  (amount0, amount1, sqrtPriceX96, liquidity, tick, fee) into data;
          //  amount0 is the first 32-byte word and, because the quote is always
          //  currency0 by construction, it is the quote leg.
          //
          //  Deliberately approximate: this exists to make the page feel alive
          //  the moment a block lands, NOT to become a second source of truth.
          //  The indexer still owns the tape and the candles.
          const raw = String(log.data ?? "").slice(2);
          let quoteWei = 0n;
          let isBuy = false;
          if (raw.length >= 64) {
            const w0 = BigInt("0x" + raw.slice(0, 64));
            // int128 is sign-extended into the word; negative means it left the
            // pool, i.e. the trader RECEIVED quote → a sell.
            const signed = w0 >= (1n << 255n) ? w0 - (1n << 256n) : w0;
            isBuy = signed > 0n;
            quoteWei = signed < 0n ? -signed : signed;
          }
          // Token leg is the second word (currency1 by construction).
          let tokenWei = 0n;
          if (raw.length >= 128) {
            const w1 = BigInt("0x" + raw.slice(64, 128));
            const st = w1 >= (1n << 255n) ? w1 - (1n << 256n) : w1;
            tokenWei = st < 0n ? -st : st;
          }
          const hash = String(log.transactionHash ?? "");
          const key = `${hash}:${String(log.logIndex ?? "")}`;
          setRecent((prev) => {
            // Same log can arrive twice across a reconnect; key on tx+logIndex
            // so a re-subscribe does not double-paint the feed.
            if (prev.some((x) => x.key === key)) return prev;
            return [{ id: nextId++, key, isBuy, quoteWei, tokenWei, txHash: hash }, ...prev].slice(0, 12);
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
