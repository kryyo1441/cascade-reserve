// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {VaultRegistry} from "../../src/VaultRegistry.sol";
import {Cascade} from "../../src/Cascade.sol";
import {ReserveNote} from "../../src/ReserveNote.sol";
import {RepoFacility} from "../../src/RepoFacility.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockERC4626Vault} from "../mocks/MockERC4626Vault.sol";

/// @notice Randomly opens, fills, repurchases, rolls, and defaults repos. The invariant below
/// must hold throughout: the facility can never be short the collateral it owes to open
/// positions, and every repo's lifecycle fields stay internally consistent.
contract RepoHandler is Test {
    MockERC20 asset;
    ReserveNote l1;
    RepoFacility repo;

    address borrower = address(0xb0770);
    address[] lenders;

    uint256[] openRepoIds;
    uint256[] filledRepoIds;

    constructor(MockERC20 asset_, ReserveNote l1_, RepoFacility repo_) {
        asset = asset_;
        l1 = l1_;
        repo = repo_;

        for (uint256 i = 0; i < 3; i++) {
            lenders.push(address(uint160(0x1e0de5 + i)));
            vm.prank(lenders[i]);
            asset.approve(address(repo), type(uint256).max);
            asset.mint(lenders[i], 10_000_000e6);
        }

        asset.mint(borrower, 10_000_000e6);
        vm.prank(borrower);
        asset.approve(address(l1), type(uint256).max);
        vm.prank(borrower);
        l1.deposit(1_000_000e6, borrower);
        vm.prank(borrower);
        l1.approve(address(repo), type(uint256).max);
        vm.prank(borrower);
        asset.approve(address(repo), type(uint256).max);
    }

    function openRepo(uint256 noteFraction, uint256 cashFraction) public {
        uint256 bal = l1.balanceOf(borrower);
        if (bal == 0) return;
        noteFraction = bound(noteFraction, 1, 10_000);
        uint256 noteAmount = (bal * noteFraction) / 10_000;
        if (noteAmount == 0) return;

        uint256 collateralValue = l1.convertToAssets(noteAmount);
        uint256 maxCash = (collateralValue * (10_000 - repo.haircutBps())) / 10_000;
        if (maxCash < 2) return;

        cashFraction = bound(cashFraction, 1, 9_000); // keep well under the haircut ceiling
        uint256 cashAmount = (maxCash * cashFraction) / 10_000;
        if (cashAmount == 0) return;
        uint256 repurchasePrice = cashAmount + (cashAmount / 100) + 1; // always a positive premium

        vm.prank(borrower);
        try repo.openRepo(noteAmount, cashAmount, repurchasePrice) returns (uint256 repoId) {
            openRepoIds.push(repoId);
        } catch {}
    }

    function fillRepo(uint256 pick, uint256 lenderPick) public {
        if (openRepoIds.length == 0) return;
        uint256 idx = pick % openRepoIds.length;
        uint256 repoId = openRepoIds[idx];
        address lender = lenders[lenderPick % lenders.length];

        vm.prank(lender);
        try repo.fillRepo(repoId) {
            filledRepoIds.push(repoId);
            openRepoIds[idx] = openRepoIds[openRepoIds.length - 1];
            openRepoIds.pop();
        } catch {}
    }

    function repurchase(uint256 pick) public {
        if (filledRepoIds.length == 0) return;
        uint256 idx = pick % filledRepoIds.length;
        uint256 repoId = filledRepoIds[idx];

        vm.prank(borrower);
        try repo.repurchase(repoId) {
            filledRepoIds[idx] = filledRepoIds[filledRepoIds.length - 1];
            filledRepoIds.pop();
        } catch {}
    }

    function settleDefault(uint256 pick) public {
        if (filledRepoIds.length == 0) return;
        uint256 idx = pick % filledRepoIds.length;
        uint256 repoId = filledRepoIds[idx];

        try repo.settleDefault(repoId) {
            filledRepoIds[idx] = filledRepoIds[filledRepoIds.length - 1];
            filledRepoIds.pop();
        } catch {}
    }

    function warpTime(uint256 secondsForward) public {
        secondsForward = bound(secondsForward, 0, 3 days);
        vm.warp(block.timestamp + secondsForward);
    }

    function openCount() external view returns (uint256) {
        return openRepoIds.length;
    }

    function filledCount() external view returns (uint256) {
        return filledRepoIds.length;
    }
}

contract RepoFacilityInvariantTest is Test {
    MockERC20 asset;
    MockERC4626Vault vault;
    VaultRegistry registry;
    Cascade cascade;
    ReserveNote l1;
    ReserveNote l2;
    RepoFacility repo;
    RepoHandler handler;

    uint256 constant OBSERVATION_WINDOW = 10 days;
    uint256 constant TENOR = 1 days;

    function setUp() public {
        asset = new MockERC20("Mock USDC", "mUSDC", 6);
        vault = new MockERC4626Vault(asset, "Mock Vault", "mVLT");
        registry = new VaultRegistry(asset, OBSERVATION_WINDOW, 100e6, address(this));
        asset.mint(address(registry), 1000e6);

        cascade = new Cascade(asset, registry, 0, 1000, address(this));
        l1 = new ReserveNote(asset, "L1", "L1", cascade, true);
        l2 = new ReserveNote(asset, "L2", "L2", cascade, false);
        cascade.setTiers(address(l1), address(l2));

        repo = new RepoFacility(l1, asset, cascade, TENOR, 500, address(this));

        handler = new RepoHandler(asset, l1, repo);
        targetContract(address(handler));
    }

    /// @notice The facility must always hold at least as much L1-note collateral as it owes
    /// across every still-open position (open or filled, not yet closed).
    function invariant_FacilityHoldsEnoughCollateralForOpenRepos() public view {
        uint256 owed = 0;
        for (uint256 i = 0; i < repo.nextRepoId(); i++) {
            (,, uint256 noteAmount,,,,,, bool closed) = repo.repos(i);
            if (!closed) owed += noteAmount;
        }
        assertLe(owed, l1.balanceOf(address(repo)));
    }

    /// @notice A repo can never be simultaneously filled and unfilled, or closed while still
    /// reporting itself as not closed - the lifecycle flags are mutually consistent.
    function invariant_RepoLifecycleFlagsAreConsistent() public view {
        for (uint256 i = 0; i < repo.nextRepoId(); i++) {
            (address borrower_, address lender_,,,,, uint64 filledAt, bool filled, bool closed) = repo.repos(i);
            if (!filled) {
                assertEq(lender_, address(0));
                assertEq(filledAt, 0);
            }
            if (closed) {
                assertTrue(filled || borrower_ != address(0));
            }
        }
    }
}
