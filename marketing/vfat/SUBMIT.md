# Submitting MiFrens to vfat.tools

Fork-ready bundle. Everything here targets vfat's **standard Synthetix loader** so
the PR is a fast, low-friction merge. Nothing is submittable until MiFrens is on a
**mainnet** vfat indexes (it is currently Sepolia-only) — see
`docs/vfat-listing-readiness.md` for the full gate list.

## Files in this folder
- `mifrens.js`   → copy to `src/static/js/mifrens.js` in a vfat-tools fork
- `index.ejs`    → copy to `src/views/pages/mifrens/index.ejs`
- `ADAPTER_SPEC.md` → the StakingRewards adapter to deploy+verify+audit on mainnet
- `SUBMIT.md`    → this file

## Steps (once on mainnet)
1. Build, audit, deploy & **verify** the two PLV adapters (`ADAPTER_SPEC.md`).
2. Put their addresses into `mifrens.js` (`PLV_ADAPTER_ETH`, `PLV_ADAPTER_TOKEN`).
3. Fork https://github.com/vfat-io/vfat-tools, clone, `npm install`.
4. Copy the two files into the paths above.
5. Register the page in the chain index (append at the **bottom**, chronological):
   - Ethereum → `src/static/js/all.js`
   - other chains → that chain's file (e.g. `base.js`, `arbitrum.js`)
   Add an entry pointing at `mifrens` (match the shape of existing entries in that
   file). **Do not** add to the front-page index.
6. `npm run dev`, open `localhost:3000/mifrens`, confirm real TVL/APR render.
7. Commit → push → open a PR. In the PR body include: project URL, the two verified
   adapter addresses (explorer links), and a one-line "real-yield perp LP vault"
   description.

Optional: paid fast-track review via MCN Ventures (https://mcn.ventures/review).
Maintainer contact: `vfat0` on Twitter/Telegram.
