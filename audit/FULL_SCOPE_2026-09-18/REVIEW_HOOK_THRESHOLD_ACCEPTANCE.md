# HOOK-01 acceptance continuation — 2026-09-19

## Executed evidence

From `contracts/solidity`:
`FOUNDRY_PROFILE=cauldron forge test --offline --threads 1 --match-contract LegacyThresholdAcceptanceTest -vv`

Result: exit 0, **9 passed / 0 failed / 0 skipped**. Seven new tests plus two
inherited F2A regressions; the latter are not new distinct coverage. Two fuzz
tests each ran 256 cases. Initial harness compiles failed because the threshold
fields are internal; corrected using read-only `vm.load` of compiler-confirmed
slot 69, without changing production visibility or writing target storage.

`LegacyThresholdAcceptance.t.sol` exercises:

- native → six decimals → eighteen decimals → native cache refresh;
- configuration refresh and zero-argument preservation of the old threshold;
- reverting and 0–31-byte metadata fallback to one raw unit;
- unsupported metadata words 78 through uint256 maximum, fallback to one;
- sub-raw-unit rounding clamped to one;
- 24/77-decimal multiplication and uint256 overflow saturation;
- inherited six/eighteen-decimal actual buyback call assertions.

Production hook and registry are used, but PoolManager is a stub. Metadata
responses are mocked. Cache transitions do not establish full treasury rotation
or actual native-pool buyback execution. No production change made in this pass.

## Artifact and layout evidence

Current `out/CauldronHook.sol/CauldronHook.json` metadata's hook source hash
matches the current file's keccak256:
`0x4b555fe9c1cba8942e91c888fd5fe864817097995abfbe82466faf1a5abb1a58`.
Compiler 0.8.30, optimizer runs 1. Runtime object length excluding `0x` is
23,762 bytes, leaving 814 bytes below the 24,576-byte EIP-170 limit. This checks
the local artifact, not deployed bytecode or every dependency's provenance.

Compiler storage layout locates `legacyBufferAsset` at slot 68 and appended
`legacyThresholdRaw` at slot 69. The hook source diff against HEAD adds only
this storage field. However HEAD's checked-in layout cache is older than HEAD's
source: it still represents `batchCursor`/`outstandingCrystals` instead of the
current `GachaLib.State`, and names the older Batch type. Comparing cache-array
indices falsely reports many moved fields. Comparing by label shows this
specific stale Gacha representation plus the new threshold field. Do not use
that cache comparison as proof of deployment/upgrade layout compatibility.
Any full baseline-layout claim needs compiler output from baseline source.

## Remaining checks / limits

The metadata call forwards unbounded available gas and copies return data into
dynamic bytes. Ordinary revert/short data is covered; gas exhaustion and large
return-data responses are NOT covered by the passing fuzz tests. Governance
chooses quote tokens, so production reachability/severity must be assessed at
that trust boundary before adding another finding. The comment claiming metadata
cannot brick `setLiveKey` is stronger than the evidence presently supports.

Real native-pool execution, broader rotation lifecycle interaction, and full
baseline/deployed parity remain separate gates. HOOK-01 stays
PATCHED-UNVERIFIED pending reconciliation of those finding-specific checks;
these tests close the listed ordinary metadata/arithmetic/cache questions only.

## Follow-up: hostile metadata gas, HOOK-02 (Low, unfixed)

Same command rerun after adding an actual local `ExhaustingDecimals` contract:
exit 0, **10 passed / 0 failed / 0 skipped**, including the same 512 fuzz cases.
The additional pass is a reproduction, not a safety assertion: its `INVALID`
halt consumes all forwarded metadata-call gas. `setLiveKey` with 200,000 gas
fails, preserving the previous native key and threshold atomically. With
2,000,000 gas the same setter succeeds and records the one-unit fallback.

`setAllowedQuote` is owner-only and `setLiveKey` registry-only. The fixture
impersonates the registry; it does not demonstrate arbitrary token injection
by an ordinary user or execute a production rotation. Classify the demonstrated
bounded-call cost/liveness limitation Low, not an established permanent freeze,
fund loss, or High/Medium production exploit. Leave code unchanged per scope.
If a future lifecycle reproduction establishes an unavoidable operational gas
ceiling or an unprivileged trigger, reassess severity rather than relying on
this classification. Large-return-data behavior remains untested.

Suggested future hardening: cap metadata call gas and copy only one return word,
with explicit fallback behavior and proxy-token compatibility controls. Such a
policy change has not been applied. The production comment's absolute promise
that metadata cannot brick the setter is not supported by this reproduction.
