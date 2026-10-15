// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CompanyToken} from "src/CompanyToken.sol";

/// forge-config: default.fuzz.runs = 1000
contract CompanyTokenPropertiesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;
    CompanyToken private token;
    address private alice;
    address private bob;
    address private spender;

    function setUp() public {
        token = new CompanyToken();
        alice = makeAddr("property alice");
        bob = makeAddr("property bob");
        spender = makeAddr("property spender");
    }

    function test_OneBaseUnitCanBeTransferredAndReturnedExactly() public {
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumAmountCannotOverflowTransferAccounting() public {
        uint256 maximum = type(uint256).max;
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, maximum)
        );
        token.transfer(alice, maximum);
        assertTrue(token.approve(spender, maximum));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, maximum)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, maximum);
        assertEq(token.allowance(address(this), spender), maximum);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_OwnerMustApproveItselfForTransferFrom() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
        assertTrue(token.approve(address(this), 1));
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_InfiniteApprovalCanBeReplacedThenRevoked() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        token.approve(spender, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);

        token.approve(spender, type(uint256).max);
        token.approve(spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_ZeroApprovalToZeroSpenderRevertsWithoutAffectingValidApproval() public {
        token.approve(spender, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), spender), 10);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_OneSpenderCannotUseAnothersAllowance() public {
        token.approve(spender, 10);
        token.approve(bob, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 1, 2));
        vm.prank(bob);
        token.transferFrom(address(this), alice, 2);
        assertEq(token.allowance(address(this), spender), 10);
        assertEq(token.allowance(address(this), bob), 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 10));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.allowance(address(this), bob), 1);
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY - 10);
    }

    function testFuzz_TransferRoundTripRestoresBothBalances(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_InsufficientFiniteAllowanceIsAtomic(uint256 allowance, uint256 excess) public {
        allowance = bound(allowance, 0, type(uint256).max - 1);
        uint256 requested = allowance + bound(excess, 1, type(uint256).max - allowance);
        token.approve(spender, allowance);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowance, requested)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, requested);
        assertEq(token.allowance(address(this), spender), allowance);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_OverdrawPreservesFiniteOrInfiniteApproval(uint256 balance, uint256 amount, bool infinite) public {
        balance = bound(balance, 0, SUPPLY);
        amount = bound(amount, balance + 1, type(uint256).max);
        token.transfer(alice, balance);
        uint256 approval = infinite ? type(uint256).max : amount;
        vm.prank(alice);
        token.approve(spender, approval);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approval);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SplitSpendingExhaustsExactlyTheGrantedBudget(uint256 budget, uint256 first) public {
        budget = bound(budget, 0, SUPPLY);
        first = bound(first, 0, budget);
        token.approve(spender, budget);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, first));
        assertEq(token.allowance(address(this), spender), budget - first);
        assertTrue(token.transferFrom(address(this), bob, budget - first));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(address(this), alice, 1);
        vm.stopPrank();
        assertEq(token.balanceOf(alice), first);
        assertEq(token.balanceOf(bob), budget - first);
        assertEq(token.balanceOf(address(this)), SUPPLY - budget);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
