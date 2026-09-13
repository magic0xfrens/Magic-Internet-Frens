import sepoliaRound from "../../indexer/deployments/round.json";
import arcRound from "../../indexer/deployments/round.arc.json";

/**
 * WHICH DEPLOYMENT THE APP IS LOOKING AT.
 *
 *  The app talks to ONE chain at a time, but the user can now choose which. Both
 *  manifests are bundled; the selection picks one, and it is persisted so a
 *  reload keeps you where you were.
 *
 *  ── WHY SWITCHING RELOADS THE PAGE ────────────────────────────────────────
 *  `CAULDRON` (src/config/cauldron.ts) is a module-level const read by 41 files,
 *  and the indexer base URL by 22 more. Making all of that reactive would mean
 *  threading a chainId through every read hook and every query key — and the
 *  failure mode of missing ONE is silent: Sepolia data rendered under Arc's
 *  header, which looks like plausible numbers rather than an error. A reload
 *  re-evaluates every module against the new selection with zero chance of
 *  cross-chain bleed, and costs the user one flash. That is the right trade for
 *  a value that changes a handful of times per session, never mid-interaction.
 *
 *  This is also the prerequisite for doing it reactively later, if that is ever
 *  worth it: the manifests are keyed by chain now, which is the hard part.
 */
export const DEPLOYMENTS = {
  11155111: sepoliaRound,
  //  Cast so both manifests are interchangeable to consumers. They share a
  //  shape; a fresh deployment's `poolIds` is empty and infers as `never[]`.
  5042002: arcRound as typeof sepoliaRound,
} as const;

export type DeployChainId = keyof typeof DEPLOYMENTS;

/** Display metadata for the switcher. Kept here so it cannot drift from DEPLOYMENTS. */
export const DEPLOYMENT_LABELS: Record<DeployChainId, { name: string; short: string }> = {
  11155111: { name: "Sepolia testnet", short: "Sepolia" },
  5042002: { name: "Arc testnet", short: "Arc" },
};

export const DEPLOY_CHAIN_IDS = Object.keys(DEPLOYMENTS).map(Number) as DeployChainId[];

const STORAGE_KEY = "mifrens:selected-chain";

function isDeployChain(id: number): id is DeployChainId {
  return Object.prototype.hasOwnProperty.call(DEPLOYMENTS, id);
}

/**
 * The chain whose deployment we are reading, resolved ONCE at module load.
 *
 *  Order: an explicit user choice wins, then VITE_NETWORK's default, then
 *  Sepolia — which is the long-running deployment and the safe place to land if
 *  anything above is malformed.
 *
 *  Wrapped because `localStorage` throws outright in some privacy modes rather
 *  than returning null, and a config module that throws takes the whole app down
 *  before anything can render an error.
 */
function resolveInitialChain(): DeployChainId {
  //  `?chain=` FIRST, because it is both the shareable form ("look at Arc") and
  //  the fallback `selectDeployChain` uses when localStorage is unavailable. If
  //  this were not read here that fallback would silently do nothing.
  try {
    const fromUrl = Number(new URLSearchParams(window.location.search).get("chain"));
    if (Number.isSafeInteger(fromUrl) && isDeployChain(fromUrl)) return fromUrl;
  } catch {
    /* no window/search — fall through */
  }
  try {
    const stored = Number(localStorage.getItem(STORAGE_KEY));
    if (Number.isSafeInteger(stored) && isDeployChain(stored)) return stored;
  } catch {
    /* privacy mode or no storage — fall through to the env default */
  }
  const network = ((import.meta.env.VITE_NETWORK as string) ?? "testnet").trim().toLowerCase();
  if (network === "target" || network === "mainnet" || network === "arc") return 5042002;
  return 11155111;
}

export const SELECTED_CHAIN_ID: DeployChainId = resolveInitialChain();

/** The manifest for the selected chain — the single source every consumer reads. */
export const ACTIVE_ROUND = DEPLOYMENTS[SELECTED_CHAIN_ID];

/**
 * Switch chains: persist the choice and reload so every module re-resolves.
 *
 *  Reloads even when the id is unchanged is pointless, so that case is a no-op —
 *  otherwise clicking the chain you are already on would blank the screen for no
 *  reason.
 */
export function selectDeployChain(id: DeployChainId): void {
  if (id === SELECTED_CHAIN_ID) return;
  try {
    localStorage.setItem(STORAGE_KEY, String(id));
  } catch {
    //  Cannot persist, but the switch should still work for this session —
    //  reload with the choice in the URL so `resolveInitialChain` is not the
    //  only path in. Falls back to a plain reload if even that fails.
    try {
      const url = new URL(window.location.href);
      url.searchParams.set("chain", String(id));
      window.location.href = url.toString();
      return;
    } catch {
      /* fall through */
    }
  }
  window.location.reload();
}

/** True when this deployment has no indexer yet — the UI degrades rather than lying. */
export const HAS_INDEXER = Boolean((ACTIVE_ROUND.indexerUrl ?? "").trim());
