// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LaunchToken} from "src/LaunchToken.sol";
import {QuantumEngine} from "src/QuantumEngine.sol";

/// @dev A closed set of holders lets the oracle account for every unit of the real minted supply.
/// Ghosts are updated from successful actions, never copied from the contract's resulting state.
contract ObservatorySequenceHandler is Test {
    uint256 public constant SUPPLY = 1e27;
    uint256 public constant ACTORS = 6;
    LaunchToken public immutable token;
    QuantumEngine public immutable engine;
    uint256[6] public balances;
    uint256[6][6] public allowances;
    bool[6] public submitted;
    uint16[8] public counts;
    uint64 public expectedEpoch = 1;
    uint256 public expectedStart;
    uint256 public successfulTransfers;
    uint256 public successfulSpends;
    uint256 public successfulObservations;
    uint256 public successfulAdvances;
    uint256 public rejectedCalls;

    constructor() {
        token = new LaunchToken();
        engine = new QuantumEngine(address(token));
        expectedStart = block.timestamp;
        balances[0] = SUPPLY - 3 ether;
        balances[1] = 1 ether - 1;
        balances[2] = 1 ether;
        balances[3] = 1 ether + 1;
        for (uint256 i; i < ACTORS; ++i) {
            token.transfer(actor(i), balances[i]);
            // Even pre-existing unlimited approval must not let the engine change balances.
            vm.prank(actor(i));
            token.approve(address(engine), type(uint256).max);
        }
    }

    function actor(uint256 index) public pure returns (address) {
        return address(uint160(0x10000 + index));
    }

    function transfer(uint8 fromSeed, uint8 toSeed, uint256 amountSeed, uint8 mode) external {
        uint256 from = fromSeed % ACTORS;
        uint256 to = toSeed % ACTORS;
        address recipient = toSeed == type(uint8).max ? address(0) : actor(to);
        uint256 amount = _amount(amountSeed, mode, balances[from]);
        bytes memory error;
        if (recipient == address(0)) {
            error = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, recipient);
        } else if (amount > balances[from]) {
            error = abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, actor(from), balances[from], amount
            );
        }
        if (error.length != 0) vm.expectRevert(error);
        vm.prank(actor(from));
        bool ok = token.transfer(recipient, amount);
        if (error.length != 0) {
            ++rejectedCalls;
        } else {
            assertTrue(ok);
            balances[from] -= amount;
            balances[to] += amount;
            ++successfulTransfers;
        }
    }

    function approve(uint8 ownerSeed, uint8 spenderSeed, uint256 amount, uint8 mode) external {
        uint256 owner = ownerSeed % ACTORS;
        uint256 spender = spenderSeed % ACTORS;
        address recipient = spenderSeed == type(uint8).max ? address(0) : actor(spender);
        if (mode % 3 == 0) amount = 0;
        if (mode % 3 == 1) amount = type(uint256).max;
        if (recipient == address(0)) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, recipient));
        }
        vm.prank(actor(owner));
        bool ok = token.approve(recipient, amount);
        if (recipient == address(0)) {
            ++rejectedCalls;
        } else {
            assertTrue(ok);
            allowances[owner][spender] = amount;
        }
    }

    function spend(uint8 ownerSeed, uint8 spenderSeed, uint8 toSeed, uint256 amountSeed, uint8 mode) external {
        uint256 owner = ownerSeed % ACTORS;
        uint256 spender = spenderSeed % ACTORS;
        uint256 to = toSeed % ACTORS;
        address recipient = toSeed == type(uint8).max ? address(0) : actor(to);
        uint256 allowed = allowances[owner][spender];
        uint256 ceiling = allowed < balances[owner] ? allowed : balances[owner];
        uint256 amount = _amount(amountSeed, mode, ceiling);
        bytes memory error;
        if (amount > allowed) {
            error = abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, actor(spender), allowed, amount
            );
        } else if (recipient == address(0)) {
            error = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, recipient);
        } else if (amount > balances[owner]) {
            error = abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, actor(owner), balances[owner], amount
            );
        }
        if (error.length != 0) vm.expectRevert(error);
        vm.prank(actor(spender));
        bool ok = token.transferFrom(actor(owner), recipient, amount);
        if (error.length != 0) {
            ++rejectedCalls;
        } else {
            assertTrue(ok);
            balances[owner] -= amount;
            balances[to] += amount;
            if (allowed != type(uint256).max) allowances[owner][spender] -= amount;
            ++successfulSpends;
        }
    }

    function observe(uint8 actorSeed, uint8 stateSeed, bool invalidState) external {
        uint256 who = actorSeed % ACTORS;
        uint8 state = invalidState ? uint8(bound(stateSeed, 8, 255)) : stateSeed % 8;
        bytes32 beforeProbabilities = keccak256(abi.encode(engine.getProbabilities()));
        bytes memory error;
        if (state >= 8) {
            error = abi.encodeWithSelector(QuantumEngine.InvalidState.selector, state);
        } else if (block.timestamp >= expectedStart + 3600) {
            error = abi.encodeWithSelector(QuantumEngine.EpochExpired.selector);
        } else if (submitted[who]) {
            error = abi.encodeWithSelector(QuantumEngine.AlreadyObserved.selector);
        } else if (balances[who] < 1 ether) {
            error = abi.encodeWithSelector(QuantumEngine.InsufficientBalance.selector);
        }
        if (error.length != 0) vm.expectRevert(error);
        vm.prank(actor(who));
        engine.observe(state);
        if (error.length != 0) {
            ++rejectedCalls;
        } else {
            submitted[who] = true;
            ++counts[state];
            ++successfulObservations;
        }
        assertEq(keccak256(abi.encode(engine.getProbabilities())), beforeProbabilities, "observe changes probabilities");
    }

    /// @dev Time can expire an epoch without advancing it, so late submissions remain reachable.
    function elapse(uint32 secondsSeed) external {
        vm.warp(block.timestamp + bound(secondsSeed, 0, 7200));
    }

    function advance(uint8 callerSeed) external {
        bool expired = block.timestamp >= expectedStart + 3600;
        bytes32 beforeProbabilities = keccak256(abi.encode(engine.getProbabilities()));
        if (!expired) vm.expectRevert(QuantumEngine.EpochStillActive.selector);
        vm.prank(actor(callerSeed % ACTORS));
        engine.advanceEpoch();
        if (expired) {
            ++expectedEpoch;
            expectedStart = block.timestamp;
            delete counts;
            delete submitted;
            ++successfulAdvances;
        } else {
            ++rejectedCalls;
            assertEq(keccak256(abi.encode(engine.getProbabilities())), beforeProbabilities);
        }
    }

    function _amount(uint256 seed, uint8 mode, uint256 ceiling) private pure returns (uint256) {
        mode %= 6;
        if (mode == 0) return 0;
        if (mode == 1) return 1;
        if (mode == 2) return ceiling;
        if (mode == 3) return ceiling + 1;
        if (mode == 4) return type(uint256).max;
        return bound(seed, 0, ceiling);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 96
/// forge-config: default.invariant.fail-on-revert = true
contract ObservatoryStatefulTest is StdInvariant, Test {
    ObservatorySequenceHandler internal handler;
    LaunchToken internal token;
    QuantumEngine internal engine;

    function setUp() public {
        vm.warp(1_000_000);
        handler = new ObservatorySequenceHandler();
        token = handler.token();
        engine = handler.engine();
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = ObservatorySequenceHandler.transfer.selector;
        selectors[1] = ObservatorySequenceHandler.approve.selector;
        selectors[2] = ObservatorySequenceHandler.spend.selector;
        selectors[3] = ObservatorySequenceHandler.observe.selector;
        selectors[4] = ObservatorySequenceHandler.elapse.selector;
        selectors[5] = ObservatorySequenceHandler.advance.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_fixedSupplyAndEveryBalanceMatchHistory() public view {
        uint256 sum;
        for (uint256 i; i < 6; ++i) {
            uint256 actual = token.balanceOf(handler.actor(i));
            assertEq(actual, handler.balances(i), "unexpected balance movement");
            sum += actual;
        }
        assertEq(sum, 1e27);
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(engine)), 0);
    }

    function invariant_allowancesMatchOnlyAuthorizedSpending() public view {
        for (uint256 owner; owner < 6; ++owner) {
            for (uint256 spender; spender < 6; ++spender) {
                assertEq(
                    token.allowance(handler.actor(owner), handler.actor(spender)), handler.allowances(owner, spender)
                );
            }
            assertEq(token.allowance(handler.actor(owner), address(engine)), type(uint256).max);
            assertEq(token.allowance(handler.actor(owner), address(0)), 0);
        }
    }

    function invariant_observationsAndEpochsMatchAcceptedHistory() public view {
        uint256 total;
        uint256 mass;
        uint256 participants;
        for (uint256 state; state < 8; ++state) {
            assertEq(engine.observationCounts(state), handler.counts(state));
            total += engine.observationCounts(state);
            mass += engine.probabilities(state);
        }
        for (uint256 i; i < 6; ++i) {
            assertEq(engine.hasObserved(handler.actor(i)), handler.submitted(i));
            if (handler.submitted(i)) ++participants;
        }
        assertEq(engine.observationCount(), total);
        assertEq(total, participants);
        assertEq(mass, 1_000_000);
        assertEq(engine.epoch(), handler.expectedEpoch());
        assertEq(engine.epochStartedAt(), handler.expectedStart());
        assertEq(engine.epochEndsAt(), handler.expectedStart() + 3600);
        assertEq(address(engine.token()), address(token));
    }

    /// @dev A deterministic walkthrough verifies that the random handler can reach both outcomes
    /// of each guard, successful nonzero delegated transfers, and renewed eligibility after expiry.
    function test_handlerExercisesTransfersRevocationAndChangingEligibility() public {
        handler.observe(1, 0, false); // One wei below eligibility.
        handler.transfer(0, 1, 0, 1);
        handler.observe(1, 7, false);
        handler.transfer(1, 4, 0, 2); // Empty the observed holder.
        handler.observe(1, 0, false); // Still a duplicate, even without a balance.
        handler.observe(4, 6, false);
        handler.approve(4, 5, 1 ether, 2);
        handler.spend(4, 5, 2, 0, 2);
        handler.approve(0, 5, 0, 1); // Unlimited approval.
        handler.spend(0, 5, 3, 0, 1);
        handler.approve(0, 5, 0, 0); // Revoke, then reject spending.
        handler.spend(0, 5, 3, 0, 1);
        handler.advance(5); // Early.
        handler.elapse(3600);
        handler.observe(2, 0, false); // Expired, despite sufficient funds.
        handler.advance(5); // Holder without tokens can advance.
        handler.observe(2, 0, false);
        assertEq(handler.successfulTransfers(), 2);
        assertEq(handler.successfulSpends(), 2);
        assertEq(handler.successfulObservations(), 3);
        assertEq(handler.successfulAdvances(), 1);
        assertEq(handler.rejectedCalls(), 5);
        invariant_fixedSupplyAndEveryBalanceMatchHistory();
        invariant_allowancesMatchOnlyAuthorizedSpending();
        invariant_observationsAndEpochsMatchAcceptedHistory();
    }
}
