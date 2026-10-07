# Quantum Observatory (QOBS)

Quantum Observatory is a classical, deterministic experiment with eight probabilities and community observations. This contribution delivers the contracts, tests, ABI exports, scientific model documentation, and deployment handoff for the contract stage.

## Build and check

Foundry and Solidity **0.8.26** are the only build prerequisites. All Solidity dependencies are ordinary files under `lib/`; no network, submodules, environment variables, FFI, or filesystem cheatcodes are required by the tests. An offline verifier must already carry the pinned compiler. No compiler binary is included.

```sh
forge build
forge test
forge fmt --check
python3 tools/export_abi.py --check
```

`foundry.toml` pins the Cancun EVM, optimizer with 200 runs, and `bytecode_hash = "none"`. ABI files are [LaunchToken.json](docs/abi/LaunchToken.json) and [QuantumEngine.json](docs/abi/QuantumEngine.json). See [the interface guide](docs/abi/README.md).

## Behavior

| Parameter | Fixed value |
| --- | --- |
| Token | Quantum Observatory / QOBS |
| Supply | 1,000,000,000 tokens, 18 decimals; exactly `10^27` minor units |
| Mint recipient | Constructor caller, which is ProjectFactory during launch |
| Probabilities | Eight integers totaling 1,000,000; initially 125,000 each |
| Epoch | Begins at deployment, then at each successful advancement; 3,600-second submission window |
| Eligibility | Caller holds at least `10^18` QOBS minor units at submission |
| Observation | One state in 0–7 per address per epoch; at most 1,024 observations |
| Advancement | Anyone after expiry, including with zero QOBS; exactly one transition per call |

`observe(state)` reads the QOBS balance and records a choice. It never requests approval, transfers tokens, locks funds, mints rewards, or changes probabilities immediately. At `timestamp == epochEndsAt()`, observation closes and `advanceEpoch()` becomes available. Full epochs still wait for expiry. A delayed advancement starts a fresh full window at its transaction timestamp; missed hours do not cause catch-up transitions. Histograms and eligibility reset, while the newly calculated probabilities persist.

The model reconstructs real amplitudes, applies an eight-state Hadamard transform, squares and normalizes, mixes 25% uniform noise, then incorporates 25% observation frequencies if there are observations. Exact equations, rounding, ten scientific sources, and limitations are in [docs/model.md](docs/model.md). This produces no random outcome and has no financial payout.

The engine has no owner, pause, withdrawal, upgrade, token-changing, or administrative functions. The launch token is a plain OpenZeppelin ERC-20 with no extra externally reachable mint or burn path, fee, blocklist, limit, owner, or upgrade power.

## Assumptions and operational limits

- The engine constructor receives this launch's **LaunchToken**, using `$token`. It checks that code exists, not that arbitrary supplied code implements QOBS. The dependency is immutable.
- Eligibility is per address, not per person or token unit. Transferring or borrowing the same QOBS can qualify multiple addresses. Bots can fill all 1,024 slots. Transaction ordering matters when capacity is exhausted.
- There is no keeper subsidy. Any willing caller pays gas to advance. If nobody does, the expired epoch remains closed. Block timestamps gate the window; they never seed a random process.
- Engine state occupies at most **2,052 storage slots**: four scalar/array slots and a fixed 2,048-record table. Each record packs an address and epoch tag. Logs and blockchain history grow; contract storage does not grow with historical users. Token balances/allowances retain normal ERC-20 mapping behavior.
- Hash collisions are resolved by linear probing, with at most 1,025 reads per lookup. Deliberately colliding addresses can increase observation/view gas. Advancement does not scan the table. Epoch tags use checked `uint64` increments; exhaustion would require roughly 2.1 quadrillion years of hourly epochs.
- The contracts reject ordinary ETH payments. Anyone can still transfer ERC-20s directly to them or force ETH to an address; there is no recovery function. Such balances are not used by the model.

## Launch economics and responsibilities

The factory receives the whole token supply. It supplies the distributor, pool, and initialization guard and performs the protocol split: 10% swarm (2% accepted contributors; 8% paired seats), 90% requester, with the selected requester liquidity allocation coming from that 90%. The platform default is 80% of total supply to liquidity and 10% to the requester wallet. These contracts do not allocate, retain, or forward those shares.

Pool economics remain platform-controlled. Canonical admission uses fee `3000`, tick spacing `60`, and legacy price `79228162514264337593543950336`. The effective opening price follows the pinned policy; actual trading fees follow the chain's LaunchFees configuration (platform default 1.25% total: 1% requester/payer and 0.25% IMD). No pool-fee logic is embedded in QOBS or the engine.

[docs/deployment.md](docs/deployment.md) defines constructor arguments, source identifiers, deployment order, and handoff responsibilities. The separate manifest contributor writes `launch.json`; the independent reviewer examines accepted source and that manifest. Services publish source, attest, admit, deploy on Ethereum mainnet, and hand exact addresses and pool parameters to the subsequent website/IPFS stage. Publication, a public IPFS URL, and deployed addresses are not claimed by this source contribution.

The later website must display the complete model document, connect wallets, show deployed addresses and live state, and offer observation and advancement transactions using the exported ABIs. The model document is part of the source artifact, not a dependency on a separate research task.

## Validation and review

The suite covers token supply and ERC-20 failure behavior, factory constructor execution and runtime checks, eligibility, duplicates, epoch boundaries and delays, 1,024 observations over successive epochs, hash collisions, token-read failure and hostile callbacks, events, order-independent transitions, exact reference vectors, fuzzed mass conservation, and stateful invariants.

The Python standard-library [reference model](tools/model_reference.py) generates 32 checked-in Solidity vectors using explicit matrix multiplication and `math.isqrt`, independently of the Solidity butterfly and Newton implementations. Regeneration is optional:

```sh
python3 tools/model_reference.py
forge fmt test/QuantumVectors.t.sol
forge test
```

See [docs/security.md](docs/security.md) for implementation review notes and residual risks. Local checks are not an independent security audit. Independent review of source and final manifest remains a required later-stage responsibility. No transactions were broadcast and no wallet keys are used.
