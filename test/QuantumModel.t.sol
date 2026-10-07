// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {QuantumModel} from "../src/QuantumModel.sol";

contract QuantumModelTest is Test {
    function test_everyBasisStateBecomesUniform() public pure {
        uint16[8] memory counts;
        for (uint256 state; state < 8; ++state) {
            uint32[8] memory p;
            p[state] = 1_000_000;
            uint32[8] memory next = QuantumModel.transition(p, counts);
            for (uint256 i; i < 8; ++i) {
                assertEq(next[i], 125_000);
            }
        }
    }

    function testFuzz_transitionNormalizationAndBounds(uint32[8] memory seeds, uint16[8] memory votes) public pure {
        uint32[8] memory p = _distribution(seeds);
        for (uint256 i; i < 8; ++i) {
            votes[i] %= 129;
        }
        _assertDistribution(QuantumModel.transition(p, votes));
    }

    function testFuzz_manyTransitionsPreserveMass(uint32[8] memory seeds, uint16[8] memory votes) public pure {
        uint32[8] memory p = _distribution(seeds);
        for (uint256 i; i < 8; ++i) {
            votes[i] %= 129;
        }
        uint16[8] memory empty;
        for (uint256 round; round < 24; ++round) {
            p = QuantumModel.transition(p, round % 2 == 0 ? votes : empty);
            _assertDistribution(p);
        }
    }

    function _distribution(uint32[8] memory raw) private pure returns (uint32[8] memory p) {
        uint256 sum;
        for (uint256 i; i < 8; ++i) {
            sum += raw[i];
        }
        if (sum == 0) {
            p[0] = 1_000_000;
            return p;
        }
        uint32 allocated;
        for (uint256 i; i < 8; ++i) {
            p[i] = uint32(uint256(raw[i]) * 1_000_000 / sum);
            allocated += p[i];
        }
        p[0] += 1_000_000 - allocated;
    }

    function _assertDistribution(uint32[8] memory p) private pure {
        uint256 sum;
        for (uint256 i; i < 8; ++i) {
            assertGe(p[i], 23_437, "depolarizing floor after observation feedback");
            assertLe(p[i], 835_938, "maximum after depolarization and feedback");
            sum += p[i];
        }
        assertEq(sum, 1_000_000);
    }
}
