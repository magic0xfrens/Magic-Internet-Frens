# CauldronHook — full source traversal, final verification pending

All executable bodies and declarations through line 2786 traversed; critical
liquidation narrative rechecked against the executable branches. Source SHA256:
`84c16c0b9967f183db6c25e99fbb82124976f9076e0c316b34bbc6cb5a40f8bf`.
This is source coverage, not final semantic sign-off.

| Functions / surface | Review and remaining obligations |
|---|---|
| constructor, getHookPermissions, _afterInitialize | Explicit owner, immutable manager; address permissions enforced by BaseHook. Initialization requires registry sender and records tracked quote orientation. Allowed-quote admission and actual deployment flags must agree. Legacy DeployCauldron flags currently omit beforeSwap permissions. |
| _liqSweep, _beforeSwap | Normal tracked swaps call engine sweep BEFORE fee/exemption processing. Both supported buy shapes carry signed amount and limit. Exact-output sells rejected. Engine/self-buy/relaunch-close exclusions need cross-lifecycle invariants. Pretrade failed/short sweep fails closed unless explicit owner escape; status2 trade-too-large, other nonzero gas-starved. Low-gas branch queries openCount, but failed/short query permits trade: faulty configured dependency lead, not proven outsider exploit. Public poke is optional, never a normal-operation prerequisite. |
| _afterSwap | Tracked volume and credit, best-effort posttrade sweep, gacha and fee routing. Posttrade failures cannot substitute for pretrade completeness. Untagged player is tx.origin; tagged credit assignment is not trusted-opener restricted, unlike fee exemptions. Check aggregator attribution, exact-output fee direction, callback ordering and gas ceilings. |
| _toUsd, _recordVolume, volume/death/link views, linkVolume | Bad oracle reply maps to zero; multiplication can overflow on extreme quote/factor. Hour ring saturates uint128, gaps clear aged buckets. Sibling linking registry-only, bounded nine-entry adjacency and engine link interlock. Death checker trusted external policy fallback. Need lifecycle tests for volume carry and quote normalization. |
| _maybeLegacyBuyback, legacyBuyStep, fundLegacyBuffer, sweepLegacyReserve | Only-self bounded buy step, transient exclusion, unspent buffer restoration and owed accounting. Mismatched quote buffer moves to reserve. Authorized legacy registry can choose token against global owed counter; generation flush ordering must preserve denomination/backing. Forced ETH and ordinary receive are not automatically buffer credits. |
| _maybePoke | Bounded best-effort progressive-seeder call, distinct from perp poke. No keeper requirement inferred. |
| _takeEthFee, _routeEthFee, _routePerpFee, tax/exemption helpers | Pool take uses transient fee asset; trusted opener required to attribute exemption/surtax to tagged player. Base/tax bounded, policy split validated then fallback. Native-only proposer debt/vault routing and per-asset reserve accounting. Perp fee routes 30/70 with fallback. Need nested callback/transient asset, exact-output direction and conservation verification. |
| release reserves, proposer claim, reserve views | Registry-only release, CEI and checked sends; proposer claim nonReentrant. Asset-specific accounting must match custody across rotation and registry override. Asset-less event name alone is not accounting evidence. |
| forceClosePerps, setLiveKey, threshold cache | Registry close transient flag resets even on catch; verifies empty book afterward. Quote threshold uses oracle conversion then decimals fallback. Funded relaunch/open-book and low-gas caller behavior remain required. |
| registry setup/override, collection/vault/quest/seeder/engine configuration | Registry set once; owner override waits seven days, only native reserve released to old registry. Other assets/legacy registry/openers/perp dependencies need migration coordination. Collection resets epoch/baseline and best-effort badge wiring. Engine replacement here lacks independent open-book guard; owner trust and coordinated engine lifecycle matter. |
| curve/policy, death, guild/proposer, odds/pity/weights, opener/exemption setters | Explicit owner or registry boundaries; configured policies are trusted dependencies. Renounce disabled. Oracle-zero threshold setter does not clear existing oracle. Registry curve update does not clear curve policy. Verify intended policy precedence and supported admin sequences. |
| nftPriceAt, curve position, crystal/progress/cost views | Linear or positive policy curve; minted+outstanding-baseline position. Thirty-item bounded ready/progress, arbitrary-count cost view can consume unbounded gas. Arithmetic and collection-reset consistency remain lifecycle obligations. |
| commit, resolve, nativeGachaStep | Opener-only commit, room includes reservations, at most30 batch, credit debit then push. Public resolve delegates GachaLib under guard; only-self native step commits4/resolves6. Actual failed-mint reservation repair and ownership/epoch carry depend on existing gacha findings/tests, not this source pass alone. |

Existing source-matched findings include oracle/fee/surtax fallback remediations
and FS-perpmark-01. Its ordinary-swap reproduction never calls public poke.
Remaining gates: full swap-shape/quote-orientation integration, solvency and fee
conservation, earned liquidation badge lifecycle, registry migration/relaunch,
all unresolved worksheet leads, full regression, consumer/deployment compatibility,
and fresh ABI/storage/size evidence. No final sign-off.

## Final disposition (2026-09-23)

Final: curve-policy malformed reply = FS-hook-L01 Low (swaps unaffected). Low-gas openCount query and tagged-credit leads are trusted-dependency/gift behaviours (Info). Signed off.
