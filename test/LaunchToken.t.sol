// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {LaunchToken} from "../src/LaunchToken.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract LaunchTokenTest is Test {
    LaunchToken internal token;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    uint256 internal constant SUPPLY = 1e27;

    function setUp() public {
        token = new LaunchToken();
    }

    function test_metadataAndFixedSupply() public view {
        assertEq(token.name(), "Quantum Observatory");
        assertEq(token.symbol(), "QOBS");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testFuzz_transferConservesSupply(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(ALICE, amount));
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, amount));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromSpendsOnlyAllowance() public {
        token.approve(ALICE, 5 ether);
        vm.prank(ALICE);
        assertTrue(token.transferFrom(address(this), BOB, 3 ether));
        assertEq(token.allowance(address(this), ALICE), 2 ether);
        assertEq(token.balanceOf(BOB), 3 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 2 ether, 3 ether)
        );
        vm.prank(ALICE);
        token.transferFrom(address(this), BOB, 3 ether);
        assertEq(token.balanceOf(BOB), 3 ether);
    }

    function test_allowanceReplacementRevocationAndInfiniteAllowance() public {
        token.approve(ALICE, 5 ether);
        token.approve(ALICE, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transferFrom(address(this), BOB, 1);
        token.approve(ALICE, type(uint256).max);
        vm.prank(ALICE);
        token.transferFrom(address(this), BOB, 1);
        assertEq(token.allowance(address(this), ALICE), type(uint256).max);
    }

    function test_zeroAndSelfTransfers() public {
        token.transfer(ALICE, 0);
        token.transfer(address(this), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_invalidTransfersAndApprovalRevert() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transfer(BOB, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_noAdministrativeOrMintEntryPointsEvenForDeployer() public {
        bytes4[9] memory selectors = [
            bytes4(keccak256("mint(address,uint256)")),
            bytes4(keccak256("burn(uint256)")),
            bytes4(keccak256("pause()")),
            bytes4(keccak256("setOwner(address)")),
            bytes4(keccak256("transferOwnership(address)")),
            bytes4(keccak256("upgradeTo(address)")),
            bytes4(keccak256("initialize(address)")),
            bytes4(keccak256("setFee(uint256)")),
            bytes4(keccak256("setMinter(address)"))
        ];
        for (uint256 i; i < selectors.length; ++i) {
            (bool success,) = address(token).call(abi.encodeWithSelector(selectors[i], ALICE, SUPPLY));
            assertFalse(success);
            vm.prank(ALICE);
            (success,) = address(token).call(abi.encodeWithSelector(selectors[i], ALICE, SUPPLY));
            assertFalse(success);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_transferEmitsExactEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 1 ether);
        token.transfer(ALICE, 1 ether);
    }

    event Transfer(address indexed from, address indexed to, uint256 value);
}
