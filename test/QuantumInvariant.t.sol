// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {QuantumEngine} from "../src/QuantumEngine.sol";
import {LaunchToken} from "../src/LaunchToken.sol";

contract ObservatoryHandler is Test {
    QuantumEngine public immutable engine;
    uint16[8] public expectedCounts;
    bool[16] public submitted;

    constructor(QuantumEngine engine_) {
        engine = engine_;
    }

    function observe(uint8 actorSeed, uint8 stateSeed) external {
        uint8 actor = actorSeed % 16;
        uint8 state = stateSeed % 8;
        address account = address(uint160(1000 + actor));
        if (submitted[actor]) {
            vm.expectRevert(QuantumEngine.AlreadyObserved.selector);
            vm.prank(account);
            engine.observe(state);
        } else {
            vm.prank(account);
            engine.observe(state);
            submitted[actor] = true;
            ++expectedCounts[state];
        }
    }

    function advance(uint32 delay) external {
        vm.warp(engine.epochEndsAt() + uint256(delay));
        engine.advanceEpoch();
        delete expectedCounts;
        delete submitted;
    }
}

contract QuantumInvariantTest is StdInvariant, Test {
    LaunchToken internal token;
    QuantumEngine internal engine;
    ObservatoryHandler internal handler;

    function setUp() public {
        token = new LaunchToken();
        engine = new QuantumEngine(address(token));
        handler = new ObservatoryHandler(engine);
        for (uint160 i; i < 16; ++i) {
            token.transfer(address(1000 + i), 1 ether);
        }
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = ObservatoryHandler.observe.selector;
        selectors[1] = ObservatoryHandler.advance.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_massCountsAndEligibilityAgreeWithHistory() public view {
        uint256 sum;
        uint256 count;
        for (uint256 i; i < 8; ++i) {
            sum += engine.probabilities(i);
            count += engine.observationCounts(i);
            assertEq(engine.observationCounts(i), handler.expectedCounts(i));
        }
        assertEq(sum, 1_000_000);
        assertEq(count, engine.observationCount());
        assertLe(count, 1024);
        for (uint160 i; i < 16; ++i) {
            address actor = address(1000 + i);
            assertEq(engine.hasObserved(actor), handler.submitted(i));
            assertEq(token.balanceOf(actor), 1 ether);
        }
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(address(this)), 1e27 - 16 ether);
        assertEq(token.balanceOf(address(engine)), 0);
    }
}
