// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchToken} from "src/LaunchToken.sol";
import {QuantumEngine} from "src/QuantumEngine.sol";

contract QuantumStorageBoundTest is Test {
    mapping(bytes32 => bool) private touched;

    function test_fourFullEpochsKeepStorageBoundedAndMatchSingleObservationFeedback() public {
        LaunchToken token = new LaunchToken();
        QuantumEngine engine = new QuantumEngine(address(token));
        QuantumEngine singleObservation = new QuantumEngine(address(token));
        uint256 uniqueWrites;

        // More distinct observers than the entire fixed table; a per-user mapping would grow.
        for (uint256 round; round < 4; ++round) {
            vm.record();
            for (uint256 i; i < 1024; ++i) {
                address account = address(uint160(0x100000 + round * 1024 + i));
                token.transfer(account, 1 ether);
                vm.prank(account);
                engine.observe(uint8(round));
            }
            assertEq(engine.observationCount(), 1024);
            for (uint256 state; state < 8; ++state) {
                assertEq(engine.observationCounts(state), state == round ? 1024 : 0);
            }
            bytes32 histogram = keccak256(abi.encode(engine.getObservationCounts()));
            vm.expectRevert(QuantumEngine.EpochFull.selector);
            engine.observe(uint8(round)); // A funded, previously unused observer cannot be 1,025th.
            assertFalse(engine.hasObserved(address(this)));
            assertEq(engine.observationCount(), 1024);
            assertEq(keccak256(abi.encode(engine.getObservationCounts())), histogram);
            singleObservation.observe(uint8(round));

            vm.warp(engine.epochEndsAt());
            engine.advanceEpoch();
            singleObservation.advanceEpoch();
            (, bytes32[] memory writes) = vm.accesses(address(engine));
            for (uint256 i; i < writes.length; ++i) {
                if (!touched[writes[i]]) {
                    touched[writes[i]] = true;
                    ++uniqueWrites;
                }
            }
            // Documented bound: 2,048 observer records and four scalar/packed-array slots.
            assertLe(uniqueWrites, 2052, "engine storage grows with observer history");
            assertEq(abi.encode(engine.getProbabilities()), abi.encode(singleObservation.getProbabilities()));
            assertEq(engine.observationCount(), 0);
            assertFalse(engine.hasObserved(address(uint160(0x100000 + round * 1024))));
            assertEq(token.balanceOf(address(engine)), 0);
            assertEq(token.totalSupply(), 1e27);
        }
        assertGt(uniqueWrites, 1024, "storage probe must exercise reuse beyond one epoch");
    }
}

/// forge-config: default.fuzz.runs = 128
contract QuantumCollisionReuseTest is Test {
    LaunchToken private token;
    QuantumEngine private engine;
    address[12] private colliders;

    function setUp() public {
        token = new LaunchToken();
        engine = new QuantumEngine(address(token));
        uint256 found;
        // Every address starts at the final slot, forcing wraparound through slot zero.
        for (uint160 candidate = 1; found < colliders.length; ++candidate) {
            address account = address(candidate);
            if (uint256(keccak256(abi.encodePacked(account))) % 2048 == 2047) {
                colliders[found++] = account;
                token.transfer(account, 1 ether);
            }
        }
    }

    function testFuzz_sparseCollisionChainsSurviveEpochReuse(uint16[4] memory masks, uint8 offsetSeed) public {
        for (uint256 round; round < masks.length; ++round) {
            uint256 mask = bound(masks[round], 1, 4095);
            uint256 accepted;
            bool[12] memory expected;
            uint16[8] memory histogram;
            for (uint256 step; step < 12; ++step) {
                uint256 index = (uint256(offsetSeed) + round + 11 * step) % 12;
                if (mask & (uint256(1) << index) != 0) {
                    uint8 state = uint8(index % 8);
                    vm.prank(colliders[index]);
                    engine.observe(state);
                    expected[index] = true;
                    ++histogram[state];
                    ++accepted;
                    vm.expectRevert(QuantumEngine.AlreadyObserved.selector);
                    vm.prank(colliders[index]);
                    engine.observe(uint8((state + 1) % 8));
                }
                // Check both absent and present accounts after each mutation of the shared chain.
                for (uint256 i; i < 12; ++i) {
                    assertEq(engine.hasObserved(colliders[i]), expected[i]);
                }
                assertEq(engine.observationCount(), accepted);
                assertEq(abi.encode(engine.getObservationCounts()), abi.encode(histogram));
            }
            vm.warp(engine.epochEndsAt());
            for (uint256 i; i < 12; ++i) {
                assertEq(engine.hasObserved(colliders[i]), expected[i]);
            }
            engine.advanceEpoch();
            for (uint256 i; i < 12; ++i) {
                assertFalse(engine.hasObserved(colliders[i]));
            }
            assertEq(engine.observationCount(), 0);
        }
    }

    function test_failedEligibilityDoesNotReserveACollisionSlot() public {
        vm.prank(colliders[0]);
        engine.observe(0);
        vm.prank(colliders[1]);
        token.transfer(address(this), 1 ether);
        vm.expectRevert(QuantumEngine.InsufficientBalance.selector);
        vm.prank(colliders[1]);
        engine.observe(1);
        assertFalse(engine.hasObserved(colliders[1]));
        assertEq(engine.observationCount(), 1);
        vm.prank(colliders[2]);
        engine.observe(2);
        token.transfer(colliders[1], 1 ether);
        vm.prank(colliders[1]);
        engine.observe(1);
        for (uint256 i; i < 3; ++i) {
            assertTrue(engine.hasObserved(colliders[i]));
            assertEq(engine.observationCounts(i), 1);
        }
        assertEq(engine.observationCount(), 3);
    }
}
