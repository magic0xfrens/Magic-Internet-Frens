# Dividend callback evidence correction — 2026-09-19

## Outcome

The previously reported T9b reentrancy "control" is a successful vulnerability
reproduction, not a defense. Restore historical Z-13 as Low NFT-02 and leave
production code unchanged under the owner's Low/Informational exception.
This is not a newly established permissionless production exploit.

## Source and assertions inspected

- `contracts/solidity/cauldron/MiFrensDividend.sol`: `castSpell` and `castMany`
  call `_castSpell` without the inherited reentrancy guard. In its fresh-join
  branch, `_collectEnchantFee` runs before `activeShares` increments and
  `enchantedBy` is written. That collection calls token `transferFrom`,
  `approve`, and the registry's `donateToReserve`.
- `contracts/solidity/test/attacks/T9b_DividendConservation.t.sol`:
  `test_F_CastSpellReentrancyDoubleCountsActiveShares` substitutes a malicious
  `ReentrantRegistry`, wired by impersonating the authorized treasury. The
  registry calls back through the NFT-owning `Holder`, satisfying the owner
  check on a nested cast of the same ID.
- The assertions explicitly require two active shares for one NFT, one phantom
  share after that NFT transfers away, and a subsequent sole real participant
  entitled to only 1 ETH of a 2 ETH deposit. Passing these assertions confirms
  the accounting defect under the fixture's dependency substitution.
- The other two T9b tests are basket/ETH conservation controls. Do not count all
  three passes as proof that reentrancy is prevented.

## Reachability and severity boundary

`setRegistry` is treasury-only and one-time once nonzero. The production
`CauldronToken` inherits ordinary OpenZeppelin ERC20 transfers, with no custom
receiver callbacks. Production `RedemptionExt.donateToReserve` is guarded and
routes through `_pullGrow` and `PoolOps.addToReserve` into PositionManager.
The reviewed direct path does not contain the fixture's arbitrary Holder call.
This is not proof that every downstream hook/callback combination is safe;
that broader callback reachability review remains open.

The older `audit/FINAL_BLIND_2026-09-11/FINAL_AUDIT_FULLSWEEP.md`, Z-13,
already classifies this as Low defense-in-depth requiring a protocol-controlled
reentering registry or token. Preserve that conditional classification, not an
unjustified High/Medium promotion or rejection. If a production, unprivileged
callback path is demonstrated, reassess severity and remediate accordingly.

## Remediation guidance (not applied)

Review guards on both casting entry points together with ownership changes
during fee collection. A guard alone does not establish ownership stability:
a callback could transfer the NFT without reentering a cast. Any future fix
needs same-ID/batch reentry, transfer-during-fee, failed-fee rollback, normal
paid/free casting and ETH/ERC20 conservation regressions. Do not blindly move
activation before fee collection: that changes the dividend accrual window.

No bytecode, storage layout, ABI, deployment, or production state changed in
this evidence correction. Historical test pass counts are retained as command
outcomes, with their actual assertion semantics made explicit.

Fresh execution from `contracts/solidity`:
`FOUNDRY_PROFILE=cauldron forge test --offline --threads 1 --match-contract T9bDividendConservation -vv`
returned exit 0, 3 passed / 0 failed / 0 skipped, with compilation skipped
(unchanged source). The phantom-share reproduction passed at 1,386,286 gas;
the two conservation controls also passed. No RPC or live transactions used.
