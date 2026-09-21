# Perp quote transfer boundary — 2026-09-21

Current observed HEAD: `6ec1f8e0816c508a9c2f532b212cebd9ca0230ae`.
This differs from the earlier audit baseline. No commit/push was performed in
this continuation. Preserve the changed source; prior execution results are
historical until source/artifact freshness is revalidated.

Inspected current PerpEngine `_quoteIsNative`, `_pullQuote`, `_pushQuote` and
`_safeTransfer`, and PerpSwapLib `tryTransferFrom` / `tryTransfer`.

- Native input requires msg.value exactly equal to amount. ERC20 input rejects
  any msg.value and delegates the transfer call to the linked library, retaining
  the engine's address/allowance context. The helper itself credits no counters.
- Token return false produces BadParam in the checked caller. A reverting token
  yields false; empty successful return data is accepted. Malformed nonempty
  data can revert during bool decoding rather than return false.
- Native output returns early at zero amount; otherwise it forwards value to
  the recipient and reverts EthSend on failure. ERC20 output uses the checked
  transfer helper. Entry-point guards and effect ordering still determine
  callback safety; the helper is not itself a reentrancy proof.
- No received-balance delta or token-code existence check is present in these
  token wrappers. This is not independently a demonstrated attack: actual quote
  admission and token assumptions must be reviewed before assigning severity.
  Do not equate a true/empty ERC20 return with proof of received backing for a
  fee-on-transfer, dishonest or codeless asset.

Removed two fabricated declaration self-call edges from `perp.json` and corrected
the external library edge to delegatecall scope. Updated Markdown counts.
The native rejecting-staker regression previously exercised rollback through
this payout chain, but has not been rerun on the newly observed HEAD. No
production fix, new severity assignment, or broad coverage closure claimed.
