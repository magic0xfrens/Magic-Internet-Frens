# API and treasury-rotation UI review

Date: 2026-09-18  
Scope: first-party `api/` handlers, `src/hooks/useTreasuryRotation.ts`, and its direct `TreasuryRotation` consumer in `src/components/cauldron/TreasuryRotation.tsx`. `TheCauldron.tsx` was checked only to confirm that it mounts this consumer. No live requests, builds, tests, or secret-value inspection were performed.

## Result

Two concrete Medium UI liveness defects are reachable in the treasury-rotation flow. The API review found one concrete unsafe diagnostic disclosure sink whose credential impact is deployment/error-shape dependent, plus several Low resource-hardening gaps. None of these paths bypasses an on-chain custody check: rotation writes still pass through the registry, governor allowance, curated venue, oracle floor, and caller `minOut` checks.

## Reviewed API inventory

| Handler | Trust boundary and intended authority | Principal bounds observed |
|---|---|---|
| `api/brand.ts` | Public GET; POST requires an allowlisted EIP-191 signer. Origin checking is browser defense-in-depth, not authorization. | Generation and image sizes bounded; signer set and row cap fail closed; parameterized SQL. |
| `api/fren-ask.ts` | Public, untrusted prompt input; model output has no write/custody authority. | POST only; question/history/output bounded; per-warm-instance IP throttle; provider model chain finite. |
| `api/fren-teach.ts` | Shared-secret administrator can add/delete authoritative prompt corrections. | Fails closed without secret; fixed-width secret comparison; bounded correction strings and GET rows; failed-auth throttle is per warm instance. |
| `api/x-token.ts` | Public OAuth PKCE exchange proxy holding X client credentials; returns the resulting access token to the initiating client by design. | POST only; exact redirect allowlist; per-warm-instance IP throttle. PKCE possession remains required. |
| `api/cauldron/creature.ts` | Public metadata renderer; only manifest/environment-allowlisted collection addresses are read. | Two chain reads maximum on the normal revealed path, but token syntax/size and HTTP method are not strictly bounded. |
| `api/cauldron/liquidatoor.ts` | Public badge renderer; only allowlisted collection addresses are read. | One bounded stats read, but token syntax/size and HTTP method are not strictly bounded. |
| `api/cauldron/unrevealed.ts` | Public constant metadata with no input-dependent work. | Constant response, immutable cache. |

`api/CANDLES_SETUP.md` is documentation, not an executable handler.

## Verified defects

### UI-01 — Active native-destination envelope is classified as idle (Medium, remediated)

**Evidence.** `TreasuryGovernor.allowance()` explicitly documents and implements `remainingBps` as the liveness flag because `address(0)` is a legitimate native-asset destination (`TreasuryGovernor.sol:782-792,825-827`). The hook instead assigns `idle: allow[0] === NATIVE_QUOTE` while independently calculating `slicesLeft` from `allow[1]` (`useTreasuryRotation.ts:296-305,345-360`).

**Reachability.** After governance executes a still-funded envelope whose destination is native ETH, `allowance()` returns `(address(0), nonzero)`. The hook sets `env.idle = true`. The direct consumer takes the proposal branch instead of the approved-envelope branch (`TreasuryRotation.tsx:360-364,531-536,630-733`), so it does not expose the permissionless slice action even though allowance remains.

**Impact/severity.** The canonical UI cannot carry out a voted return-to-native mandate. The envelope may expire and the governor cooldown can delay replacement. This is Medium availability/governance liveness, not direct loss of custody: another caller can invoke the public on-chain entrypoint, and the contract recognizes liveness by the nonzero remainder.

**Smallest remediation.** Derive `idle` solely from the remainder: `allow[1] === 0`. Keep `quote` from `envelope[0]`/`allow[0]` as an asset value, never a sentinel.

**Required regression.** Mock a successful load where `allowance()` returns `[NATIVE_QUOTE, 2500]`, `envelope()` is active with native quote, and assert `env.idle === false`, `env.slicesLeft === 1`, and that the consumer renders the approved-envelope slice control rather than the proposal picker. Add the counterpart `[NATIVE_QUOTE, 0] => idle` to prove absence and native destination are distinguished.

