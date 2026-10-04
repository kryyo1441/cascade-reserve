// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {VaultRegistry} from "../../src/VaultRegistry.sol";
import {Cascade} from "../../src/Cascade.sol";
import {ReserveNote} from "../../src/ReserveNote.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockERC4626Vault} from "../mocks/MockERC4626Vault.sol";

/// @notice Handler performs random deposits/withdrawals/allocations/losses against the Cascade,
/// and the invariant checks below must hold after every single one of them.
contract CascadeHandler is Test {
    MockERC20 public asset;
    MockERC4626Vault public vault;
    Cascade public cascade;
    ReserveNote public l1;
    ReserveNote public l2;

    address senior = address(0x5e2101);
    address junior = address(0x6701102);

    constructor(MockERC20 asset_, MockERC4626Vault vault_, Cascade cascade_, ReserveNote l1_, ReserveNote l2_) {
        asset = asset_;
        vault = vault_;
        cascade = cascade_;
        l1 = l1_;
        l2 = l2_;

        asset.mint(senior, 1_000_000_000e6);
        asset.mint(junior, 1_000_000_000e6);
        vm.prank(senior);
        asset.approve(address(l1), type(uint256).max);
        vm.prank(junior);
        asset.approve(address(l2), type(uint256).max);
    }

    function depositSenior(uint256 amount) public {
        amount = bound(amount, 0, 10_000_000e6);
        if (amount == 0) return;
        vm.prank(senior);
        l1.deposit(amount, senior);
    }

    function depositJunior(uint256 amount) public {
        amount = bound(amount, 0, 10_000_000e6);
        if (amount == 0) return;
        vm.prank(junior);
        l2.deposit(amount, junior);
    }

    function withdrawSenior(uint256 shareBps) public {
        uint256 bal = l1.balanceOf(senior);
        if (bal == 0) return;
        shareBps = bound(shareBps, 0, 10_000);
        uint256 shares = (bal * shareBps) / 10_000;
        uint256 maxAssets = l1.previewRedeem(shares);
        if (maxAssets == 0) return;
        uint256 maxAllowed = l1.maxWithdraw(senior);
        if (maxAssets > maxAllowed) maxAssets = maxAllowed;
        if (maxAssets == 0) return;
        vm.prank(senior);
        l1.withdraw(maxAssets, senior, senior);
    }

    function withdrawJunior(uint256 shareBps) public {
        uint256 bal = l2.balanceOf(junior);
        if (bal == 0) return;
        shareBps = bound(shareBps, 0, 10_000);
        uint256 shares = (bal * shareBps) / 10_000;
        uint256 maxAssets = l2.previewRedeem(shares);
        if (maxAssets == 0) return;
        uint256 maxAllowed = l2.maxWithdraw(junior);
        if (maxAssets > maxAllowed) maxAssets = maxAllowed;
        if (maxAssets == 0) return;
        vm.prank(junior);
        l2.withdraw(maxAssets, junior, junior);
    }

    function allocateIntoVault(uint256 amount) public {
        uint256 idle = asset.balanceOf(address(cascade)) - cascade.reserveBuffer();
        if (idle == 0) return;
        amount = bound(amount, 0, idle);
        if (amount == 0) return;
        cascade.allocate(address(vault), amount);
    }

    function loseVaultValue(uint256 amount) public {
        uint256 bal = asset.balanceOf(address(vault));
        if (bal == 0) return;
        amount = bound(amount, 0, bal);
        if (amount == 0) return;
        vault.simulateLoss(amount);
    }

    function warpTime(uint256 secondsForward) public {
        secondsForward = bound(secondsForward, 0, 30 days);
        vm.warp(block.timestamp + secondsForward);
    }
}

contract CascadeWaterfallInvariantTest is Test {
    MockERC20 asset;
    MockERC4626Vault vault;
    VaultRegistry registry;
    Cascade cascade;
    ReserveNote l1;
    ReserveNote l2;
    CascadeHandler handler;

    uint256 constant OBSERVATION_WINDOW = 10 days;

    function setUp() public {
        asset = new MockERC20("Mock USDC", "mUSDC", 6);
        vault = new MockERC4626Vault(asset, "Mock Vault", "mVLT");
        registry = new VaultRegistry(asset, OBSERVATION_WINDOW, 100e6, address(this));
        asset.mint(address(registry), 1000e6);

        cascade = new Cascade(asset, registry, 0, 1000, address(this));
        l1 = new ReserveNote(asset, "L1", "L1", cascade, true);
        l2 = new ReserveNote(asset, "L2", "L2", cascade, false);
        cascade.setTiers(address(l1), address(l2));

        registry.register(address(vault));
        vm.warp(block.timestamp + OBSERVATION_WINDOW);

        handler = new CascadeHandler(asset, vault, cascade, l1, l2);
        targetContract(address(handler));
    }

    /// @notice The core safety property of the whole waterfall: the two tiers can never, between
    /// them, lay claim to more than the Cascade actually holds (counting the reserve only when
    /// it's genuinely released under stress).
    function invariant_TotalClaimsNeverExceedPoolValue() public view {
        assertLe(cascade.seniorClaim() + cascade.juniorClaim(), cascade.poolValue());
    }

    /// @notice And the two claims must exactly exhaust the pool - no value silently vanishes
    /// between the senior floor calculation and the junior residual.
    function invariant_ClaimsExactlyPartitionPoolValue() public view {
        assertEq(cascade.seniorClaim() + cascade.juniorClaim(), cascade.poolValue());
    }

    /// @notice Junior can never have a negative-equivalent claim; it's floored at zero even
    /// under total loss.
    function invariant_JuniorClaimNeverUnderflows() public view {
        assertGe(cascade.juniorClaim(), 0);
    }
}
