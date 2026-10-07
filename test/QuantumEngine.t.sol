// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {QuantumEngine} from "../src/QuantumEngine.sol";

contract BalanceFailureToken {
    bool public fail;

    function setFail(bool value) external {
        fail = value;
    }

    function balanceOf(address) external view returns (uint256) {
        require(!fail, "balance unavailable");
        return 1 ether;
    }
}

contract ReentrantBalanceToken {
    QuantumEngine public engine;
    bool public callbackSucceeded;

    function setEngine(QuantumEngine value) external {
        engine = value;
    }

    // Intentionally non-view: called by engine through the view IERC20 interface and thus STATICCALL.
    function balanceOf(address) external returns (uint256) {
        (bool ok,) = address(engine).call(abi.encodeCall(QuantumEngine.observe, (0)));
        callbackSucceeded = ok; // The static context rejects this write and rolls back the entire call.
        return 1 ether;
    }
}

contract QuantumEngineTest is Test {
    LaunchToken internal token;
    QuantumEngine internal engine;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);

    function setUp() public {
        vm.warp(100_000);
        token = new LaunchToken();
        engine = new QuantumEngine(address(token));
        token.transfer(ALICE, 1 ether);
        token.transfer(BOB, 1 ether - 1);
    }

    function test_constructorAndInitialState() public view {
        assertEq(address(engine.token()), address(token));
        assertEq(engine.epoch(), 1);
        assertEq(engine.epochStartedAt(), 100_000);
        assertEq(engine.epochEndsAt(), 103_600);
        assertEq(engine.observationCount(), 0);
        for (uint256 i; i < 8; ++i) {
            assertEq(engine.probabilities(i), 125_000);
        }
        assertFalse(engine.hasObserved(ALICE));
        _assertConservation();
    }

    function test_constructorRejectsZeroAndEOA() public {
        vm.expectRevert(QuantumEngine.InvalidToken.selector);
        new QuantumEngine(address(0));
        vm.expectRevert(QuantumEngine.InvalidToken.selector);
        new QuantumEngine(ALICE);
    }

    function test_exactBalanceThresholdAndInvalidState() public {
        vm.prank(ALICE);
        engine.observe(7);
        assertEq(engine.observationCounts(7), 1);
        assertTrue(engine.hasObserved(ALICE));
        vm.expectRevert(QuantumEngine.InsufficientBalance.selector);
        vm.prank(BOB);
        engine.observe(0);
        token.transfer(BOB, 1);
        vm.prank(BOB);
        engine.observe(0);
        vm.expectRevert(abi.encodeWithSelector(QuantumEngine.InvalidState.selector, uint8(8)));
        engine.observe(8);
        assertEq(engine.observationCount(), 2);
        _assertConservation();
    }

    function testFuzz_invalidStatesAreAtomic(uint8 state) public {
        state = uint8(bound(state, 8, 255));
        vm.expectRevert(abi.encodeWithSelector(QuantumEngine.InvalidState.selector, state));
        vm.prank(ALICE);
        engine.observe(state);
        assertEq(engine.observationCount(), 0);
        assertFalse(engine.hasObserved(ALICE));
    }

    function test_duplicateRejectedAcrossStatesAndBalanceChanges() public {
        vm.prank(ALICE);
        engine.observe(0);
        vm.prank(ALICE);
        token.transfer(BOB, 1 ether);
        vm.prank(BOB);
        token.transfer(ALICE, 1 ether);
        vm.expectRevert(QuantumEngine.AlreadyObserved.selector);
        vm.prank(ALICE);
        engine.observe(7);
        assertEq(engine.observationCount(), 1);
        assertEq(engine.observationCounts(7), 0);
    }

    function test_balanceCheckedAtEachSubmissionAndNoCustody() public {
        vm.prank(ALICE);
        engine.observe(2);
        vm.prank(ALICE);
        token.transfer(BOB, 1 ether);
        vm.prank(BOB);
        engine.observe(2); // Balance gating intentionally does not prevent token recycling across addresses.
        assertEq(engine.observationCount(), 2);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 2 ether - 1);
        assertEq(token.balanceOf(address(engine)), 0);
        assertEq(token.totalSupply(), 1e27);
    }

    function test_boundaryRejectsEarlyAdvanceAndLateEntry() public {
        vm.warp(engine.epochEndsAt() - 1);
        vm.expectRevert(QuantumEngine.EpochStillActive.selector);
        engine.advanceEpoch();
        vm.prank(ALICE);
        engine.observe(3);
        vm.warp(engine.epochEndsAt());
        vm.expectRevert(QuantumEngine.EpochExpired.selector);
        engine.observe(3);
        vm.prank(address(0xCAFE)); // No QOBS required to advance.
        engine.advanceEpoch();
        assertEq(engine.epoch(), 2);
        assertEq(engine.observationCount(), 0);
        assertEq(engine.epochStartedAt(), 103_600);
        assertEq(engine.epochEndsAt(), 107_200);
        assertFalse(engine.hasObserved(ALICE));
        vm.prank(ALICE);
        engine.observe(4);
        assertEq(engine.observationCounts(3), 0);
        assertEq(engine.observationCounts(4), 1);
        vm.expectRevert(QuantumEngine.EpochStillActive.selector);
        engine.advanceEpoch();
        _assertConservation();
    }

    function test_delayedAdvanceAppliesExactlyOneStepAndStartsFullWindow() public {
        vm.warp(engine.epochEndsAt() + 30 days);
        vm.expectRevert(QuantumEngine.EpochExpired.selector);
        vm.prank(ALICE);
        engine.observe(0);
        engine.advanceEpoch();
        assertEq(engine.epoch(), 2);
        assertEq(engine.epochStartedAt(), block.timestamp);
        assertEq(engine.epochEndsAt(), block.timestamp + 3600);
        assertEq(engine.probabilities(0), 781_250);
        for (uint256 i = 1; i < 8; ++i) {
            assertEq(engine.probabilities(i), 31_250);
        }
        _assertConservation();
    }

    function test_observationAndAdvanceEventsAndKnownVector() public {
        vm.expectEmit(true, true, false, true, address(engine));
        emit Observation(1, ALICE, 7);
        vm.prank(ALICE);
        engine.observe(7);
        uint16[8] memory counts;
        counts[7] = 1;
        uint32[8] memory expected = [uint32(585938), 23438, 23438, 23438, 23437, 23437, 23437, 273437];
        vm.warp(engine.epochEndsAt());
        vm.expectEmit(true, false, false, true, address(engine));
        emit EpochAdvanced(1, block.timestamp, counts, expected);
        engine.advanceEpoch();
        assertEq(abi.encode(engine.getProbabilities()), abi.encode(expected));
        assertEq(token.balanceOf(ALICE), 1 ether);
        assertEq(token.allowance(ALICE, address(engine)), 0);
        assertEq(token.balanceOf(address(engine)), 0);
    }

    function test_capacityExactly1024AndStorageReusedAcrossEpochs() public {
        for (uint256 round; round < 3; ++round) {
            for (uint256 i; i < 1024; ++i) {
                address observer = address(uint160(100_000 + 1024 * round + i));
                token.transfer(observer, 1 ether);
                vm.prank(observer);
                engine.observe(uint8(i % 8));
            }
            assertEq(engine.observationCount(), 1024);
            for (uint256 i; i < 8; ++i) {
                assertEq(engine.observationCounts(i), 128);
            }
            for (uint256 i; i < 1024; ++i) {
                assertTrue(engine.hasObserved(address(uint160(100_000 + 1024 * round + i))));
            }
            assertFalse(engine.hasObserved(ALICE));
            vm.expectRevert(QuantumEngine.EpochFull.selector);
            vm.prank(ALICE);
            engine.observe(1);
            vm.warp(engine.epochEndsAt());
            uint256 beforeGas = gasleft();
            engine.advanceEpoch();
            assertLt(beforeGas - gasleft(), 500_000, "advancement must not scan the observer table");
            assertEq(engine.observationCount(), 0);
            assertFalse(engine.hasObserved(address(uint160(100_000 + 1024 * round))));
            _assertConservation();
        }
    }

    function test_hashCollisionsWrapAndDoNotBypassDuplicateCheck() public {
        address[5] memory colliders;
        uint256 found;
        for (uint160 candidate = 1; found < 5; ++candidate) {
            address observer = address(candidate);
            if (uint256(keccak256(abi.encodePacked(observer))) % 2048 == 2047) colliders[found++] = observer;
        }
        for (uint256 i; i < 5; ++i) {
            token.transfer(colliders[i], 1 ether);
            vm.prank(colliders[i]);
            engine.observe(uint8(i));
        }
        for (uint256 i; i < 5; ++i) {
            assertTrue(engine.hasObserved(colliders[i]));
            vm.expectRevert(QuantumEngine.AlreadyObserved.selector);
            vm.prank(colliders[i]);
            engine.observe(7);
        }
        vm.warp(engine.epochEndsAt());
        engine.advanceEpoch();
        for (uint256 i; i < 5; ++i) {
            assertFalse(engine.hasObserved(colliders[4 - i]));
            vm.prank(colliders[4 - i]);
            engine.observe(uint8(i));
        }
        assertEq(engine.observationCount(), 5);
    }

    function test_transitionIgnoresOrderCallerAndDelay() public {
        QuantumEngine second = new QuantumEngine(address(token));
        token.transfer(BOB, 1);
        vm.prank(ALICE);
        engine.observe(6);
        vm.prank(BOB);
        engine.observe(3);
        vm.prank(BOB);
        second.observe(3);
        vm.prank(ALICE);
        second.observe(6);
        vm.warp(engine.epochEndsAt());
        engine.advanceEpoch();
        vm.warp(block.timestamp + 10 days);
        vm.prank(BOB);
        second.advanceEpoch();
        assertEq(abi.encode(engine.getProbabilities()), abi.encode(second.getProbabilities()));
    }

    function test_balanceReadFailureIsAtomicAndCannotBlockAdvancement() public {
        BalanceFailureToken failing = new BalanceFailureToken();
        QuantumEngine isolated = new QuantumEngine(address(failing));
        failing.setFail(true);
        vm.expectRevert(bytes("balance unavailable"));
        isolated.observe(0);
        assertEq(isolated.observationCount(), 0);
        assertFalse(isolated.hasObserved(address(this)));
        failing.setFail(false);
        isolated.observe(0);
        failing.setFail(true);
        vm.warp(isolated.epochEndsAt());
        isolated.advanceEpoch();
        assertEq(isolated.epoch(), 2);
    }

    function test_hostileBalanceCallbackCannotMutateEngine() public {
        ReentrantBalanceToken hostile = new ReentrantBalanceToken();
        QuantumEngine isolated = new QuantumEngine(address(hostile));
        hostile.setEngine(isolated);
        // Bound gas because hostile recursive calls intentionally exhaust their static context.
        (bool ok,) = address(isolated).call{gas: 500_000}(abi.encodeCall(QuantumEngine.observe, (1)));
        assertFalse(ok);
        assertFalse(hostile.callbackSucceeded());
        assertEq(isolated.observationCount(), 0);
        assertFalse(isolated.hasObserved(address(this)));
        assertFalse(isolated.hasObserved(address(hostile)));
        vm.warp(isolated.epochEndsAt());
        isolated.advanceEpoch();
        assertEq(isolated.epoch(), 2);
    }

    function test_rejectsETHAndUnknownSelectors() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(engine).call{value: 1}("");
        assertFalse(ok);
        (ok,) = address(engine).call{value: 1}(abi.encodeCall(QuantumEngine.observe, (0)));
        assertFalse(ok);
        (ok,) = address(engine).call(abi.encodeWithSignature("withdraw()"));
        assertFalse(ok);
        (ok,) = address(engine).call(abi.encodeWithSignature("pause()"));
        assertFalse(ok);
        assertEq(address(engine).balance, 0);
    }

    function _assertConservation() internal view {
        uint256 sum;
        uint256 observations;
        for (uint256 i; i < 8; ++i) {
            sum += engine.probabilities(i);
            observations += engine.observationCounts(i);
        }
        assertEq(sum, 1_000_000);
        assertEq(observations, engine.observationCount());
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(address(engine)), 0);
    }

    event Observation(uint64 indexed epoch, address indexed observer, uint8 state);
    event EpochAdvanced(
        uint64 indexed completedEpoch, uint256 nextEpochStartedAt, uint16[8] observations, uint32[8] probabilities
    );
}
