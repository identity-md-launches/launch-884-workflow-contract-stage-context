# Contract ABI guide

`LaunchToken.json` and `QuantumEngine.json` are complete compiler ABI arrays, including constructors, errors, events, and all public getters. They can be imported by an Ethereum client without artifact-wrapper parsing. Regenerate with `python3 tools/export_abi.py` after `forge build`; use `--check` for a read-only comparison.

## LaunchToken

Constructor takes no arguments and is nonpayable. Standard ERC-20 methods are `name`, `symbol`, `decimals`, `totalSupply`, `balanceOf`, `allowance`, `approve`, `transfer`, and `transferFrom`. Balances and amounts are in 18-decimal minor units. Events are `Transfer` and `Approval`; revert errors are the OpenZeppelin ERC-6093 variants exported in the ABI. Finite allowances decrease on spending; maximum `uint256` allowances retain the standard infinite-allowance behavior. The engine needs neither approvals nor `transferFrom`.

## QuantumEngine

Constructor takes the deployed QOBS address and is nonpayable. All write calls take zero ETH value and return no data.

| Call | Purpose / units |
| --- | --- |
| `observe(uint8 state)` | Submit one choice, 0–7, for the connected eligible caller |
| `advanceEpoch()` | Process one expired epoch and open a new 3,600-second window |
| `token()` | Immutable QOBS address |
| `epoch()` | Current `uint64` epoch, starting at 1 |
| `epochStartedAt()`, `epochEndsAt()` | Unix timestamps in seconds |
| `observationCount()` | Current accepted observations, 0–1,024 |
| `getProbabilities()` | `uint32[8]` scaled probabilities, summing to 1,000,000 |
| `getObservationCounts()` | `uint16[8]` current histogram |
| `probabilities(uint256)`, `observationCounts(uint256)` | Single element; index must be 0–7 |
| `hasObserved(address)` | Whether that account submitted in the currently stored epoch |
| `SCALE()`, `EPOCH_DURATION()`, `MIN_BALANCE()`, `MAX_OBSERVATIONS()` | Fixed constants, respectively 1,000,000; 3,600; `10^18`; 1,024 |

`hasObserved` remains true after expiry until the next successful advancement. It does not mean the epoch is open or the account still holds sufficient tokens. An empty slot returns false even for the zero address. Current probabilities change only on advancement; counts change on observations and reset on advancement.

`Observation(uint64 indexed epoch,address indexed observer,uint8 state)` records each accepted observation. `EpochAdvanced(uint64 indexed completedEpoch,uint256 nextEpochStartedAt,uint16[8] observations,uint32[8] probabilities)` records the completed histogram and the **new** probability vector. The newly active epoch is `completedEpoch + 1`; its initial count is zero. Initial probabilities are defined by the constructor, with no synthetic initial advancement event.

Errors are `InvalidToken`, `InvalidState(uint8)`, `EpochExpired`, `EpochStillActive`, `EpochFull`, `AlreadyObserved`, and `InsufficientBalance`. Observation checks run in that order: state, deadline, capacity, duplicate, balance. A full epoch therefore returns `EpochFull` even for a duplicate address. Balance-provider failures bubble up; malformed return data reverts. Boundary definition: observations require `block.timestamp < epochEndsAt`; advancement requires `>=`.

Read a coherent snapshot using one block tag. Estimate transaction gas on current state, especially near capacity or after a competing advancement. Format percentages as `P_i / 10,000`, retaining four decimal places if showing every stored unit. No API exposes random seeds, selected winners, payouts, or privileged controls.
