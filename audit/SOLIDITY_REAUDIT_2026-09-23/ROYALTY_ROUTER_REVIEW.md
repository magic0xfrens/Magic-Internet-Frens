# RoyaltyRouter — source traversal

Read all five implementation bodies (constructor, receive, sweep, _balanceOf,
_safeTransfer); no production changes. Public getters require compiler mapping
separately.

- Constructor rejects zero hook, pins hook and ERC20 sink; zero sink uses hook.
  Does not verify code or downstream adopt/recovery support.
- receive ignores zero value; under 40000 gas retains ETH, otherwise low-level
  forwards current msg.value to immutable hook; failure leaves balance for sweep.
  Forward uses nearly all gas, so universal sale-liveness against arbitrary
  gas-burning hooks is not proved. Actual production hook boundary is pending.
- sweep(native) permissionlessly forwards full balance to the same fixed hook;
  rejects empty balance, propagates hook failure so funds remain recoverable.
- sweep(ERC20) reads balance, checked transfer to immutable sink, then advisory
  typed adopt call. Successful malformed adopt return data can bypass catch;
  assess only after establishing a reachable production sink/configuration.
  Untrusted token semantics may misreport delivery; caller chooses asset, never
  destination. No accounting debt or cross-asset counters in this router.
- _balanceOf requires successful call and >=32 return bytes; dynamic returndata
  is not bounded. _safeTransfer accepts no return or ABI true, rejects false;
  assumes token's claimed transfer corresponds to delivered value. No lock;
  callback analysis must distinguish router-owned balances from token lies.

Existing K4a tests deploy factory/collection/router with synthetic hook/dividend
and token, asserting fixed-sink ERC20 delivery/adoption and stipend ETH retention
then sweep. X1e tests use production hook with manager stub across quote changes;
they are not full V4 swap or real dividend integration. `royalty-routing-review`
is running; result pending. No confirmed new finding.
