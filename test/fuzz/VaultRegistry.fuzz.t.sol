// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {VaultRegistry} from "../../src/VaultRegistry.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockERC4626Vault} from "../mocks/MockERC4626Vault.sol";

contract VaultRegistryFuzzTest is Test {
    MockERC20 asset;
    MockERC4626Vault vault;
    VaultRegistry registry;

    uint256 constant OBSERVATION_WINDOW = 10 days;
    uint256 constant PROBATION_AMOUNT = 100e6;

    function setUp() public {
        asset = new MockERC20("Mock USDC", "mUSDC", 6);
        vault = new MockERC4626Vault(asset, "Mock Vault", "mVLT");
        registry = new VaultRegistry(asset, OBSERVATION_WINDOW, PROBATION_AMOUNT, address(this));
        asset.mint(address(registry), 10 * PROBATION_AMOUNT);
        registry.register(address(vault));
    }

    /// @notice Weight must never exceed MAX_WEIGHT and must never decrease over time absent a
    /// detected loss - it's a monotonically non-decreasing function of elapsed time.
    function testFuzz_WeightNeverExceedsMaxAndIsMonotonic(uint256 t1, uint256 t2) public {
        t1 = bound(t1, 0, OBSERVATION_WINDOW * 5);
        t2 = bound(t2, t1, OBSERVATION_WINDOW * 5);

        vm.warp(block.timestamp + t1);
        uint256 w1 = registry.weightOf(address(vault));

        vm.warp(block.timestamp + (t2 - t1));
        uint256 w2 = registry.weightOf(address(vault));

        assertLe(w1, registry.MAX_WEIGHT());
        assertLe(w2, registry.MAX_WEIGHT());
        assertGe(w2, w1);
    }

    /// @notice Any detected loss, of any size, permanently zeroes weight no matter how much
    /// time has elapsed before or after it.
    function testFuzz_AnyLossZeroesWeightPermanently(uint256 elapsedBefore, uint256 lossAmount, uint256 elapsedAfter)
        public
    {
        elapsedBefore = bound(elapsedBefore, 0, OBSERVATION_WINDOW * 3);
        lossAmount = bound(lossAmount, 1, PROBATION_AMOUNT);
        elapsedAfter = bound(elapsedAfter, 0, OBSERVATION_WINDOW * 3);

        vm.warp(block.timestamp + elapsedBefore);
        vault.simulateLoss(lossAmount);
        registry.checkpoint(address(vault));

        assertEq(registry.weightOf(address(vault)), 0);

        vm.warp(block.timestamp + elapsedAfter);
        assertEq(registry.weightOf(address(vault)), 0);
    }
}