**Remediation evidence.** `src/lib/treasuryRotation.ts:isIdleRotationAllowance` now derives liveness solely from `remainingBps`, and `useTreasuryRotation.ts` calls that helper when normalizing the governor result. `scripts/test-treasury-rotation.mjs` covers native/nonzero and zero-remainder allowance tuples. This is deterministic helper coverage of the production branch; no browser-render test was run.

### UI-02 — Route construction ignores the selected source leg (Medium, remediated)

**Evidence.** The contract derives `fromQuote` from `generationPoolKey.currency0` for leg 0 or `generationLegs[fromLeg-1].quote` for a secondary leg (`RedemptionExt.sol:339-381`) and passes that value to `QuoteRotator.swapOnce` (`RedemptionExt.sol:417-433`). The rotator requires the route currencies to equal exactly `{fromQuote,toQuote}` (`QuoteRotator.sol:335-359,765-773`). The component lets the caller select `fromLeg`, but constructs `route` from generation-wide `liveQuote` and `dest`, not `legs[fromLeg].quote` and `dest` (`TreasuryRotation.tsx:316-319,336-378,688-720`). Preview and execution both reuse that incorrect route (`TreasuryRotation.tsx:393-401,483-499`).

**Reachability.** Once rotation creates a secondary leg and the selected leg asset differs from `liveQuote`, the UI either (a) supplies a pool key for the wrong pair and receives `NoRoute`, or (b) concludes there is no route because `liveQuote === dest`, even when the selected leg differs from the destination. For example, after denomination moves to USDG while residual ETH remains, selecting the ETH leg for an ETH-to-USDG rebalance is a valid on-chain source/destination but the UI compares USDG to USDG and constructs no route.

**Impact/severity.** Valid leg rebalance/merge operations exposed by the UI are unreachable or revert, frustrating an approved mandate and potentially letting it expire. This is Medium UI/governance liveness. It cannot redirect assets: `_routeMatches`, venue allowlisting, and the oracle/slippage floor reject a mismatched or adversarial route.

**Smallest remediation.** Construct the route from `legs[fromLeg]?.quote` (falling back to the known primary quote only while legs are unavailable) and `dest`. Reset or validate `fromLeg` whenever loaded legs or destination change so a selected source can never equal the destination. Venue labels should likewise use the selected source asset.

**Required regressions.** Extract/test a pure route builder with three distinct assets: denomination A, selected-leg B, destination C must return the sorted B/C key, never A/C. Also assert B destination B returns no route, and denomination C with selected B/destination C still returns B/C. At component level, select a non-primary leg and assert both `checkVenue` and `quoteSlice(..., fromLeg)` receive that leg's pair.

**Remediation evidence.** `routeForRotationLeg` now resolves the source with `leg.index === fromLeg`, accepts native as a destination, and fails closed for a missing leg or self-route. The component uses that helper for venue checking, simulation, and execution; it repairs stale/self selections to the first executable leg and disables execution until the route, curated venue, and fresh quote all exist. Deterministic tests cover the residual launch leg after requote, a non-contiguous secondary-leg index, native return, self-route, and disappeared leg. No browser-render test was run.

### API-01 — Public creature metadata returned raw RPC error text (conditionally Medium, remediated)

**Evidence.** Before remediation, any exception from either chain read was copied from `Error.message`, truncated, and returned publicly in `art_unavailable` (`api/cauldron/creature.ts:203-241`). A local, mocked-transport regression using the repository's installed viem proved that an error containing a synthetic credential-bearing RPC URL reached the actual handler response. No network request or real secret was used, and this does not establish that the deployed RPC URL contains a credential or that a live credential leaked.

**Reachability.** An RPC outage, invalid/oversized token id, provider rejection, or transport error reaches the catch and public JSON response. No authentication is required.

**Impact/severity.** The disclosure sink is verified; credential disclosure is conditional. If an RPC endpoint embeds an API key in the error string, this is Medium secret exposure and can lead to quota theft. With sanitized provider errors it is Low operational-information disclosure.

**Smallest remediation.** Return a fixed public reason such as `chain read failed`; record a redacted/categorized server-side diagnostic if operational logging is needed. Never serialize provider exceptions.

**Required regression.** Stub `readContract` to reject with `Error("HTTP failure: https://provider.example/SECRET_KEY")`; assert the response contains the fixed category and contains neither `SECRET_KEY` nor the provider URL. `tests/api/creature-errors.test.ts` now performs that check against the actual handler, alongside the non-error metadata path.

