// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {VaultRegistry} from "../../src/VaultRegistry.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockERC4626Vault} from "../mocks/MockERC4626Vault.sol";

contract VaultRegistryTest is Test {
    MockERC20 asset;
    MockERC4626Vault vault;
    VaultRegistry registry;

    address owner = makeAddr("owner");
    address alice = makeAddr("alice");

    uint256 constant OBSERVATION_WINDOW = 10 days;
    uint256 constant PROBATION_AMOUNT = 100e6; // 100 USDC-like units

    function setUp() public {
        asset = new MockERC20("Mock USDC", "mUSDC", 6);
        vault = new MockERC4626Vault(asset, "Mock Vault", "mVLT");
        registry = new VaultRegistry(asset, OBSERVATION_WINDOW, PROBATION_AMOUNT, owner);

        // Fund the registry with enough asset to run probation deposits, as documented in
        // VaultRegistry's NatSpec (owner/treasury responsibility, not enforced on-chain).
        asset.mint(address(registry), 10 * PROBATION_AMOUNT);
    }

    function test_Register_StartsAtZeroWeight() public {
        vm.prank(alice);
        registry.register(address(vault));

        assertEq(registry.weightOf(address(vault)), 0);
    }

    function test_Register_IsPermissionless() public {
        // Anyone, not just the owner, can register a vault.
        vm.prank(alice);
        registry.register(address(vault));

        (bool registered,,,,) = registry.vaults(address(vault));
        assertTrue(registered);
    }

    function test_Register_DepositsProbationAmountIntoVault() public {
        registry.register(address(vault));

        assertEq(asset.balanceOf(address(vault)), PROBATION_AMOUNT);
        assertEq(vault.balanceOf(address(registry)), vault.convertToShares(PROBATION_AMOUNT));
    }

    function test_RevertWhen_RegisteringTwice() public {
        registry.register(address(vault));

        vm.expectRevert(VaultRegistry.AlreadyRegistered.selector);
        registry.register(address(vault));
    }

    function test_RevertWhen_AssetMismatch() public {
        MockERC20 otherAsset = new MockERC20("Other", "OTH", 18);
        MockERC4626Vault badVault = new MockERC4626Vault(otherAsset, "Bad Vault", "bVLT");

        vm.expectRevert(VaultRegistry.AssetMismatch.selector);
        registry.register(address(badVault));
    }

    function test_Weight_GrowsLinearlyOverObservationWindow() public {
        registry.register(address(vault));

        vm.warp(block.timestamp + OBSERVATION_WINDOW / 2);
        uint256 halfwayWeight = registry.weightOf(address(vault));
        assertApproxEqAbs(halfwayWeight, registry.MAX_WEIGHT() / 2, 1);

        vm.warp(block.timestamp + OBSERVATION_WINDOW / 2);
        assertEq(registry.weightOf(address(vault)), registry.MAX_WEIGHT());
    }

    function test_Weight_CapsAtMaxAfterWindow() public {
        registry.register(address(vault));

        vm.warp(block.timestamp + OBSERVATION_WINDOW * 10);
        assertEq(registry.weightOf(address(vault)), registry.MAX_WEIGHT());
    }

    function test_Checkpoint_DetectsLossAndPermanentlyZeroesWeight() public {
        registry.register(address(vault));
        vm.warp(block.timestamp + OBSERVATION_WINDOW); // fully trusted

        assertEq(registry.weightOf(address(vault)), registry.MAX_WEIGHT());

        // The vault silently loses half its assets (insolvency / attacker vault scenario).
        vault.simulateLoss(PROBATION_AMOUNT / 2);

        vm.prank(alice); // checkpoint is permissionless
        registry.checkpoint(address(vault));

        assertEq(registry.weightOf(address(vault)), 0);

        // Weight stays zero even as more time passes - it's a permanent slash, not decay.
        vm.warp(block.timestamp + OBSERVATION_WINDOW * 100);
        assertEq(registry.weightOf(address(vault)), 0);
    }

    function test_Checkpoint_NoLossLeavesWeightUnaffected() public {
        registry.register(address(vault));
        vm.warp(block.timestamp + OBSERVATION_WINDOW / 2);

        uint256 weightBefore = registry.weightOf(address(vault));
        registry.checkpoint(address(vault));
        assertEq(registry.weightOf(address(vault)), weightBefore);
    }

    function test_RevertWhen_CheckpointingUnregisteredVault() public {
        vm.expectRevert(VaultRegistry.NotRegistered.selector);
        registry.checkpoint(address(vault));
    }

    function test_AllVaults_ListsRegisteredVaults() public {
        registry.register(address(vault));
        address[] memory list = registry.allVaults();
        assertEq(list.length, 1);
        assertEq(list[0], address(vault));
    }
}
