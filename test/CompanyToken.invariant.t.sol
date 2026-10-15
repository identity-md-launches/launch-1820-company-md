// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CompanyToken} from "src/CompanyToken.sol";

/// @dev The handler is the real deployer. Three other holders and the token itself
/// form a closed set of recipients, so summing their balances accounts for every token.
/// Ghost state follows requested operations, never values read back from the token.
contract CompanyTokenHandler is Test {
    uint256 public constant SUPPLY = 1_000_000_000 * 1e18;
    uint256 public constant ACTOR_COUNT = 4;
    CompanyToken public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor() {
        actors[0] = address(this);
        actors[1] = makeAddr("invariant alice");
        actors[2] = makeAddr("invariant bob");
        actors[3] = makeAddr("invariant carol");
        token = new CompanyToken();
        expectedBalance[address(this)] = SUPPLY;
        for (uint256 i = 1; i < ACTOR_COUNT; ++i) {
            assertTrue(token.transfer(actors[i], SUPPLY / ACTOR_COUNT));
            _move(address(this), actors[i], SUPPLY / ACTOR_COUNT);
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed); // Deliberately includes self-transfers.
        uint256 amount = _amount(amountSeed, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        _move(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed) external {
        // Mix replacement, revocation, finite and infinite approvals independently of balances.
        uint256 amount = amountSeed;
        if (amountSeed % 4 == 0) amount = 0;
        else if (amountSeed % 4 == 1) amount = type(uint256).max;
        else if (amountSeed % 4 == 2) amount = bound(amountSeed, 0, SUPPLY);
        _approve(_actor(ownerSeed), _actor(spenderSeed), amount);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 allowance = expectedAllowance[owner][spender];
        uint256 limit = expectedBalance[owner];
        if (allowance < limit) limit = allowance;
        uint256 amount = _amount(amountSeed, limit);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        _move(owner, to, amount);
        if (allowance != type(uint256).max) expectedAllowance[owner][spender] = allowance - amount;
    }

    function roundTrip(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 amount = _amount(amountSeed, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        // Check the intermediate leg as well: two cancelling errors must not hide a fee or burn.
        _move(from, to, amount);
        assertEq(token.balanceOf(from), expectedBalance[from]);
        assertEq(token.balanceOf(to), expectedBalance[to]);
        vm.prank(to);
        assertTrue(token.transfer(from, amount));
        _move(to, from, amount);
    }

    function donateToToken(uint256 fromSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        uint256 amount = _amount(amountSeed, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(address(token), amount));
        _move(from, address(token), amount);
    }

    function rejectedTransfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(_actor(toSeed), amount);
        // No ghost update: every balance and allowance must survive the rejected operation.
    }

    function rejectedTransferFrom(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 toSeed,
        uint256 amountSeed,
        bool insufficientBalance
    ) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 amount;
        if (insufficientBalance) {
            uint256 balance = expectedBalance[owner];
            amount = bound(amountSeed, balance + 1, type(uint256).max);
            _approve(owner, spender, amount);
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount)
            );
        } else {
            uint256 allowance = bound(amountSeed, 0, SUPPLY);
            _approve(owner, spender, allowance);
            amount = allowance + 1;
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowance, amount)
            );
        }
        vm.prank(spender);
        token.transferFrom(owner, _actor(toSeed), amount);
        // In particular, a balance failure must roll back any attempted allowance decrement.
    }

    function rejectedZeroAddress(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, uint8 mode) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        if (mode % 3 == 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
            vm.prank(owner);
            token.approve(address(0), amountSeed);
        } else if (mode % 3 == 1) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(owner);
            token.transfer(address(0), _amount(amountSeed, expectedBalance[owner]));
        } else {
            uint256 limit = expectedBalance[owner];
            uint256 allowance = expectedAllowance[owner][spender];
            if (allowance < limit) limit = allowance;
            uint256 amount = _amount(amountSeed, limit);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
        }
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % ACTOR_COUNT];
    }

    function _amount(uint256 seed, uint256 limit) internal pure returns (uint256) {
        // Exercise zero, one base unit, full balance/allowance and arbitrary partial amounts often.
        if (seed % 4 == 0) return 0;
        if (seed % 4 == 1) return limit == 0 ? 0 : 1;
        if (seed % 4 == 2) return limit;
        return bound(seed, 0, limit);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _move(address from, address to, uint256 amount) internal {
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 64
/// forge-config: default.invariant.fail-on-revert = true
contract CompanyTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;
    CompanyTokenHandler private handler;
    CompanyToken private token;

    function setUp() public {
        handler = new CompanyTokenHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.roundTrip.selector;
        selectors[4] = handler.donateToToken.selector;
        selectors[5] = handler.rejectedTransfer.selector;
        selectors[6] = handler.rejectedTransferFrom.selector;
        selectors[7] = handler.rejectedZeroAddress.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_FixedSupplyEqualsAllBalances() public view {
        uint256 held = token.balanceOf(address(token));
        for (uint256 i; i < handler.ACTOR_COUNT(); ++i) {
            held += token.balanceOf(handler.actors(i));
        }
        assertEq(token.totalSupply(), SUPPLY, "supply changed after constructor");
        assertEq(held, SUPPLY, "tokens were created, destroyed or leaked outside the recipient set");
        assertEq(token.balanceOf(address(0)), 0);
    }

    function invariant_BalancesMatchRequestedMovements() public view {
        for (uint256 i; i < handler.ACTOR_COUNT(); ++i) {
            address actor = handler.actors(i);
            assertEq(token.balanceOf(actor), handler.expectedBalance(actor), "holder balance differs from ledger");
        }
        assertEq(token.balanceOf(address(token)), handler.expectedBalance(address(token)));
    }

    function invariant_OnlyAuthorizedSpendingChangesAllowances() public view {
        for (uint256 i; i < handler.ACTOR_COUNT(); ++i) {
            address owner = handler.actors(i);
            assertEq(token.allowance(owner, address(0)), 0);
            for (uint256 j; j < handler.ACTOR_COUNT(); ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(owner, spender),
                    handler.expectedAllowance(owner, spender),
                    "approval replacement, spending or rollback differs from ledger"
                );
            }
        }
    }
}