**Remediation evidence.** The public field now uses a fixed failure reason rather than the caught exception. The isolated API suite passes both cases with a mocked viem transport. The finding is conditionally Medium when a configured provider URL carries a credential; this review makes no claim of a deployed or historical live-secret disclosure.

## Resource and input hardening (Low / defense in depth)

- `creature.ts` and `liquidatoor.ts` do not restrict the HTTP method. POST requests can invoke origin work while bypassing normal GET caching. Both derive ids by deleting every non-digit character (`creature.ts:189-199`; `liquidatoor.ts:174-207`), so many different URLs alias one token and defeat cache reuse. Very long decimal values also reach `BigInt` and, for creature metadata, RPC encoding. Require GET/HEAD, accept only canonical `^(0|[1-9][0-9]{0,77})$`, then reject values above `uint256.max`. Regression: `abc12`, `0012`, oversized decimal, and POST must fail before any RPC read; canonical `12` must read once.
- `brand.ts` rejects unknown query keys but accepts multiple textual encodings of one numeric generation (`1`, `01`, `1e0`, whitespace), creating distinct cache keys for the same Neon read (`brand.ts:119-133`). Canonical decimal validation before `Number` closes the remaining cache-key fanout. `website` is signer-authorized but lacks a local length bound; apply a modest URL/string cap for database/response hygiene.
- `fren-ask.ts` and `x-token.ts` rely on per-warm-instance maps, so their throttles are not distributed controls. Both external provider flows lack explicit abort timeouts. `fren-ask` can attempt a finite fallback chain and `x-token` accepts unbounded code/verifier strings up to platform request limits. Edge/WAF limits, short `AbortSignal.timeout` values, and protocol-appropriate input caps would bound billed concurrency. This is not an authentication bypass: X still requires an allowlisted redirect and possession of a valid code/verifier.
- String-body `JSON.parse` in `brand.ts`, `fren-ask.ts`, and `fren-teach.ts` is not consistently guarded. Malformed JSON can become a platform 500 rather than a controlled 400. This is robustness, not custody impact.
- `fren-teach.ts` intentionally places authenticated corrections into the system prompt. The shared administrator secret is therefore a high-trust content-integrity boundary. Its failure throttle is only supplemental; rotating and protecting that secret and enforcing a distributed edge limit remain operational requirements.

## Rejected concerns / intentional boundaries

- Public metadata reads and wildcard CORS on the three metadata endpoints are intentional; collection addresses are allowlisted where caller selection exists. `unrevealed.ts` performs no input-dependent work.
- `brand.ts` does not rely on Origin for authority. A non-browser caller can omit Origin, but still needs a fresh signature from an allowlisted signer; timestamp freshness and monotonic row timestamps limit replay/rollback.
- Returning the X access token is intrinsic to this PKCE proxy's browser flow. The handler does not return the client secret or refresh token. Lack of server-side state binding is not by itself account takeover because redemption still requires the authorization code and its verifier, and the redirect must match the configured allowlist.
- Prompt injection into `fren-ask.ts` does not cross a privileged tool boundary: the model can only return text. Corrections are different by design and require the teaching administrator secret.
- The UI's simulated quote uses `minOut = 0` only for a read-only preview. Execution derives a nonzero user floor from the fresh result, while the rotator independently enforces its oracle floor. This is not an unbounded execution path.
- Stale or failed frontend reads can misrender state, but contract writes remain authoritative and fail closed. No frontend finding above permits bypass of governor allowance, source-leg identity, venue curation, or asset conservation checks.

## Priority

1. Keep the new UI-01/UI-02 deterministic suite in CI; add a browser component test when a frontend harness is introduced.
2. Sanitize API-01 regardless of current provider error formatting; it is a small change at a public boundary.
3. Apply canonical metadata input/method checks and external-call timeouts as resource hardening.

## Verification performed after remediation

- `npm run test:treasury-rotation` — 6/6 passed.
- `npm test` — runs 19 Node tests plus 2 isolated API Vitest cases; all 21 passed.
- `npm run type-check` — passed.
- No browser test, Forge test, Vite build, network request, or dependency installation was run.
