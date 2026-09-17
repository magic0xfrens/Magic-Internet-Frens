# Decontamination — R45 blind tree

## 1. Tree, exclusions, symlinks
- Blind tree: /tmp/r45-blind/contracts/solidity (rsync of contracts/solidity, excluding audit/, broadcast/, .git, lib/, node_modules/, out/, cache/).
- Symlinked: contracts/solidity/lib -> real lib/; compressed-traits -> real ../compressed-traits (for foundry.toml fs_permissions). node_modules not present under contracts/solidity, so not symlinked.
- Extra fix needed: test/functional/F11_FloorsAndRedemption.t.sol imports ../attacks/YBase.sol, a shared test-helper base contract (not an exploit PoC). It was restored from quarantine into test/attacks/YBase.sol and hand-decontaminated (3 comment-only tag references: Z-10, Y-01, H-1 → generic prose), preserving line count (399 lines, unchanged).
- Blind build required `--skip "lib/v4-periphery/lib/permit2/script/**"` (DeployPermit2.s.sol has a pre-existing broken relative import `src/Permit2.sol` unrelated to decontamination; the real tree's build only avoided it because of a stale out/ cache — out/ is excluded from the blind tree so the fresh compile surfaced it). This is a pre-existing repo issue, not introduced by stripping.

## 2. Quarantined
- test/attacks -> /tmp/r45-quarantine/attacks (139 files; YBase.sol later restored as a helper, decontaminated by hand).
- test/audit did not exist in this tree (no files moved).
- No EXPLOIT_REPORT* files found.

## 3. Tags stripped
decontaminate.py strip: files changed: 66; substitutions: 490 (full per-tag breakdown in strip-log.json / tool stdout, e.g. Z-05:14, B-05:13, Z-17:13, F-19:11, H-01:11, ... down to singletons).

## 4. Verification
- Tool verify: PASS. line-mismatch=0, comment-hits=0, code-hits=46 (finding-ID tokens inside string literals, e.g. assertLe/assertGe revert-message strings like "S-3: ...", "L-4: ...", "I-6: ... (see finding C-01)" — by design the tool only strips COMMENTS, never string literals or code, so these are intentionally left; they are visible only as assertion-failure text during a test run, not as static findings commentary).
- Independent grep for `[A-Z]{1,2}-[0-9]{1,2}` outside lib/: 45 hits, all inside test assertion string literals (same code-hits population as above) — none are prior-review-ID leaks accessible by reading comments.
- Hyphenless letter+digit residuals (25): SVG path commands (M0, M86, M87, M88, M94, M98 — rendering path data, not findings) and doc phase labels (P0-P5 in COLLECTION_FLOOR_UNIFY.md, a project-plan doc not a finding ID).
- Line-count diff (real vs blind, .sol excluding lib/node_modules/test-attacks/test-audit/out/cache/broadcast): 0 differences — identical.
- Size-table comparison (forge build --sizes, real vs blind): CauldronHook 23,140/1,436 both; CauldronRegistry 24,492/84 both; PerpEngine 24,247/329 both; PerpSwapLib 8,968 both (0.8.30 build unit; real tree also emitted an 8,978 row for a separate 0.8.26 compiler unit not present in the blind tree's single-pass build — same source, different solc target, not a code difference); GachaLib 1,466/23,110 both. All identical for contracts present in both tables.

## 5. Residual leak
Perfect blinding is impossible. Hunters are blind to PRIOR CONCLUSIONS (finding IDs, prior reports, the answer-key PoCs) but they are NOT blind to the fact that this code has been reviewed: comments such as "the old routine never did that work" still signal prior review, variable names like everMoved still hint at a past threat, and after three passes the codebase is visibly audited. The real repo also contains audit/ output, a committed agent roster under .claude/agents/, and the orchestrator's memory names prior findings by ID; none of that is visible inside /tmp/r45-blind but the hunters know a review process exists.

Concrete examples (file:line) of comments that still signal prior review, sampled from the blind tree:
- CauldronRegistry.sol:139 — "to an unbounded sub-call (audit). The 63/64 rule means an"
- CauldronRegistry.sol:157 — "(audit). Claims are first-come until a future generation with a"
- CauldronRegistry.sol:253 — "── THE FACET HAD THIS; THE DISPATCHER DID NOT (functional audit) ──"
- CauldronRegistry.sol:342 — "was unreachable (audit). Emergency-admin gated + timelocked,"
- CauldronRegistry.sol:387 — "ARMING IS ALWAYS MANDATORY (audit). This whole check used to be"
- CauldronRegistry.sol:419 — "handing over ownership. See {CauldronBase.igniter} (audit)."
- CauldronRegistry.sol:456 — "emergencyWithdrawLP. NOT timelocked itself (a live exploit needs a"
- CauldronRegistry.sol:515 — "ASYMMETRIC TIMELOCK (audit). Setting a non-zero gate CLOSES the 1:1"
- CauldronRegistry.sol:518 — "used to be neither timelocked nor guardian-vetoable, so a single un-announced"
- CauldronRegistry.sol:551 — "PROGRESSIVE GENERATIONS (audit). On a streamed generation"
- CauldronRegistry.sol:601 — "if (_max == 0 || _max > MAX_NFT_SUPPLY) revert BadConfig(); // audit"
- CauldronRegistry.sol:730 — "{CauldronBase.igniter} (audit). One-shot either way (`summoned`)."
- CauldronToken.sol:46 — "_mint(_registry, _initialSupply); // one-time; supply is fixed forever"
- CauldronToken.sol:54 — "Burn `amount` from `from`. Registry-only — used to burn recovered"
