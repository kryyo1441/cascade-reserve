// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {VaultRegistry} from "../../src/VaultRegistry.sol";
import {Cascade} from "../../src/Cascade.sol";
import {ReserveNote} from "../../src/ReserveNote.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockERC4626Vault} from "../mocks/MockERC4626Vault.sol";

contract CascadeTest is Test {
    MockERC20 asset;
    MockERC4626Vault vault;
    VaultRegistry registry;
    Cascade cascade;
    ReserveNote l1;
    ReserveNote l2;

    address owner = makeAddr("owner");
    address senior = makeAddr("senior");
    address junior = makeAddr("junior");

    uint256 constant OBSERVATION_WINDOW = 10 days;
    uint256 constant PROBATION_AMOUNT = 100e6;
    uint256 constant L1_COUPON_RATE_WAD = 0; // disabled by default; see dedicated coupon test
    uint256 constant RESERVE_CUT_BPS = 1000; // 10%

    function setUp() public {
        asset = new MockERC20("Mock USDC", "mUSDC", 6);
        vault = new MockERC4626Vault(asset, "Mock Vault", "mVLT");
        registry = new VaultRegistry(asset, OBSERVATION_WINDOW, PROBATION_AMOUNT, owner);
        asset.mint(address(registry), 10 * PROBATION_AMOUNT);

        cascade = new Cascade(asset, registry, L1_COUPON_RATE_WAD, RESERVE_CUT_BPS, owner);
        l1 = new ReserveNote(asset, "Cascade L1", "csL1", cascade, true);
        l2 = new ReserveNote(asset, "Cascade L2", "csL2", cascade, false);

        vm.prank(owner);
        cascade.setTiers(address(l1), address(l2));

        asset.mint(senior, 1_000_000e6);
        asset.mint(junior, 1_000_000e6);
        vm.prank(senior);
        asset.approve(address(l1), type(uint256).max);
        vm.prank(junior);
        asset.approve(address(l2), type(uint256).max);

        registry.register(address(vault));
        vm.warp(block.timestamp + OBSERVATION_WINDOW); // fully trust the vault
    }

    function test_SeniorDeposit_CreditsFloorAndMintsShares() public {
        vm.prank(senior);
        uint256 shares = l1.deposit(1000e6, senior);

        assertEq(cascade.l1Floor(), 1000e6);
        assertEq(l1.balanceOf(senior), shares);
        assertEq(asset.balanceOf(address(cascade)), 1000e6);
    }

    function test_JuniorDeposit_IncreasesPoolNotFloor() public {
        vm.prank(junior);
        l2.deposit(500e6, junior);

        assertEq(cascade.l1Floor(), 0);
        assertEq(cascade.poolValue(), 500e6);
        assertEq(cascade.juniorClaim(), 500e6);
    }

    function test_Waterfall_ProfitFlowsEntirelyToJunior() public {
        vm.prank(senior);
        l1.deposit(1000e6, senior);
        vm.prank(junior);
        l2.deposit(1000e6, junior);

        // Actually put junior's capital to work in the vault (900 invested, 100 withheld as
        // reserve - decisions.md's reserve-cut design), then simulate the vault earning yield
        // by minting it extra assets directly (standard way to raise price-per-share in a mock).
        cascade.allocate(address(vault), 1000e6);
        asset.mint(address(vault), 200e6);

        // Senior floor is unaffected by pool profit: senior claim stays at its floor.
        assertEq(cascade.seniorClaim(), 1000e6);
        // All of the profit flows to junior, not just a pro-rata share of it.
        assertGt(cascade.juniorClaim(), 1000e6);
        assertEq(cascade.seniorClaim() + cascade.juniorClaim(), cascade.poolValue());
    }

    function test_Waterfall_LossHitsJuniorBeforeSenior() public {
        vm.prank(senior);
        l1.deposit(1000e6, senior);
        vm.prank(junior);
        l2.deposit(300e6, junior);

        // Only junior-sized capital goes into the vault; senior's capital stays untouched idle.
        cascade.allocate(address(vault), 300e6);

        // Wipe out the vault entirely (including the registry's own probation position in it) -
        // cascade's invested position is worth exactly 0 afterwards.
        vault.simulateLoss(asset.balanceOf(address(vault)));

        assertEq(cascade.juniorClaim(), 0);
        assertEq(cascade.seniorClaim(), 1000e6); // untouched: the loss never exceeded junior's size
    }

    function test_Waterfall_LossBeyondJuniorHitsSenior() public {
        vm.prank(senior);
        l1.deposit(1000e6, senior);
        vm.prank(junior);
        l2.deposit(100e6, junior);

        // Allocate more than junior alone contributed - the allocator pools capital without
        // tracking whose deposit is whose, so this pulls in some of senior's idle capital too.
        cascade.allocate(address(vault), 1000e6);

        // A large loss now eats through junior entirely and starts eating into senior's floor.
        vault.simulateLoss(asset.balanceOf(address(vault)) / 2);

        assertEq(cascade.juniorClaim(), 0);
        assertLt(cascade.seniorClaim(), 1000e6); // senior now also impaired
        assertEq(cascade.seniorClaim() + cascade.juniorClaim(), cascade.poolValue());
    }

    function test_SeniorWithdraw_PullsFromVaultWhenIdleInsufficient() public {
        vm.prank(senior);
        l1.deposit(1000e6, senior);

        cascade.allocate(address(vault), 900e6);

        uint256 balBefore = asset.balanceOf(senior);
        vm.prank(senior);
        l1.withdraw(950e6, senior, senior);

        assertEq(asset.balanceOf(senior) - balBefore, 950e6);
    }

    function test_Allocate_RevertsForNonFullyTrustedVault() public {
        MockERC4626Vault freshVault = new MockERC4626Vault(asset, "Fresh", "FR");
        registry.register(address(freshVault)); // just registered, zero weight

        vm.expectRevert(Cascade.VaultNotFullyTrusted.selector);
        cascade.allocate(address(freshVault), 1e6);
    }

    function test_Allocate_WithholdsReserveCutDuringCalm() public {
        vm.prank(junior);
        l2.deposit(1000e6, junior);

        cascade.allocate(address(vault), 1000e6);

        assertEq(cascade.reserveBuffer(), 100e6); // 10% of 1000
        // Vault also already holds the registry's own probation deposit from setUp.
        assertEq(asset.balanceOf(address(vault)), PROBATION_AMOUNT + 900e6);
    }

    function test_RevertWhen_NonTierCallsOnSeniorDeposit() public {
        vm.expectRevert(Cascade.NotTier.selector);
        cascade.onSeniorDeposit(1e6);
    }

    function test_RevertWhen_SettingTiersTwice() public {
        vm.prank(owner);
        vm.expectRevert(Cascade.TiersAlreadySet.selector);
        cascade.setTiers(address(l1), address(l2));
    }
}
