# DECONTAMINATION — FINAL_BLIND_2026-09-13

## Stripping
Tool: audit/FINAL_BLIND_2026-09-13/tools/decontaminate.py (copied from FINAL_BLIND_2026-09-11, unchanged).
Ran `strip` against /tmp/blind-final/contracts/solidity.
Result: 139 files changed, 759 substitutions of finding-ID-shaped comment tags (e.g. R-02, B-05, Q-01, F-19, Z-17, S08, etc — full tag_frequency table in /tmp/blind13-strip.json).

## Quarantine
- `test/attacks/` moved wholesale to /tmp/blind-quarantine/test/attacks/ (all X/Y/Z/A/B/Q/S/T PoC files, EXPLOIT files, ZAuditBase.sol).
- No `test/audit/` directory existed under contracts/solidity/test in this tree (it's a different location than in earlier runs); nothing quarantined there.
- No EXPLOIT_REPORT*/*REDTEAM*/*REMEDIATION*/*AUDIT* files found outside /lib/ at the root of the copied tree, other than test/final/FinalAuditBase.sol, which was KEPT — it is a base contract used by test/final/ (legitimate coverage), not a report.
- Correction made mid-run: test/functional/F10_QuoteRotationTotality.t.sol and F11_FloorsAndRedemption.t.sol import `test/attacks/YBase.sol` as a shared test-harness base class (not an attack PoC). Restoring the whole attacks/ dir would have leaked all PoCs, so only YBase.sol was copied back from quarantine into the blind tree at its original path (test/attacks/YBase.sol). It contained zero finding-ID tags to strip (checked directly, 0 substitutions).

## Verification
(a) grep for finding-ID-shaped tags, excluding EIP-/ERC-/Q[0-9] fixed-point names: 45 residual hits, ALL inside string literals passed to assertEq/assertGe/assertLe/assertFalse as failure messages in test/invariants/*.t.sol and test/final/FacetLayoutInvariant.t.sol (e.g. `"V-1: escrow owes more than it holds"`, `"L-3: entitlement exceeds everything ever credited"`). The stripper only touches `//` and `/* */` comments per spec; string literals are code, not comments, so these are NOT bugs in the tool — they are a residual leak (see below).
    grep for `\b(LIQ|LEG|FIX)-[0-9]{1,2}\b`: 8 hits, all in cauldron/PerpEngine.sol, PerpSwapLib.sol, RedemptionExt.sol comments (e.g. "the LIQ-02 partial-close fix", "red-team LIQ-01", "red-team LEG-01"). These are 3-letter prefixes; the tool's TAG regex only captures 1-2 letter groups ([A-Z]{1,2}), so these were never matched or stripped. This is a genuine gap in the stripper, NOT fixed in this run (out of the ≤30-call budget; flagging instead).
(b) wc -l diff between real and blind trees (excluding lib/, test/attacks/, test/audit/, cache/, out/): 0 lines different — line counts identical file-for-file.
(c) forge build --sizes on the blind tree: exit 0. Runtime/initcode byte columns for every tracked contract (CauldronHook, CauldronRegistry, PoolOps, PerpEngine, PerpSwapLib, CauldronSeeder, CauldronToken, etc.) are byte-identical to the real tree's sizes table; the diff between the two greps shows only cosmetic differences (some contract names carry a "(path.sol)" disambiguation suffix in one tree's output and not the other, and PerpEngine/LegacyBuyLib matched by the grep pattern used for the tracked-contract table in the blind run but not the real one because the real STEP-3 grep used a narrower earlier pass — no numeric column differs anywhere).

## Residual leaks (not removed)
1. Finding-ID tags embedded in Solidity STRING LITERALS (invariant assertion messages) — 45 instances, e.g. "I-6: the hook owes more ETH than it holds (see finding C-01)". A blind reader who runs the invariant suite and reads failure output will see these IDs. Left in place per the tool's comment-only mandate; a future decontamination pass would need a separate (riskier) string-literal rewrite.
2. Three-letter finding tags (LIQ-01, LIQ-02, LEG-01) inside comments — 8 instances in PerpEngine.sol, PerpSwapLib.sol, RedemptionExt.sol — not matched by the current regex's 1-2 letter cap.
3. Review-shaped prose survives even where the raw tag was stripped, e.g. "MEASURED DEAD END, DO NOT RETRY (red-team LIQ-02): moving this body into ..." reads as an audit note regardless of the ID.
4. Variable/function names that encode a fix are present and were NOT renamed (out of scope for a comment-only stripper): grepped `everMoved`, `reanchored`, `accountedDeposits`, `MIN_SEED_UNITS`, `priceRef`, `_syncRef`, `_bench`, `failedReads` against /tmp/blind-final — several of these identifiers exist in the real source (not enumerated further here; renaming code identifiers was out of scope per the brief, which restricts stripping to comments).
5. `docs/protocol/` was checked and confirmed NOT copied into /tmp/blind-final (it lives outside contracts/solidity at the repo root and rsync only mirrored contracts/solidity/).
6. This orchestrator's own memory file names prior findings (Q-01, B-01, B-05, B-06, B-09/10, B-11/12/13, B-15, F-10/11, etc.) — that memory is available to whichever agent reads it, so true blinding depends on NOT re-reading MEMORY.md's finding-ID list before hunting in the blind tree, which is a process constraint, not something this stripper can enforce.

Overall: comment-level blinding is solid (0 stripper-scope tags, 759 removed, sizes/line-counts verified identical) but NOT total — string-literal tags, 3-letter tags, and naming/prose leaks remain.
