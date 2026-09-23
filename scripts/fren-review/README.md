# Fren Review — running a round

The Identity.md swarm red-teams the Cauldron from a dedicated review repo (`magic0xfrens/IMD-fren-to-fren-review`). This folder builds that repo from a commit here; `template/` is
everything that ships in it (the skill, landing page, job templates, ledger tools).

**Why a separate repo:** IMD workers run `forge config`, `forge build` and `forge test` at the
repository ROOT with the default profile, each capped at 10 minutes, and refuse to submit on a
failure; they also reject any `fs_permissions` outside the repo. This repo has neither a root
Foundry project nor a working default profile, and its full test suite needs `FORK_RPC`. The export
fixes all three and compiles only the contracts plus the PoC harness.

## A round

1. **Cut it from a commit that builds.**
   ```sh
   python3 scripts/fren-review/export.py --commit <sha> --out ../IMD-fren-to-fren-review --round <N> --git-commit
   ```
   The review repo's `ledger/` survives every export — it is the memory between rounds.
2. **Check it like a worker would** (in `../IMD-fren-to-fren-review`): `git submodule update --init --recursive`,
   `forge build` and `forge test` each under 10 minutes and green, `python3 tools/check-map.py`.
3. **Push** the review repo and post jobs from `jobs/` with `<COMMIT>` filled in:
   many `hunt.json`; one `prove.json` per `reported` ledger issue; one `fix.json` per `proven` one.
   Paste `SKILL.md` (without front matter) as each job's `guidance`. Post ONE hunt first as a dry
   run and confirm it comes back accepted before posting the rest.
4. **Record every job id** in the review repo's `ledger/jobs.txt`.
5. **Rebuild the ledger** there: `node tools/aggregate.mjs`, then set our own calls in
   `ledger/triage.json` (`fixed` once a fix is merged here, `wontfix`, `duplicate`, a corrected
   severity) and run it again. Commit the ledger.
6. **Pay the pepes** (here):
   ```sh
   node scripts/frenlist/add-imd-workers.mjs $(grep -oE '^[0-9a-f-]{36}' ../IMD-fren-to-fren-review/ledger/jobs.txt)
   node scripts/frenlist/build.mjs     # deploy the site with the new file, then setDiscountRoot
   ```
7. **Merge accepted fixes here**, then cut the next round from the fixed commit.
