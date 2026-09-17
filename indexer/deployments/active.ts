import sepolia from "./round.json";
import arc from "./round.arc.json";

/**
 * WHICH DEPLOYMENT THIS INDEXER SERVES.
 *
 *  One codebase, one manifest at a time. `DEPLOYMENT=arc` selects the Arc
 *  testnet manifest; anything else (including unset) selects Sepolia, so an
 *  existing deployment that sets nothing keeps behaving exactly as before.
 *
 *  ── WHY A SECOND SERVICE RATHER THAN ONE MULTI-CHAIN INSTANCE ─────────────
 *  Ponder can index several chains in a single instance, but every table here is
 *  keyed WITHOUT a chainId, and every API route queries without one. Going
 *  multi-chain therefore means touching the schema, every handler and every
 *  route, and the failure mode if any one of them is missed is silent: Arc rows
 *  served as Sepolia data, which reads as plausible numbers rather than an
 *  error. Running the same code twice against two manifests keeps the blast
 *  radius at zero and costs one Railway service.
 *
 *  Consequence to respect: the two deployments MUST NOT share a database. Each
 *  service needs its own `DATABASE_URL` (or its own Postgres schema), because
 *  the table names are identical and the second one to sync would overwrite the
 *  first. The manifests carry different `schema` values, which is what keeps
 *  Ponder's own instance namespacing apart.
 *
 *  Deploy Arc:
 *    DEPLOYMENT=arc DATABASE_URL=<its own db> PONDER_RPC_URL=https://rpc.testnet.arc.network
 */
const which = (process.env.DEPLOYMENT ?? "sepolia").trim().toLowerCase();

//  Cast to the Sepolia manifest's type so the two JSON files are interchangeable
//  to every consumer. They share a shape; `poolIds` is empty on a fresh
//  deployment and infers as `never[]`, which is assignable either way.
const round: typeof sepolia = which === "arc" ? (arc as typeof sepolia) : sepolia;

//  The guard used to fire ONLY for DEPLOYMENT=arc, so a `round.json` repointed
//  at any other chain (the mainnet cutover repoints exactly that file) was
//  accepted with no chain check at all. Assert the selected slot's chain id
//  against what DEPLOYMENT claims, for every slot.
const EXPECTED_CHAIN: Record<string, number> = { arc: 5042002 };
const expected = EXPECTED_CHAIN[which];
if (expected != null && Number(round.chainId) !== expected) {
  throw new Error(
    `DEPLOYMENT=${which} selected a manifest for chain ${round.chainId} (expected ${expected}) — refusing to index the wrong chain`,
  );
}
//  CHAIN_ID, when set, is the operator's explicit statement of which chain this
//  service indexes. Disagreeing with the manifest is a misconfiguration that
//  would otherwise surface as "wrong data served confidently".
const declared = Number(process.env.CHAIN_ID ?? "");
if (Number.isSafeInteger(declared) && declared > 0 && declared !== Number(round.chainId)) {
  throw new Error(
    `CHAIN_ID=${declared} but the selected manifest pins chain ${round.chainId} — refusing to index the wrong chain`,
  );
}

export default round;
