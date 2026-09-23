# Remediation verification — intermediate

## FS-oracle-01

Baseline: BASELINE.json; snapshot unchanged. Candidate source SHA256:
753907d4c41ce9ac00cdba3dc814b0011bc632d55d930f21a7f43cb281078ffa.

| Evidence | Result |
|---|---|
| oracle-failure-boundaries | Baseline: 0 pass, 5 fail, 0 skip |
| oracle-hook-lifecycle | Baseline: 1 pass, 1 fail, 0 skip |
| oracle-fix-regressions | Candidate: 42 pass, 0 fail, 0 skip; exit 0; 184.39s including compilation |
| oracle-fix-neighbors | Candidate: 146 pass, 0 fail, 0 skip; exit 0; 12.64s |
| verify_oracle_surface.mjs | ABI/selectors/storage unchanged; current hash matched; unresolved compiler references/selectors zero |

Exact commands, cwd, timing and exit status are in logs/<label>.json; full test
output is in the corresponding .log. Candidate batches are disjoint: 188 tests
passed, not a claim that every repository test ran. The snapshot's failing
tests remain failing by design and their results must not be erased.

Both compiler-versioned QuoteOracle artifacts (0.8.26/0.8.30) report runtime
3,970 bytes, initcode 4,128 bytes. Baseline: 3,821/3,979. Runtime headroom to
24,576 bytes: 20,606. Artifact metadata source keccak agrees with local
`cast keccak < contracts/solidity/cauldron/QuoteOracle.sol`:
0xf6e6ad34686a381d98331b3d873090d5ceb0293ae9ea2a5e0a8defe7737bc043.
Used versioned artifacts, not the potentially stale unversioned artifact.

Separate patch source review is in LEDGER.md. This is a same-reviewer second
pass, not independent human/agent verification. Full repository/fork suites,
deployed bytecode parity and final subsystem review are still required.
