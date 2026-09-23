# Perp recovery checks — draft, deployment rehearsal pending

This audit uses local EVM tests only. No live transactions or deployment are
performed or authorized by this document. Never assume a deployed vault or
engine includes these source changes: verify chain, address, artifact/compiler,
linked libraries, ownership and runtime parity before proposing any transaction.

## Vault replacement with earned rewards (FS-perpvault-01)

1. Inspect both share supplies and both queue-unit supplies on the CURRENT vault.
   Zero principal counters alone do not establish absence of earned rewards.
2. On the patched candidate, hasStakers also protects settled attributed reward
   claims. Users claim through claimTokYield, then recheck eligibility. An
   operator cannot redirect another user's reward or clear it on their behalf.
3. Positive internal tokRewardOwed may become less than one raw quote unit
   after conversion. If pendingTokYield is zero, verify user epoch against current
   epoch and preview the exact user's claim by local simulation before asking
   them to clear it. Clearing intentionally forfeits that fractional internal
   claim; it sends no tokens and may cost more in gas than its value.
4. The candidate's claimTokYield returns zero and emits ClaimTokYield(user,0)
   for positive internal debt rounded to zero. It clears only that caller's
   claim. Truly absent debt still reverts ZeroAmount. Old deployments may revert
   on zero-rounded claims and must not be advertised as supporting this action.
5. Current StakePanel hides the claim button for zero displayed reward. An
   explicit wallet/contract-call flow is required for this candidate dust case;
   UI support and deployed capability gating are not yet validated. Do not use
   indexer float rounding to infer zero raw payout; use exact on-chain values.
6. Only propose replacement after simulation confirms current hasStakers false
   and the replacement's engine/registry wiring and deployment identity match.
   Unattributed yield/engine pot residue alone is not a blocking user liability.

Evidence: R23_VaultReplacementYield (production engine/stub registry/manager),
R23_VaultRewardScale (modeled conversion), source-matched surface/size checks.
Pending: consumer UI/capability checks, actual requote rehearsal, stateful debt
sequence (prepared), and deployed-code identity. This is not a completed runbook
rehearsal or authorization to operate deployed contracts.

## Malformed mark source (FS-perpmark-01)

Normal operation relies on production hook beforeSwap, not a poke keeper.
BeforeSwap invokes the engine's observation/funding path internally and requires
its sweep to be available. Candidate validates the full returned tick word
before recording it; invalid values fall back to primary-pool ticks.

For an already-poisoned deployed ring, do not assume merely changing the source
immediately repairs TWAP history. Reconfiguration/recovery must be simulated
against the actual ring, positions and pool with no forced storage changes.
Do not enable sweepFailOpen as routine recovery: it explicitly permits trades
without the protective sweep and can expose PLV to bad debt. No such action was
performed. Recovery timing and actual-ring rehabilitation remain an open test.
