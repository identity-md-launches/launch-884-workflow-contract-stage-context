// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {QuantumModel} from "src/QuantumModel.sol";

/// @dev Algebraic properties of the equations in docs/model.md, without copying the transform,
/// square root, or largest-remainder implementation into the oracle.
/// forge-config: default.fuzz.runs = 1000
contract QuantumModelPropertiesTest is Test {
    function testFuzz_feedbackUsesFrequenciesNotAbsoluteCount(
        uint32[8] memory raw,
        uint16[8] memory seeds,
        uint16 multiplierSeed
    ) public pure {
        uint32[8] memory p = _distribution(raw);
        uint16[8] memory counts;
        uint16[8] memory scaled;
        uint256 total;
        for (uint256 i; i < 8; ++i) {
            counts[i] = uint16(bound(seeds[i], 0, 16));
            total += counts[i];
        }
        if (total == 0) {
            counts[0] = 1;
            total = 1;
        }
        uint256 multiplier = bound(multiplierSeed, 2, 1024 / total);
        for (uint256 i; i < 8; ++i) {
            scaled[i] = uint16(uint256(counts[i]) * multiplier);
        }
        assertEq(abi.encode(QuantumModel.transition(p, counts)), abi.encode(QuantumModel.transition(p, scaled)));
    }

    function testFuzz_xorRelabelingInputChangesOnlyDiscardedAmplitudeSigns(
        uint32[8] memory raw,
        uint16[8] memory seeds,
        uint8 shiftSeed
    ) public pure {
        uint32[8] memory p = _distribution(raw);
        uint16[8] memory counts = _counts(seeds);
        uint32[8] memory relabeled;
        uint256 shift = bound(shiftSeed, 1, 7);
        for (uint256 i; i < 8; ++i) {
            relabeled[i] = p[i ^ shift];
        }
        // H applied to an XOR-permuted input changes signs, not squared magnitudes.
        assertEq(abi.encode(QuantumModel.transition(p, counts)), abi.encode(QuantumModel.transition(relabeled, counts)));
    }

    function testFuzz_feedbackIsWithinOneUnitOfTheSpecifiedMixture(uint32[8] memory raw, uint16[8] memory seeds)
        public
        pure
    {
        uint32[8] memory p = _distribution(raw);
        uint16[8] memory counts = _counts(seeds);
        uint16[8] memory empty;
        uint32[8] memory baseline = QuantumModel.transition(p, empty);
        uint32[8] memory result = QuantumModel.transition(p, counts);
        uint256 total;
        uint256 mass;
        for (uint256 i; i < 8; ++i) {
            total += counts[i];
            assertGe(baseline[i], 31_250);
            assertLe(baseline[i], 781_250);
        }
        if (total == 0) {
            assertEq(abi.encode(result), abi.encode(baseline));
        } else {
            for (uint256 i; i < 8; ++i) {
                // 75% baseline + 25% empirical frequency, with strictly <1 unit rounding error.
                uint256 exactNumerator = 3 * uint256(baseline[i]) * total + uint256(counts[i]) * 1_000_000;
                uint256 actualNumerator = uint256(result[i]) * (4 * total);
                uint256 error = actualNumerator > exactNumerator
                    ? actualNumerator - exactNumerator
                    : exactNumerator - actualNumerator;
                assertLt(error, 4 * total);
            }
        }
        for (uint256 i; i < 8; ++i) {
            mass += result[i];
        }
        assertEq(mass, 1_000_000);
    }

    function test_oneObservationAndFullUnanimousEpochHaveIdenticalWeight() public pure {
        uint32[8] memory p = [uint32(999_993), 1, 1, 1, 1, 1, 1, 1];
        for (uint256 state; state < 8; ++state) {
            uint16[8] memory one;
            uint16[8] memory full;
            one[state] = 1;
            full[state] = 1024;
            assertEq(abi.encode(QuantumModel.transition(p, one)), abi.encode(QuantumModel.transition(p, full)));
        }
    }

    function _distribution(uint32[8] memory seeds) private pure returns (uint32[8] memory p) {
        // Partition a fixed budget; unlike eight separately capped weights, this reaches nearly
        // empty components and concentrated distributions. Rotate to avoid privileging index zero.
        uint256 remaining = 1_000_000;
        uint256 offset = seeds[7] % 8;
        for (uint256 i; i < 7; ++i) {
            uint256 amount = bound(seeds[i], 0, remaining);
            p[(i + offset) % 8] = uint32(amount);
            remaining -= amount;
        }
        p[(7 + offset) % 8] = uint32(remaining);
    }

    function _counts(uint16[8] memory seeds) private pure returns (uint16[8] memory counts) {
        uint256 remaining = bound(seeds[7], 0, 1024);
        uint256 offset = seeds[0] % 8;
        for (uint256 i; i < 7; ++i) {
            uint256 amount = bound(seeds[i], 0, remaining);
            counts[(i + offset) % 8] = uint16(amount);
            remaining -= amount;
        }
        counts[(7 + offset) % 8] = uint16(remaining);
    }
}
