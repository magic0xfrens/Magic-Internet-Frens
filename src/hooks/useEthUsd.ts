import { useEffect, useState } from "react";

/**
 * Live ETH/USD spot (Coinbase — CORS-friendly, no key).
 *
 * Module-level shared state: several panels want this number at once and the
 * rate is identical for all of them, so one poll feeds every subscriber rather
 * than each mount opening its own 60s interval.
 */
let current = 0;
let timer: ReturnType<typeof setInterval> | null = null;
const subscribers = new Set<(p: number) => void>();

async function poll() {
  try {
    const r = await fetch("https://api.coinbase.com/v2/prices/ETH-USD/spot", {
      signal: AbortSignal.timeout(5000),
    });
    const j = await r.json();
    const p = Number(j?.data?.amount);
    if (p > 0) {
      current = p;
      for (const fn of subscribers) fn(p);
    }
  } catch {
    /* keep the last good price */
  }
}

export function useEthUsd(): number {
  const [price, setPrice] = useState(current);

  useEffect(() => {
    subscribers.add(setPrice);
    // First subscriber starts the poll; the rest ride along.
    if (timer === null) {
      poll();
      timer = setInterval(poll, 60_000);
    } else if (current > 0) {
      setPrice(current);
    }

    return () => {
      subscribers.delete(setPrice);
      if (subscribers.size === 0 && timer !== null) {
        clearInterval(timer);
        timer = null;
      }
    };
  }, []);

  return price;
}
