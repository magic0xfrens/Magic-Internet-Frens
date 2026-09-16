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
export type DeployChainId = number;

/** The shared manifest shape. `round.json` is the PRIMARY slot — the one the
 *  cutover copies a new chain's manifest over. */
type Manifest = typeof sepoliaRound;

/**
 *  ── KEYED BY THE MANIFEST'S OWN `chainId`, NEVER BY A LITERAL ──────────────
 *  A hardcoded `{ 11155111: round.json }` is a lie the moment `round.json` is
 *  repointed at another chain, and it is a SILENT one: the app then loads that
 *  manifest under the old key, believes it is on the old chain, force-switches
 *  the wallet there and signs the new chain's calldata against it. Deriving the
 *  key from `m.chainId` makes that state unrepresentable — a manifest can only
 *  ever be reached through its own chain id.
 */
//  Cast so both manifests are interchangeable to consumers. They share a
//  shape; a fresh deployment's `poolIds` is empty and infers as `never[]`.
const BUNDLED: Manifest[] = [sepoliaRound, arcRound as Manifest];

export const DEPLOYMENTS: Record<number, Manifest> = Object.fromEntries(
  BUNDLED.map((m) => [m.chainId, m]),
);

//  Two manifests on the same chain id would silently shadow one another, and
//  the survivor is whichever happens to be last in the array. Fatal, not warned.
if (Object.keys(DEPLOYMENTS).length !== BUNDLED.length) {
  throw new Error(
    `[cauldron] DUPLICATE MANIFEST CHAIN ID — bundled manifests declare ${BUNDLED.map((m) => m.chainId).join(", ")}; ` +
      `each manifest must pin a distinct chainId.`,
  );
}

/** Display metadata for the switcher. Names for chains we know; anything else
 *  is labelled by its id rather than mislabelled as a chain it is not. */
const KNOWN_LABELS: Record<number, { name: string; short: string }> = {
  11155111: { name: "Sepolia testnet", short: "Sepolia" },
  5042002: { name: "Arc testnet", short: "Arc" },
  4663: { name: "Robinhood Chain", short: "Robinhood" },
  46630: { name: "Robinhood testnet", short: "Robinhood" },
};

export const DEPLOY_CHAIN_IDS: DeployChainId[] = Object.keys(DEPLOYMENTS).map(Number);

export const DEPLOYMENT_LABELS: Record<number, { name: string; short: string }> = Object.fromEntries(
  DEPLOY_CHAIN_IDS.map((id) => [id, KNOWN_LABELS[id] ?? { name: `Chain ${id}`, short: `#${id}` }]),
);

/** The chain id of the PRIMARY manifest (`round.json`) — what an unset
 *  `VITE_NETWORK` resolves to, and what the cutover repoints. */
export const PRIMARY_CHAIN_ID: DeployChainId = sepoliaRound.chainId;
/** The chain id of the secondary bundled manifest (`round.arc.json`). */
export const SECONDARY_CHAIN_ID: DeployChainId = (arcRound as Manifest).chainId;

const STORAGE_KEY = "mifrens:selected-chain";

function isDeployChain(id: number): id is DeployChainId {
  return Object.prototype.hasOwnProperty.call(DEPLOYMENTS, id);
}

/**
 * The chain whose deployment we are reading, resolved ONCE at module load.
 *
 *  Order: an explicit user choice wins, then VITE_CHAIN_ID (authoritative, and
 *  FATAL when it names a chain no bundled manifest declares), then
 *  VITE_NETWORK's slot, then the primary manifest's own chain id. There is no
 *  hardcoded fallback chain id anywhere in this function — every value it can
 *  return came out of a manifest.
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
  //  ── VITE_CHAIN_ID IS AUTHORITATIVE, AND UNSUPPORTED IS FATAL ─────────────
  //  This is the knob an operator actually sets for a cutover. If it names a
  //  chain no bundled manifest declares, the ONLY safe behaviour is to refuse:
  //  falling back would put the app on a chain the operator did not ask for
  //  while it holds another chain's addresses — which is a user signing
  //  value-bearing calldata for chain A with their wallet on chain B.
  const rawEnvId = Number((import.meta.env.VITE_CHAIN_ID as string | undefined) ?? "");
  if (Number.isSafeInteger(rawEnvId) && rawEnvId > 0) {
    if (!isDeployChain(rawEnvId)) {
      throw new Error(
        `[cauldron] UNSUPPORTED CHAIN — VITE_CHAIN_ID=${rawEnvId}, but no bundled manifest declares ` +
          `that chain (have: ${DEPLOY_CHAIN_IDS.join(", ")}). Point indexer/deployments/round.json at ` +
          `chain ${rawEnvId} (its "chainId" field IS the key) and rebuild. Refusing to start rather ` +
          `than loading another chain's addresses.`,
      );
    }
    return rawEnvId;
  }

  //  VITE_NETWORK picks a manifest SLOT, never a hardcoded chain id: "arc" is
  //  the secondary manifest, everything else is the primary one (`round.json`,
  //  which the cutover repoints). A typo used to land silently on Sepolia.
  const network = ((import.meta.env.VITE_NETWORK as string) ?? "").trim().toLowerCase();
  if (network === "arc") return SECONDARY_CHAIN_ID;
  if (network && !["testnet", "sepolia", "primary", "target", "mainnet"].includes(network)) {
    throw new Error(
      `[cauldron] UNKNOWN VITE_NETWORK="${network}" — expected one of testnet|sepolia|primary|target|mainnet|arc, ` +
        `or set VITE_CHAIN_ID to one of ${DEPLOY_CHAIN_IDS.join(", ")}.`,
    );
  }
  return PRIMARY_CHAIN_ID;
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
