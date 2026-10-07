// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev Classical, deterministic model; see docs/model.md for equations and approximations.
/// Internal functions are inlined into QuantumEngine; this library needs no deployment.
library QuantumModel {
    uint256 internal constant SCALE = 1_000_000;

    /// @dev Preconditions, maintained by the engine: sum(p) = SCALE and sum(counts) <= 1024.
    function transition(uint32[8] memory p, uint16[8] memory counts) internal pure returns (uint32[8] memory) {
        int256[8] memory amplitudes;
        for (uint256 i; i < 8; ++i) {
            amplitudes[i] = int256(_sqrt(uint256(p[i]) * SCALE));
        }

        // Unnormalized H tensor H tensor H. Its common normalization cancels when squaring/rescaling.
        for (uint256 width = 1; width < 8; width *= 2) {
            for (uint256 start; start < 8; start += 2 * width) {
                for (uint256 offset; offset < width; ++offset) {
                    uint256 a = start + offset;
                    uint256 b = a + width;
                    int256 left = amplitudes[a];
                    int256 right = amplitudes[b];
                    amplitudes[a] = left + right;
                    amplitudes[b] = left - right;
                }
            }
        }

        uint256[8] memory weights;
        for (uint256 i; i < 8; ++i) {
            // |amplitudes[i]| <= 8e6, so the signed square and all subsequent products are safe.
            weights[i] = uint256(amplitudes[i] * amplitudes[i]);
        }
        uint32[8] memory coherent = _normalize(weights);
        for (uint256 i; i < 8; ++i) {
            weights[i] = 3 * uint256(coherent[i]) + SCALE / 8;
        }
        uint32[8] memory mixed = _normalize(weights);

        uint256 total;
        for (uint256 i; i < 8; ++i) {
            total += counts[i];
        }
        if (total == 0) return mixed;

        // 75% mixed model + 25% empirical choices. No token weighting or random sampling.
        for (uint256 i; i < 8; ++i) {
            weights[i] = 3 * uint256(mixed[i]) * total + uint256(counts[i]) * SCALE;
        }
        return _normalize(weights);
    }

    /// @dev Largest-remainder apportionment; ties favor the lower state index. Sum is exactly SCALE.
    function _normalize(uint256[8] memory weights) private pure returns (uint32[8] memory result) {
        uint256 total;
        for (uint256 i; i < 8; ++i) {
            total += weights[i];
        }
        // A normalized input has a nonzero amplitude; the Hadamard transform is invertible.
        assert(total != 0);
        uint256 allocated;
        uint256[8] memory remainders;
        for (uint256 i; i < 8; ++i) {
            uint256 numerator = weights[i] * SCALE;
            result[i] = uint32(numerator / total);
            remainders[i] = numerator % total;
            allocated += result[i];
        }
        // The sum of eight fractional remainders is less than eight: at most seven iterations.
        for (uint256 left = SCALE - allocated; left != 0; --left) {
            uint256 best;
            for (uint256 i = 1; i < 8; ++i) {
                if (remainders[i] > remainders[best]) best = i;
            }
            ++result[best];
            remainders[best] = 0;
        }
    }

    /// @dev Integer Newton iteration, floor(sqrt(n)); n <= 1e12 in this model.
    function _sqrt(uint256 n) private pure returns (uint256 root) {
        if (n == 0) return 0;
        root = n;
        uint256 next = (n + 1) / 2;
        while (next < root) {
            root = next;
            next = (n / next + next) / 2;
        }
    }
}
