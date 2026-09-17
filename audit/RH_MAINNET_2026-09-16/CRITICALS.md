# Criticals

Running list. Orchestrator-maintained. A row lands here the moment an agent reports
it VERIFIED; the verdict column is filled at P2/P3.

## C1 — T5A — the frontend cannot target chain 4663 at all (VERIFIED, Hunter 5)

`src/config/deployments.ts:24-29` hard-codes `DEPLOYMENTS = {11155111, 5042002}`.
There is no `4663` key, and neither `scripts/deploy-round.mjs` nor
`apply-deployment.mjs` writes one.

Consequences, both proven from the **emitted bundle** (`Ea={11155111:z1,5042002:tS}`):
- `VITE_NETWORK` unset → the Robinhood manifest loads under the **Sepolia** key, so
  `IS_TARGET=false`, `CAULDRON.chainId=11155111`, and `useCauldronSwap.ts:194`
  **force-switches the user's wallet to Sepolia** and then sends Robinhood-addressed
  `play{value}` calldata. `src/config/cauldron.ts:25` only `console.error`s.
- `VITE_NETWORK=mainnet` → silently loads **Arc testnet** addresses.
- Same root cause discards `VITE_CHAIN_DECIMALS` / `VITE_CHAIN_CURRENCY`
  (`chains.ts:176-177`).

PoC: `poc/h5/h5_chain4663_seam.sh` (two real `npm run build`s + greps of `dist/`).

**The chain id to add is `4663`** — independently VERIFIED by the P0.5 agent three
ways (live `cast chain-id`, `ArbSys.arbChainID()`, ethereum-lists registry). This
does not need more research; see CHAIN_PROFILE.md §0b, §1.

Status: assigned to the chain-config fixer.

## Deploy-blocking documentation defects (CHAIN_PROFILE.md §0)

Not contract bugs, but each one misdirects an operator at deploy time.

- **0a** `docs/MAINNET_LAUNCH.md:10` gives RPC `https://rpc.chain.robinhood.com`
  under a heading that says "(confirmed)". **That host does not exist** — resolves to
  CloudFront, refuses TLS with `handshake_failure` from three independent TLS stacks.
  Real host: `https://rpc.mainnet.chain.robinhood.com`.
- **0b** `docs/protocol/09-FRONTEND.md:44-46` says testnet is `46646`. **46646 is not
  a chain id at all** (registry 404). The testnet is **46630**. Mainnet 4663 is
  confirmed, so the "4663 vs 46646 ambiguity" that doc flags as unresolved is closed.
- **0c** `docs/protocol/11-OPERATIONS.md:25` documents `VITE_ROBINHOOD_CHAIN_ID`.
  **The code does not read it.** `chains.ts:29-36` reads `VITE_CHAIN_ID` and falls
  back to **5042002 (Arc)** — never 4663. This is the other half of C1.

## High — T5B (VERIFIED, Hunter 5)

`indexer/ponder.config.ts:117` sends a **4663 manifest to a Sepolia RPC** when
`PONDER_RPC_URL` is unset, while the comment at `:88-91` claims that can "NEVER"
happen. `/freshness` uses `API_RPC_URL`, which also defaults to Sepolia, so the
health endpoint can report healthy while the indexer reads the wrong chain.
PoC: `poc/h5/h5_ponder_default_chain.mjs`.
