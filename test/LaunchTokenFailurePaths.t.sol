// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {LaunchToken} from "src/LaunchToken.sol";

/// forge-config: default.fuzz.runs = 1000
contract LaunchTokenFailurePathsTest is Test {
    LaunchToken private token;
    address private constant HOLDER = address(0xA11CE);
    address private constant SPENDER = address(0xB0B);
    address private constant RECIPIENT = address(0xCAFE);

    function setUp() public {
        token = new LaunchToken();
        token.transfer(HOLDER, 1 ether);
    }

    function testFuzz_failedTransferFromRollsBackAllowanceSpend(uint256 amount) public {
        amount = bound(amount, 1 ether + 1, type(uint256).max);
        vm.prank(HOLDER);
        token.approve(SPENDER, amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, HOLDER, 1 ether, amount));
        vm.prank(SPENDER);
        token.transferFrom(HOLDER, RECIPIENT, amount);
        assertEq(token.allowance(HOLDER, SPENDER), amount);
        assertEq(token.balanceOf(HOLDER), 1 ether);
        assertEq(token.balanceOf(RECIPIENT), 0);
        assertEq(token.totalSupply(), 1e27);
    }

    function test_invalidReceiverRollsBackFiniteAllowance() public {
        vm.prank(HOLDER);
        token.approve(SPENDER, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(SPENDER);
        token.transferFrom(HOLDER, address(0), 1 ether);
        assertEq(token.allowance(HOLDER, SPENDER), 1 ether);
        assertEq(token.balanceOf(HOLDER), 1 ether);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), 1e27);
    }

    function test_selfTransferFromConsumesFiniteAllowanceWithoutMovingValue() public {
        vm.prank(HOLDER);
        token.approve(SPENDER, 1 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(HOLDER, HOLDER, 1 ether));
        assertEq(token.allowance(HOLDER, SPENDER), 0);
        assertEq(token.balanceOf(HOLDER), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        vm.prank(SPENDER);
        token.transferFrom(HOLDER, RECIPIENT, 1);
        assertEq(token.balanceOf(RECIPIENT), 0);
    }

    function test_fullSupplyRoundTripAndMaximumAttempt() public {
        vm.prank(HOLDER);
        token.transfer(address(this), 1 ether);
        token.transfer(HOLDER, 1e27);
        vm.prank(HOLDER);
        token.approve(SPENDER, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, HOLDER, 1e27, type(uint256).max)
        );
        vm.prank(SPENDER);
        token.transferFrom(HOLDER, address(this), type(uint256).max);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(HOLDER, address(this), 1e27));
        assertEq(token.balanceOf(address(this)), 1e27);
        assertEq(token.balanceOf(HOLDER), 0);
        assertEq(token.allowance(HOLDER, SPENDER), type(uint256).max);
        assertEq(token.totalSupply(), 1e27);
    }

    function test_zeroTransferFromNeedsNoAllowanceAndEmitsTransfer() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(HOLDER, RECIPIENT, 0);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(HOLDER, RECIPIENT, 0));
        assertEq(token.allowance(HOLDER, SPENDER), 0);
        assertEq(token.balanceOf(HOLDER), 1 ether);
        assertEq(token.balanceOf(RECIPIENT), 0);
    }

    event Transfer(address indexed from, address indexed to, uint256 amount);
}
