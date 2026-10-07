// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {QuantumModel} from "./QuantumModel.sol";

/// @notice Ownerless, noncustodial eight-state observatory; all transitions are deterministic.
/// @dev The constructor must receive this launch's 18-decimal LaunchToken ($token).
contract QuantumEngine {
    uint256 public constant SCALE = 1_000_000;
    uint256 public constant EPOCH_DURATION = 3_600;
    uint256 public constant MIN_BALANCE = 1e18;
    uint16 public constant MAX_OBSERVATIONS = 1_024;
    uint256 private constant TABLE_SIZE = 2_048;

    IERC20 public immutable token;
    uint64 public epoch = 1;
    uint16 public observationCount;
    uint256 public epochStartedAt;
    uint32[8] public probabilities;
    uint16[8] public observationCounts;

    // A fixed table, rather than a permanently growing address=>epoch mapping.
    // Epoch tags lazily invalidate old entries; every record occupies exactly one storage slot.
    struct Observer {
        address account;
        uint64 epoch;
    }

    Observer[2048] private observers;

    error InvalidToken();
    error InvalidState(uint8 state);
    error EpochExpired();
    error EpochStillActive();
    error EpochFull();
    error AlreadyObserved();
    error InsufficientBalance();

    event Observation(uint64 indexed epoch, address indexed observer, uint8 state);
    event EpochAdvanced(
        uint64 indexed completedEpoch, uint256 nextEpochStartedAt, uint16[8] observations, uint32[8] probabilities
    );

    constructor(address token_) {
        if (token_ == address(0) || token_.code.length == 0) revert InvalidToken();
        token = IERC20(token_);
        epochStartedAt = block.timestamp;
        for (uint256 i; i < 8; ++i) {
            probabilities[i] = 125_000;
        }
    }

    /// @notice Choose state 0..7 once per address in the current active epoch while holding >=1 QOBS.
    /// @dev No approval, transfer, lock, fee, reward, or random draw occurs.
    function observe(uint8 state) external {
        if (state >= 8) revert InvalidState(state);
        if (block.timestamp >= epochEndsAt()) revert EpochExpired();
        if (observationCount == MAX_OBSERVATIONS) revert EpochFull();
        (uint256 slot, bool found) = _findObserver(msg.sender);
        if (found) revert AlreadyObserved();
        // IERC20.balanceOf is a STATICCALL: even a hostile configured token cannot mutate/reenter state.
        if (token.balanceOf(msg.sender) < MIN_BALANCE) revert InsufficientBalance();

        observers[slot] = Observer(msg.sender, epoch);
        ++observationCount;
        ++observationCounts[state];
        emit Observation(epoch, msg.sender, state);
    }

    /// @notice Close an expired epoch and start a fresh 3,600-second window at this block's timestamp.
    /// @dev One transition per call, regardless of delay. No token interaction; anyone may advance.
    function advanceEpoch() external {
        if (block.timestamp < epochEndsAt()) revert EpochStillActive();
        uint16[8] memory completedCounts = observationCounts;
        probabilities = QuantumModel.transition(probabilities, completedCounts);
        uint64 completedEpoch = epoch;
        ++epoch;
        epochStartedAt = block.timestamp;
        observationCount = 0;
        delete observationCounts;
        emit EpochAdvanced(completedEpoch, block.timestamp, completedCounts, probabilities);
    }

    function epochEndsAt() public view returns (uint256) {
        return epochStartedAt + EPOCH_DURATION;
    }

    function getProbabilities() external view returns (uint32[8] memory) {
        return probabilities;
    }

    function getObservationCounts() external view returns (uint16[8] memory) {
        return observationCounts;
    }

    /// @notice Whether the address submitted in the current epoch, including while awaiting advancement.
    function hasObserved(address account) external view returns (bool) {
        (, bool found) = _findObserver(account);
        return found;
    }

    function _findObserver(address account) private view returns (uint256 slot, bool found) {
        slot = uint256(keccak256(abi.encodePacked(account))) & (TABLE_SIZE - 1);
        // At most 1,024 slots carry the current tag; a stale slot exists within 1,025 probes.
        for (uint256 probes; probes <= MAX_OBSERVATIONS; ++probes) {
            Observer memory entry = observers[slot];
            if (entry.epoch != epoch) return (slot, false);
            if (entry.account == account) return (slot, true);
            slot = (slot + 1) & (TABLE_SIZE - 1);
        }
        assert(false); // Unreachable: fixed table is at most half full in each epoch.
    }
}
