# Additional adversarial tests

These tests extend the accepted suite without changing the contracts or configuration.
They use the repository's existing Solidity and forge-std dependencies, with no network,
fork, FFI, environment mutation, or generated runtime fixtures.

| File | Additional coverage |
| --- | --- |
| `ObservatoryStateful.t.sol` | Random transfers, approvals, delegated transfers, observations, time passage, and advancement. Independent ghost balances, allowances, accepted histograms, membership, and epoch times are checked after each call. |
| `LaunchTokenFailurePaths.t.sol` | Allowance rollback after balance/recipient failures, self-directed delegated transfers, zero-value events, and full-supply transfers with maximum allowances and amounts. |
| `QuantumAdversarial.t.sol` | Storage writes over 4,096 distinct observers, full unanimous epochs, rejected entry at capacity, colliding addresses with wraparound, and sparse collision-chain reuse. |
| `QuantumModelProperties.t.sol` | Proportional-count invariance, XOR relabeling of input amplitudes, feedback rounding error strictly below one probability unit, and concentrated distributions. |

The new invariant campaign uses six holders, 256 runs, and depth 96. It includes
successful calls and exact expected reverts, with `fail-on-revert` enabled so unexpected
failures are not discarded. A deterministic walkthrough checks that its handlers can
perform nonzero transfers, exhaust/revoke allowances, change eligibility, and renew an
epoch. The six-holder campaign does not reach the 1,024-observation cap; separate full
epoch tests cover that boundary. The model and token properties run 1,000 fuzz cases
each; the more expensive collision property runs 128.

Model properties follow the equations in `docs/model.md`. They do not assert that the
model represents a physical quantum system. The storage test checks the documented
2,052-slot bound over its exercised histories; it is not a proof over every history.

To keep local build products inside the disposable scratch directory:

```sh
forge build --offline --out test/scratch/out --cache-path test/scratch/cache
forge test --offline --out test/scratch/out --cache-path test/scratch/cache
```

No submitted test imports anything from `test/scratch/` or the protected input files.
