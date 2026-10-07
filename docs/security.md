# Implementation review notes

These are the implementing contributor's design and verification notes, **not an independent audit or launch approval**. The final independent review must inspect accepted source and `launch.json` together. Source publication, attestations, policy linkage, admission, production deployment, and explorer verification belong to services.

## Properties checked locally

- `LaunchToken` inherits the vendored OpenZeppelin v5.1.0 ERC-20 and adds only its zero-argument constructor. The full `10^27` supply goes to its caller once. ERC-20 transfers/allowances do not change supply. No externally callable mint, burn, owner, fee, pause, blacklist, or upgrade capability is added.
- `QuantumEngine` has two state-changing methods with explicit public rules. `observe` checks state, time, capacity, per-epoch uniqueness, and balance; `advanceEpoch` checks expiry. No address receives administrative power, including the deployment factory.
- The only engine external interaction is `IERC20.balanceOf`, compiled as `STATICCALL`. It occurs before writes, and a failed read rolls back the submission. Static context prevents a hostile token callback from changing state. The actual LaunchToken performs no callbacks. Advancement makes no external calls, so token unavailability cannot prevent advancing an already deployed engine.
- There are no custody paths, allowances, payouts, pricing oracles, signatures, proxy calls, `DELEGATECALL`, `CALLCODE`, or `SELFDESTRUCT`. Constructor-through-factory and runtime-opcode tests mirror the supplied launch-floor properties without depending on its environment variables.
- Fixed arrays cap engine state at 2,052 slots. Current-tag hash-table entries are inserted without deletion during an epoch; a stale tag terminates a probe because it cannot precede an existing current-tag entry along that entry's insertion path. Changing the epoch invalidates all entries without clearing or scanning them. Checked epoch arithmetic prevents tag wraparound.
- Probability calculations use checked arithmetic, a nonzero normalization denominator, bounded signed amplitudes, and explicit deterministic remainder allocation. The model document contains arithmetic bounds. Counts fit in `uint16`; totals cannot exceed 1,024.
- Rejected operations do not consume an observation slot. Tests include exact thresholds, duplicates, collision wraparound, full capacity, later-epoch reuse, late entry, early/double advancement, long delays, failing balance calls, hostile callbacks, ETH rejection, and event contents.

## Residual assumptions for independent review

The constructor accepts any address with code. The final manifest **must** pass `$token`, resolving to the reviewed 18-decimal QOBS implementation. Merely checking code presence cannot establish its ABI or behavior. There is no recovery from a wrong dependency address.

Per-address balance eligibility is susceptible to Sybil users, temporary borrowing, token recycling, and capacity capture. These follow directly from the specified eligibility rule; no stake, snapshot, identity check, or token lock is added. Transaction censorship and gas costs can influence who is admitted. The engine carries no financial entitlement based on its observations, but external consumers must not assume they represent distinct people.

Linear probing is bounded but can be deliberately made expensive with colliding addresses. Worst-case lookups inspect up to 1,025 records. Normal advancement works on eight-element arrays only; the capacity test asserts it stays below 500,000 execution gas in the test environment. This is not a promise about transaction gas including all network overhead. Epoch progression requires a willing gas payer and has no financial incentive built in.

The numerical model resets phase information, privileges a basis convention, includes fixed uncalibrated feedback/noise rates, and is fully predictable. It is unsuitable as randomness, an oracle, or an empirical quantum simulation. Sending ETH or tokens directly can trap them permanently because no withdrawal authority exists.

## Check record

On 2026-10-07, `forge build`, `forge test` (also with four test threads), `forge fmt --check`, ABI/artifact comparison, and vendored-file checksum verification passed. The suite reported **60 passing tests, zero failures, and zero skips**. It uses 256 cases per fuzz property and 64 invariant runs of depth 64 (4,096 handler calls), including 32 oracle vectors from a separate Python implementation. Optimized deployed runtime sizes are 1,722 bytes for LaunchToken and 4,789 bytes for QuantumEngine, below the 24,576-byte limit. The supplied protected floors require service-provided creation code and policy environment; their source was inspected, but their service admission run is not claimed here.

No Slither or Mythril run, independent auditor sign-off, funded-wallet access, live-chain interaction, source publication, website publication, or deployment is claimed. The independent reviewer should evaluate the model's arithmetic and table invariants as well as the accepted source/manifest linkage and constructor parameters.
