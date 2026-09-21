# PERP-02 production engine/vault boundary — 2026-09-20

Added `contracts/solidity/test/audit_full_scope/PerpVaultEngineWriteoff.t.sol`.
Both PerpEngine and PerpVault are production contracts, not derived harnesses.
Registry quote changes and PoolManager prices remain stubs; token balances and
allowances are implemented by the existing MockToken. No target storage is
written. Hook impersonation models the authorized fee-delivery boundary.

Command, from `contracts/solidity`:
`FOUNDRY_PROFILE=cauldron forge test --offline --threads 1 --match-contract PerpVaultEngineWriteoffTest -vv`

Exit 0: **1 passed, 0 failed, 0 skipped**, test gas 934,127. Compilation took
42.82s. Compiler warnings include existing unchecked calls and oversized test/
deployment harness initcode; this test is not deployment-size evidence.

## Assertions reached

1. Alice deposits 1,000 tokens through the real vault into the real engine.
2. Production `creditPerpFeeToken` receives 5 ETH from the modeled hook role.
3. Actual `syncGeneration` changes quote to the fixture ERC20 and back to native:
   pot becomes zero, cumulative accrual stays unchanged, treasury receives the
   exact retired native reward amount.
4. Another 1 ETH accrues before Bob's 9,000-token deposit synchronizes the vault.
   Epoch is one, Alice's backed pending reward is approximately 1 ETH, and
   pulled/write-off watermark plus backed pot equals cumulative credits.
5. A second quote round trip retires that pot through the real engine. Another
   10 ETH accrues. Actual claims pay Alice approximately 1 ETH and Bob 9 ETH,
   matching their native balance increases. Combined payout cannot exceed
   10 ETH; epoch is two.
6. Engine token balance and reported token assets both remain 10,000 tokens.

This closes the specific uncertainty that the previous mock engine's pot reset,
unchanged cumulative credits and vault payout interface might differ from
production `syncGeneration`. It does NOT establish real governance voting,
treasury LP migration, nonnative reward allocation, relaunch token migration,
open-position settlement, queued principal, or full V4/deployment parity.
The fixture uses no open positions and the same generation throughout.

The previously existing repeated-writeoff model/fuzz tests remain useful
additional coverage, but were not rerun in this command. No production patch
was needed for this boundary test; the existing watermark remediation held.

## Follow-up: pending previews and reverse claim order

The same command now passes **2/2, zero failed/skipped**, including 256 fuzz
cases for `testFuzz_ProductionWriteoffPreviewAndReverseClaims`. Rewards vary
from 1e12 wei through 5 ETH. After the second actual engine write-off, both
pending views return zero before fresh accrual. After fresh accrual, previews
match the 10%/90% split within a share-derived rounding bound. Bob claims first;
Alice's preview remains unchanged, and both actual payments equal their prior
previews. Final pot equals fresh accrual minus payouts; the cumulative watermark
identity and 10,000-token principal also hold. This is additional production
engine/vault boundary evidence, not a real registry/V4 rotation rehearsal.

## Reverting claim accounting — 2026-09-21

Same command now passes **3/3, zero failed/skipped**, including 256 fuzz cases.
`test_ZeroAndDuplicateClaimsCannotAdvanceWriteoffAccounting` verifies that a
zero-entitlement claim after write-off reverts with `ZeroAmount` and rolls back
the tentative epoch/watermark synchronization. After new yield arrives, the next
claim succeeds and advances the epoch exactly once. A duplicate claim reverts
without changing the epoch, watermark, engine pot, user balance or zero pending
preview. This tests zero/duplicate rejection, NOT a hostile receiver rejecting
an otherwise nonzero payment. That separate external-send failure path remains
outside these assertions. No production code change was required.

## Nonzero payment rejection — 2026-09-21

The next run passes **4/4, zero failed/skipped**, retaining the 256 fuzz cases.
An actual `RejectingYieldStaker` deposits through the vault, then rejects ETH
after two production-engine write-offs and fresh accrual. Claim reverts with
`PerpEngine.EthSend`; engine pot, vault watermark, tentative epoch advancement,
pending entitlement and recipient balance all roll back. Bob can independently
claim. Once the receiver accepts ETH, its original pending reward remains
payable exactly once. Final balances, epoch and cumulative watermark identity
are asserted. This closes the prior nonzero-send rejection gap for native ETH;
ERC20 failure modes and callback reentrancy are separate properties.
