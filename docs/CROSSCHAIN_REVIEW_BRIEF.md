# Review brief — cross-chain genesis plan

Hand this, plus `docs/CROSSCHAIN_GENESIS_PLAN.md`, to a reviewer.

**Nothing is built.** This is a design review, which is the cheapest possible
place to catch an error — a flaw found here costs a paragraph; the same flaw
found after ignition costs the launch, because ignition is one-shot and the hook
that anchors the protocol is unpatchable.

---

## What to review

| doc | what it is |
|---|---|
| `docs/CROSSCHAIN_GENESIS_PLAN.md` | the design. **Primary target.** |
| `audit/R46_2026-09-16/PERP_AUDIT.md` | perp audit — context for how this codebase fails |
| `audit/R46_2026-09-16/R46_READINESS.md` | R46 verdict, incl. three retracted findings |

---

## The claims most likely to be wrong

Ordered by *cost if wrong*, not by confidence. **Each one is a claim I made; none
should be taken on trust.**

### 1. The `igniter` must hold an ALIASED address — VERIFIED as a real constraint

`CauldronRegistry.sol:728`:
```solidity
if (msg.sender != owner() && msg.sender != igniter) revert NotAdmin();
```
Ignition arrives via an Arbitrum retryable ticket, so `msg.sender` on 4663 is
`alias(GenesisOutbox)` = L1 address + `0x1111000000000000000000000000000000001111`
— **not** the outbox's own address.

**If `igniter` is set to the raw mainnet address, ignition reverts on arrival,
after ~6.89 ETH has already crossed.** Recoverable only by manual retryable
redemption within 7 days.

*Reviewer: confirm the alias offset against Arbitrum's current spec, and confirm
`igniter` is settable after deployment — if it is immutable, the deploy order
becomes load-bearing.*

### 2. Every LayerZero fee number is an ESTIMATE, and they are ~90% of the cost

`$0.50–$2.50` per message is a guessed range, not a measurement. The entire
cost table in §7 and the architecture recommendation both ride on it.

*Reviewer: this is the single highest-value thing to check. A `quote()` call
against a trivial deployed OApp settles it in an afternoon. If the real fee is
5–10× my estimate, design C's per-holder `lock()` becomes unaffordable and the
answer reverts to a soulbound-only mirror.*

### 3. LayerZero on testnet 46630 — UNCONFIRMED

I found LayerZero's **mainnet** deployment page for 4663. I did **not** confirm a
testnet endpoint on 46630. If none exists, the messaging leg cannot be rehearsed
end-to-end before mainnet, which materially changes the risk of step 4.

### 4. Gas estimates are reasoned, not measured

`200–270k` for lock/sync comes from reasoning that `MiFrensGenesis` is
`ERC721Votes`, so a transfer writes vote checkpoints for both parties plus the
`genesisBalanceOf` SSTORE in `_update`. **Nobody has run it.**

### 5. "Exactly one side transferable" — the invariant everything rests on

Check it through **every** transition *and mid-transition*, especially:
- `unlock()` must freeze the mirror **before** sending the release message. If it
  freezes after, the mirror could be sold while the vault releases to its former
  owner — **a double-spend, which is the one thing this design exists to prevent.**
- What happens to a LOCKED fren that is floor-redeemed? (Plan says: mainnet token
  stays in the vault, treasury holds the mirror, buyer at `2F` can unlock. Verify
  that chain holds.)

### 6. The dividends-vs-floor distinction

I argued dividends are safe to claim from a freely-tradeable mainnet fren because
they are a *flow* a rational seller claims before selling, while the floor is a
*stock* whose redemption destroys the backing.

*Reviewer: is there a case where accrued dividends are large enough to be worth
stealing in the sync gap? If so the argument fails and dividends need the same
gate as the floor.*

---

## Method — what actually caught errors this week

Three of my own findings were **retracted** in the last 48 hours. All three were
confident and wrong in the same way:

| finding | what happened |
|---|---|
| rotation "Critical" | read a **dirty worktree** and attributed it to committed code |
| round-trip inversion | two sessions agreed on a reading; **execution refuted it** |
| F-3 throttle gate | recommended a fix that **already existed**, pre-dating the run |

So:

1. **Verify each claim independently — do not reason from mine.** Two readings
   agreeing is not evidence; it usually means both made the same omission.
2. **`git worktree add <commit>` before characterising committed behaviour.** One
   retraction was pure dirty-tree contamination.
3. **`git log -S '<exact code>'` before reporting anything as missing.** That is
   what exposed F-3 — the gate had been there the whole time.
4. **A green test proves only what it asserts.** `S08_E` sat red for the whole
   run asserting behaviour three later fixes had deliberately replaced. A stale
   assertion looks like standing debt, not like a question nobody re-asked.

---

## Constraints a reviewer must not break

- **EIP-170 is at the wall.** `CauldronRegistry` has **8 bytes** free;
  `PerpEngine` 238; `CauldronHook` 598. `CauldronBase` is inherited by the
  registry, so **one new public getter there blows it.** All new contracts must
  stand alone.
- **`TreasuryGovernor`, `RedemptionExt`, `MiFrensDividend` should need no
  changes** — they read `IVotes721`/`IERC721`, so the mirror is a constructor
  argument. If a review concludes otherwise, that is a finding.
- **Quorum must be measured against the same trace the votes come from**
  (`getPastTotalSupply`). Getting this wrong makes governance either unreachable
  or capturable — R46 investigated exactly this trap.

---

## Open questions the plan does not answer

1. `minOut` unmet on the mainnet-initiated redeem: return custody, or hold the
   claim open?
2. Does burn-for-iteration-tokens exist at all? It conflicts with the OG floor
   ratchet, which deliberately does **not** burn.
3. DVN set and thresholds (plan recommends ≥2 for rights, ≥3 for vault release,
   never the default single-DVN config).
4. Who funds the ignition roster — presale proceeds or deployer?
5. Is `syncOwner` permissionless-and-buyer-pays, or is there a funded keeper?
