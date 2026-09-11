# Magic Internet Frens — Security Analysis

## Known Risks & Mitigations

### 1. Oracle Manipulation
**Risk**: Attackers manipulate BTC/USD price to trigger unfair liquidations or borrow at inflated collateral values.

**Mitigations**:
- 30-minute TWAP oracle (not spot price)
- Admin fallback with governance timelock
- Oracle staleness check: revert if last update > 1 hour ago
- Phase 2: multiple oracle sources with median

### 2. cook() Function Exploits (MIM Vulnerability)
**Risk**: Abracadabra's cook() was exploited 3 times — action ordering bypass, solvency check skip, and action ID 0 undefined handler.

**Mitigations**:
- Solvency check ALWAYS runs at end of cook() — flag is immutable
- No action ID 0 or undefined action handlers
- All action IDs explicitly enumerated
- Reentrancy guard on cook()
- Each action validated independently before execution

### 3. Liquidation Cascades
**Risk**: Rapid BTC price drop triggers mass liquidations → forced selling → further price drop.

**Mitigations**:
- Conservative 75% LTV (5% buffer before 80% liquidation threshold)
- NFT tier-based liquidation grace periods (1-3 blocks)
- 10K NFT cap limits total protocol positions
- Per-tier borrow caps limit individual exposure

### 4. Flash Loan Governance Attack
**Risk**: Attacker borrows FREN, stakes for sFREN, votes, unstakes in same block.

**Mitigations**:
- 24-hour unstaking timelock
- Voting power snapshot at proposal creation
- No flash-loan accessible staking

### 5. Reentrancy
**Risk**: Malicious contract calls back into protocol during state changes.

**Mitigations**:
- Reentrancy guard on all external-facing functions
- Checks-effects-interactions pattern throughout
- State updates before external calls

### 6. Integer Overflow/Underflow
**Risk**: Math operations produce unexpected results leading to incorrect LTV calculations or fund loss.

**Mitigations**:
- All arithmetic uses safe math with overflow protection
- Fixed-point math with explicit precision handling
- All amounts validated against reasonable bounds

### 7. NFT Gate Bypass
**Risk**: Attacker interacts with Cauldron without holding MiFREN NFT.

**Mitigations**:
- NFT ownership verified on every Cauldron call (not just first interaction)
- NFT ID bound to position — cannot transfer while debt open
- Position mapped to specific NFT ID, not just holder address

## Audit Checklist

- [ ] All external functions have reentrancy guard
- [ ] cook() solvency check is immutable and always executes
- [ ] Oracle staleness check prevents stale price usage
- [ ] NFT gate check on every Cauldron interaction
- [ ] Integer overflow protection on all math operations
- [ ] Proper access control on mint/burn authorities
- [ ] No uninitialized storage slots
- [ ] Event emissions for all state changes
- [ ] Emergency pause mechanism functional
- [ ] Admin functions protected by timelock

## Known Limitations (V1)

1. Oracle is admin-set (centralized trust assumption until TWAP available)
2. No formal verification of contract logic
3. OP_NET is a newer platform — ecosystem tooling is evolving
4. No MEV protection on Bitcoin L1 (block times help — 10 min vs 12s)
5. Single Cauldron type (BTC only) — no multi-collateral in V1
