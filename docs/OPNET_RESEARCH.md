# OP_NET Research Notes

## Overview

OP_NET is a smart contract execution layer on Bitcoin L1. Contracts are written in AssemblyScript (WASM) and deployed directly to Bitcoin.

## Token Standards

### OP_20 (Fungible Token)
- Equivalent to ERC-20 on Ethereum
- Standard methods: `name()`, `symbol()`, `decimals()`, `totalSupply()`, `balanceOf(address)`, `transfer(to, amount)`, `approve(spender, amount)`, `transferFrom(from, to, amount)`, `allowance(owner, spender)`
- Events: `Transfer(from, to, amount)`, `Approval(owner, spender, amount)`
- Mint/burn authority pattern available for protocol-controlled tokens

### OP_721 (Non-Fungible Token)
- Equivalent to ERC-721 on Ethereum
- Standard methods: `ownerOf(tokenId)`, `balanceOf(address)`, `transferFrom(from, to, tokenId)`, `approve(to, tokenId)`, `getApproved(tokenId)`, `setApprovalForAll(operator, approved)`, `isApprovedForAll(owner, operator)`
- Metadata: `tokenURI(tokenId)` — can store on-chain
- Enumerable extension: `totalSupply()`, `tokenByIndex(index)`, `tokenOfOwnerByIndex(owner, index)`

## Contract Architecture on OP_NET

- **Language**: AssemblyScript (compiles to WASM)
- **State storage**: Key-value pattern with typed maps
- **Cross-contract calls**: Supported — contracts can call other contracts atomically
- **Transaction model**: Bitcoin transactions wrap OP_NET execution
- **Block time**: ~10 minutes (Bitcoin L1)
- **Gas model**: Measured in satoshis, based on computational complexity

## Key Differences from EVM

| Feature | EVM (Ethereum) | OP_NET (Bitcoin) |
|---------|---------------|-----------------|
| Language | Solidity | AssemblyScript |
| Block time | ~12 seconds | ~10 minutes |
| Gas unit | gwei | satoshis |
| Native token | ETH (18 dec) | BTC (8 dec / satoshis) |
| Token decimals | Usually 18 | Usually 18 (tokens), 8 (BTC) |
| VM | EVM | WASM |
| State | Account-based | UTXO + State overlay |

## Deployment Pattern

```typescript
// TODO: OP_NET SDK — deployment follows the platform-specific pattern
// Contracts are compiled from AssemblyScript to WASM
// Deployed via Bitcoin transaction embedding
// Contract addresses derived from deployment transaction
```

## Oracle Considerations

- No native Chainlink on OP_NET yet
- V1: Admin-set oracle with update timelock
- V2: TWAP from on-chain DEX (MotoSwap or equivalent)
- 30-minute TWAP recommended (Bitcoin's 10-min blocks = 3 block TWAP)
- Price stored as u256 with 18 decimal precision

## Gas Optimization Notes

- Batch operations (cook function) should minimize storage reads
- Cache frequently accessed values in local variables
- Use events for historical data rather than on-chain storage
- Consider Bitcoin block space constraints for complex transactions

## Security Patterns

- Reentrancy guards: use boolean lock pattern
- Access control: owner/admin pattern with address checks
- Safe math: AssemblyScript requires explicit overflow checks
- Checks-effects-interactions: update state before external calls

## Known Limitations

1. Ecosystem tooling is newer than EVM
2. Fewer auditing firms familiar with OP_NET
3. DEX liquidity may be limited initially
4. Frontend integration requires OP_NET-specific wallet connection
5. No flash loans on OP_NET (simplifies security model)

## Frontend Integration

- OP_NET wallet (OPWallet) for transaction signing
- RPC endpoints for reading contract state
- Transaction building follows Bitcoin UTXO model
- Privy can handle auth; OP_NET wallet handles signing separately
