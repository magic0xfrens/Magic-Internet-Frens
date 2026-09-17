# Decontamination — RH mainnet review 2026-09-16

Four independent blind trees built: /tmp/rh-blind-h1 .. h4.
- Copied contracts/solidity excluding audit/, broadcast/, .git/, out/, cache/, lib/.
- lib/ symlinked back to the real contracts/solidity/lib. No ../../compressed-traits
  dir exists in this repo (verified absent), so that symlink step was skipped.
- test/attacks/ and test/audit/ moved to /tmp/rh-quarantine-hN/{attacks,audit};
  test/attacks/YBase.sol was copied back in as the shared helper.
- *.md files matching AUDIT|REDTEAM|REMEDIATION|VULN|FINDING|REVIEW (case-insensitive)
  removed from each tree.
- Used the existing tool at
  audit/FINAL_BLIND_2026-09-13/tools/decontaminate.py (repo-root audit/, not
  contracts/solidity/audit/) — ran `strip` then `verify` on each tree.
  All four: PASS line-mismatch=0 comment-hits=0 code-hits=46 hyphenless-residual=25
  (code-hits/hyphenless-residual are pre-existing non-comment occurrences the tool
  does not rewrite by design — e.g. identifiers/strings — not tag leakage).

## Verification results
(a) grep -rniE 'audit|redteam|remediation|B-0[0-9]|R[0-9][A-Z]|finding|vulnerab'
    --include='*.sol' on cauldron/ (source root) in all four trees: 0 hits.
(b) `find cauldron -name '*.sol' | xargs wc -l` total: 17,268 lines, identical
    between the real tree and h1 (and by construction h2-h4, same rsync).
(c) forge build --sizes on h1: all 7 named contracts (CauldronHook, CauldronRegistry,
    PerpEngine, PoolOps, PerpVault, GachaLib, PerpSwapLib) byte-identical to the
    real-tree A2 baseline. The full table is NOT byte-identical overall: rows for
    test-only contracts under test/attacks/ (e.g. B06Swapper, BGov07, StubRegistry
    variants) are absent from the blind table since those files were quarantined,
    and a handful of library rows show path-qualifier differences
    (e.g. "BalanceDeltaLibrary.0.8.26" vs "BalanceDeltaLibrary.0.8.26
    (lib/v4-periphery/...)") from forge's ambiguous-name disambiguation, which
    depends on which duplicate-named contracts are present in the compiled set.
    This is expected given the intentional test/attacks/ removal, not a
    decontamination failure.

## Could NOT be removed
- NatSpec/comments in cauldron/*.sol that describe mechanisms (rotation, dividend
  routing, etc.) in plain English without finding-ID tags — the tool strips tags,
  not prose, so any comment that documents *why* a guard exists (without naming a
  finding ID) remains, by design, since removing it would risk misleading the
  blind reviewer about intended behavior.
- Variable/function names that may hint at a past fix (e.g. names referencing
  "markConsumed", "isNotLocked") are code, not comments, and the tool explicitly
  never touches identifiers.
