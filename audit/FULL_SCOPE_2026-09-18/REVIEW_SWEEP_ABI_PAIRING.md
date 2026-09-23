# Sweep return-protocol pairing

2026-09-21, HEAD `83ef97b` plus the local fail-closed hook patch.
Status: DERIVED compatibility risk; no deployed mismatch attested.

`PerpEngine.sweepLiquidations` (`cauldron/PerpEngine.sol:1129`) now returns
`uint8 status`: 0 is complete, 1 is gas refusal, 2 is size refusal. The current
`IPerpEngineLiq` declaration (`CauldronHook.sol:60`) and `_liqSweep` decoder
(`CauldronHook.sol:837`) agree. The earlier implementation returned a boolean
with true meaning complete. Return types do not change the call selector.

| Engine response | Current status decoder | Earlier boolean decoder |
|---|---|---|
| 0 | complete | incomplete |
| 1 | gas refusal | complete |
| 2 | size refusal | invalid boolean ABI value |

This is not wire-compatible despite identical input selectors. In particular,
an old engine's incomplete result can be accepted by the new hook, and a new
engine's gas refusal can be accepted by the old hook. The exact older hook
failure handling must be checked against its bytecode before characterizing any
deployed impact. The preserved local snapshot
`/private/tmp/mifrens-audit-20260919-final/contracts/solidity/CauldronHook.sol:820`
uses `!abi.decode(out, (bool))` to refuse incomplete work, confirming the older
source-side interpretation in this table (not deployed-bytecode identity).

`DeployPerp.run` (`deploy/DeployPerp.s.sol:69`) reads an existing hook address
from configuration, constructs a fresh engine at line 83, then calls
`setPerpEngine` at line 94. No sweep-protocol version check occurs before that
wiring. `CauldronHook.setPerpEngine` at line 2294 permits registry/owner rewiring;
it is not one-shot. Deployment authorization is required; this is not an
unprivileged replacement path.

Repository search found no additional decoder in `src`, `scripts`,
`contracts/abis`, `api`, `indexer`, or `deployments` (only a documentation call
graph reference). This is not proof of external-client compatibility.

Required acceptance: use a matched hook/engine pair, test both mismatch
directions with a minimal old-protocol fixture, and prevent deployment wiring
to an incompatible hook before broadcasting. A version marker/handshake or
explicit runtime-bytecode compatibility check needs implementation and tests;
do not assume a successful call to an unchanged selector provides that proof.
