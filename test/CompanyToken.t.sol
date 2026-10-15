// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CompanyToken} from "../src/CompanyToken.sol";

/// @dev Models deployment and distribution by a contract rather than an EOA.
contract TokenFactoryProbe {
    function deploy(bytes32 salt) external returns (CompanyToken) {
        return new CompanyToken{salt: salt}();
    }

    function distribute(CompanyToken token, address recipient, uint256 amount) external {
        require(token.transfer(recipient, amount));
    }
}

contract CompanyTokenTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 1e18;
    CompanyToken private token;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        token = new CompanyToken();
    }

    function test_MetadataAndInitialSupply() public view {
        assertEq(token.name(), "Company.md");
        assertEq(token.symbol(), "COMD");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_ConstructorEmitsOneMintEvent() public {
        vm.recordLogs();
        vm.prank(alice);
        CompanyToken deployed = new CompanyToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(deployed));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(alice))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
        assertEq(deployed.balanceOf(alice), SUPPLY);
        assertEq(deployed.balanceOf(address(this)), 0);
    }

    function test_ContractDeploymentAndLaunchDistributionArriveWhole() public {
        TokenFactoryProbe factory = new TokenFactoryProbe();
        CompanyToken deployed = factory.deploy(keccak256("company launch"));
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(address(this)), 0);
        uint256 swarm = SUPPLY / 10;
        uint256 pool = SUPPLY * 88 / 100;
        uint256 remainder = SUPPLY - swarm - pool;
        address distributor = makeAddr("distributor");
        address poolManager = makeAddr("pool manager");
        factory.distribute(deployed, distributor, swarm);
        factory.distribute(deployed, poolManager, pool);
        factory.distribute(deployed, alice, remainder);
        assertEq(deployed.balanceOf(distributor), swarm);
        assertEq(deployed.balanceOf(poolManager), pool);
        assertEq(deployed.balanceOf(alice), remainder);
        assertEq(deployed.balanceOf(address(factory)), 0);
        vm.prank(distributor);
        assertTrue(deployed.transfer(bob, swarm));
        assertEq(deployed.balanceOf(bob), swarm);
        assertEq(deployed.balanceOf(distributor), 0);
        // Exact pool-manager transfers model the ERC-20 settlement boundary, not a DEX swap.
        vm.prank(poolManager);
        assertTrue(deployed.transfer(bob, 1e18));
        vm.prank(bob);
        assertTrue(deployed.transfer(poolManager, 1e18));
        assertEq(deployed.balanceOf(poolManager), pool);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_TransferEmitsEventAndDeliversExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 42e18);
        assertTrue(token.transfer(alice, 42e18));
        assertEq(token.balanceOf(alice), 42e18);
        assertEq(token.balanceOf(address(this)), SUPPLY - 42e18);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferEntireSupply() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferToZeroRevertsEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferMoreThanBalanceReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + 1)
        );
        token.transfer(alice, SUPPLY + 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_ApproveEmitsEventAndCanReplaceOrRevoke() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 100);
        assertTrue(token.approve(spender, 100));
        assertEq(token.allowance(address(this), spender), 100);
        assertTrue(token.approve(spender, 7));
        assertEq(token.allowance(address(this), spender), 7);
        assertTrue(token.approve(spender, 0));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
    }

    function test_ApprovalIsIndependentOfBalanceAndOtherOwners() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, SUPPLY));
        assertEq(token.allowance(alice, spender), SUPPLY);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.allowance(alice, bob), 0);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_ApproveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_TransferFromSpendsAllowanceAndEmitsTransfer() public {
        token.approve(spender, 100);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 60);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 60));
        assertEq(token.allowance(address(this), spender), 40);
        assertEq(token.balanceOf(alice), 60);
        assertEq(token.balanceOf(address(this)), SUPPLY - 60);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 40));
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(bob), 40);
    }

    function test_InfiniteAllowanceIsNotDecreased() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function test_TransferFromWithoutAllowanceReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_TransferFromAboveAllowanceReverts() public {
        token.approve(spender, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 10, 11));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 11);
        assertEq(token.allowance(address(this), spender), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_InsufficientBalanceRestoresSpentAllowanceOnRevert() public {
        vm.prank(alice);
        token.approve(spender, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 50));
        vm.prank(spender);
        token.transferFrom(alice, bob, 50);
        assertEq(token.allowance(alice, spender), 100);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_InvalidRecipientRestoresAllowanceOnRevert() public {
        token.approve(spender, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 50);
        assertEq(token.allowance(address(this), spender), 100);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ZeroTransferFromNeedsNoAllowance() public {
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_ZeroTransferFromZeroSenderReverts() public {
        // OpenZeppelin validates the owner while spending even a zero allowance,
        // before reaching its transfer sender check.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.transferFrom(address(0), bob, 0);
    }

    function test_SelfTransferFromConsumesAllowanceWithoutMovingBalance() public {
        token.approve(spender, 100);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 100));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_DeployerCannotTakeTokensBackWithoutApproval() public {
        token.transfer(alice, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(alice, address(this), 1);
        assertEq(token.balanceOf(alice), 100);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100));
        assertEq(token.balanceOf(bob), 100);
    }

    function test_NoMintBurnFreezeOrUpgradeEntryPoints() public {
        token.transfer(alice, 100);
        bytes[] memory calls = new bytes[](9);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, SUPPLY);
        calls[1] = abi.encodeWithSignature("mint(uint256)", SUPPLY);
        calls[2] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[3] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1);
        calls[4] = abi.encodeWithSignature("pause()");
        calls[5] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[6] = abi.encodeWithSignature("transferOwnership(address)", bob);
        calls[7] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[8] = abi.encodeWithSignature("initialize(address)", bob);
        for (uint256 i; i < calls.length; ++i) {
            (bool ok,) = address(token).call(calls[i]);
            assertFalse(ok, "deployer reached an unsupported privileged operation");
            vm.prank(bob);
            (ok,) = address(token).call(calls[i]);
            assertFalse(ok, "stranger reached an unsupported privileged operation");
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.balanceOf(bob), 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100));
    }

    function test_RuntimeHasNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden opcode");
        }
    }

    function testFuzz_TransfersConserveSupply(uint256 first, uint256 second) public {
        first = bound(first, 0, SUPPLY);
        second = bound(second, 0, first);
        assertTrue(token.transfer(alice, first));
        vm.prank(alice);
        assertTrue(token.transfer(bob, second));
        assertEq(token.balanceOf(address(this)), SUPPLY - first);
        assertEq(token.balanceOf(alice), first - second);
        assertEq(token.balanceOf(bob), second);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(alice) + token.balanceOf(bob), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DelegatedTransferAccountsExactly(uint256 approved, uint256 spent) public {
        approved = bound(approved, 0, SUPPLY);
        spent = bound(spent, 0, approved);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, spent));
        assertEq(token.allowance(address(this), spender), approved - spent);
        assertEq(token.balanceOf(address(this)), SUPPLY - spent);
        assertEq(token.balanceOf(bob), spent);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_OverdrawRevertsWithoutChangingState(uint256 amount) public {
        amount = bound(amount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(bob, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ArbitraryRecipientGetsExactTransfer(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        amount = bound(amount, 0, SUPPLY);
        uint256 beforeBalance = token.balanceOf(recipient);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), beforeBalance + amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
