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

export function useLiveSwaps(): { nonce: number; connected: boolean } {
  const [nonce, setNonce] = useState(0);
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

  return { nonce, connected };
}
