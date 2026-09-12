/**
 * DEMO MODE — a scripted death/relaunch for filming.
 *
 * The real brew only reaches "dying" when its 24h volume falls under the death
 * floor, and only reaches "dead" after the chain says so. That is not something
 * you can arrange on camera. This module fakes the last three beats of the
 * lifecycle — dying → dead → summon → reborn — entirely in the browser, so the
 * ritual can be recorded without touching the chain.
 *
 * NOTHING here is on by default. It arms only from an explicit URL parameter:
 *
 *     ?demo=dying                       → the brew is fading
 *     ?demo=dead                        → death floor hit, relaunch panel armed
 *     ?demo=dead&demoBrew=Frogtopia&demoTicker=FROG
 *                                       → name the brew the summon reveals
 *     ?demo=off                         → disarm (also: close the tab)
 *
 * Once armed the mode is kept in sessionStorage so tab navigation and reloads
 * mid-take don't drop out of it. It is per-tab and per-session: a normal visitor
 * who never types `?demo=` can never enter it.
 *
 * The summon is mocked end to end — no wallet prompt, no transaction, no gas.
 * `relaunch()` returns the sentinel hash below, and `waitForReceipt` resolves it
 * without asking an RPC. Every OTHER action (vote, propose, migrate, trade) is
 * untouched and still hits the chain for real.
 */

export type DemoStage = "dying" | "dead" | "summoning" | "reborn";

export interface DemoState {
  stage: DemoStage;
  /** Name + ticker the summon reveals. Also fills the winning-proposal card
   *  when governance has no real proposal to show on camera. */
  brew: string;
  ticker: string;
}

/** Fake tx hash handed back by the mocked relaunch. `waitForReceipt` recognises
 *  it and resolves without an RPC round-trip, so nothing ever hits the chain. */
export const DEMO_TX_HASH =
  "0xdem0dem0dem0dem0dem0dem0dem0dem0dem0dem0dem0dem0dem0dem0dem0dem0" as `0x${string}`;

/** How long the "Summoning…" beat holds before the new iteration appears. Long
 *  enough to be a shot, short enough not to be a wait. */
const SUMMON_MS = 5200;

/** How long the mocked relaunch "takes to mine". Kept in this file so it stays
 *  in step with the stage hop in `runDemoSummon`. */
export const RECEIPT_MS = 900;

const KEY = "cauldron.demo";

/* ── store ──────────────────────────────────────────────────────────────── */

let state: DemoState | null = null;
let armed = false;
const listeners = new Set<() => void>();

function emit() { listeners.forEach((l) => l()); }

/** Read the URL (then sessionStorage) once per page load. Idempotent. */
function init() {
  if (armed) return;
  armed = true;
  if (typeof window === "undefined") return;

  const q = new URLSearchParams(window.location.search);
  const param = q.get("demo");

  if (param === "off") {
    sessionStorage.removeItem(KEY);
    return;
  }

  if (param === "dying" || param === "dead") {
    state = {
      stage: param,
      brew: q.get("demoBrew") || "Frogtopia",
      ticker: (q.get("demoTicker") || "FROG").toUpperCase(),
    };
    sessionStorage.setItem(KEY, JSON.stringify(state));
  } else {
    try {
      const saved = sessionStorage.getItem(KEY);
      if (saved) state = JSON.parse(saved) as DemoState;
    } catch { state = null; }
  }

  if (state) {
    console.warn(
      `[cauldron] DEMO MODE ARMED (stage=${state.stage}, brew=${state.brew}). ` +
      `The lifecycle is scripted and the summon is mocked. Add ?demo=off to leave.`,
    );
  }
}

export function demoState(): DemoState | null {
  init();
  return state;
}

function setStage(stage: DemoStage) {
  if (!state) return;
  state = { ...state, stage };
  try { sessionStorage.setItem(KEY, JSON.stringify(state)); } catch { /* private mode */ }
  emit();
}

export function subscribeDemo(fn: () => void): () => void {
  listeners.add(fn);
  return () => { listeners.delete(fn); };
}

/** Drive the scripted summon: dead → (mined) → summoning → reborn. Called by the
 *  mocked `relaunch()`. No-op outside demo mode.
 *
 *  The first hop waits out the mocked receipt. The page only shows its
 *  "Summoning…" screen once the caller has seen a mined tx, so flipping the
 *  stage any earlier would flash the pre-summon genesis view for a second —
 *  exactly the frame you don't want in the footage. */
export function runDemoSummon() {
  if (!state) return;
  setTimeout(() => {
    setStage("summoning");
    setTimeout(() => setStage("reborn"), SUMMON_MS);
  }, RECEIPT_MS + 150);
}
