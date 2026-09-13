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

if (which === "arc" && Number(round.chainId) !== 5042002) {
  throw new Error(
    `DEPLOYMENT=arc selected a manifest for chain ${round.chainId} — refusing to index the wrong chain`,
  );
}

export default round;
