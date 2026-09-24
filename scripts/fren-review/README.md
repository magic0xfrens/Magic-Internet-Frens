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
3. **Push** the review repo and post jobs through IMD's paid API
   ([imd.fun/docs](https://imd.fun/docs/#paid): `job.open`, 0.5 IMD per job on Ethereum mainnet,
   paid over x402 with Permit2 by a wallet holding IMD). Every job is `jobs/deep-review.json`: one deep
   review by **six seats for one price** (a job holds up to six steps; IMD picks the seats and only
   guarantees a review is not done by the seat it reviews): four hunters in parallel, a report writer that re-runs and merges them, and a
   verifier whose findings reopen the report until it holds.
   ```sh
   node tools/post-job.mjs --commit <review-repo sha> --slot 0 --dry          # fill and check, no network
   IMD_PAID_TOKEN=$(openssl rand -hex 32) node tools/post-job.mjs --commit <sha> --slot 0 --quote   # free quote
   node tools/post-job.mjs --commit <sha> --slot 1 --prior <job id>,<job id> --quote   # build on earlier reports
   ```
   `--slot n` gives the four hunters foci `4n … 4n+3` of a fixed rotation, so every three jobs cover all
   twelve; `--foci` names four instead. `--prior` attaches earlier jobs' accepted report and findings
   files as inputs. Post as many jobs as it takes; re-export with the rebuilt ledger between batches so
   new jobs start from everything already known. Budget and model tier are IMD's defaults per skill
   and cannot be set. Post ONE job first and confirm all six steps come back accepted before posting
   the rest.
4. **Record every job id** (`admission.result.jobId` of each admitted order) in the review repo's `ledger/jobs.txt`.
5. **Rebuild the ledger** there: `node tools/aggregate.mjs`, then set our own calls in
   `ledger/triage.json` (`fixed` once a fix is merged here, `wontfix`, `duplicate`, a corrected
   severity) and run it again. Commit the ledger.
6. **Pay the pepes** (here):
   ```sh
   node scripts/frenlist/add-imd-workers.mjs $(grep -oE '^[0-9a-f-]{36}' ../IMD-fren-to-fren-review/ledger/jobs.txt)
   node scripts/frenlist/build.mjs     # deploy the site with the new file, then setDiscountRoot
   ```
7. **Merge accepted fixes here**, then cut the next round from the fixed commit.
