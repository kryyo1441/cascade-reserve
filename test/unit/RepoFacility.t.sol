// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {VaultRegistry} from "../../src/VaultRegistry.sol";
import {Cascade} from "../../src/Cascade.sol";
import {ReserveNote} from "../../src/ReserveNote.sol";
import {RepoFacility} from "../../src/RepoFacility.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockERC4626Vault} from "../mocks/MockERC4626Vault.sol";

contract RepoFacilityTest is Test {
    MockERC20 asset;
    MockERC4626Vault vault;
    VaultRegistry registry;
    Cascade cascade;
    ReserveNote l1;
    ReserveNote l2;
    RepoFacility repo;

    address owner = makeAddr("owner");
    address borrower = makeAddr("borrower");
    address lender = makeAddr("lender");

    uint256 constant OBSERVATION_WINDOW = 10 days;
    uint256 constant TENOR = 1 days;
    uint256 constant HAIRCUT_BPS = 500; // 5%

    // Note shares (not asset units - ReserveNote uses a 6-decimal virtual-share offset) worth
    // approximately 1000e6 of the underlying asset at setUp time.
    uint256 notesWorth1000;

    function setUp() public {
        asset = new MockERC20("Mock USDC", "mUSDC", 6);
        vault = new MockERC4626Vault(asset, "Mock Vault", "mVLT");
        registry = new VaultRegistry(asset, OBSERVATION_WINDOW, 100e6, owner);
        asset.mint(address(registry), 1000e6);

        cascade = new Cascade(asset, registry, 0, 1000, owner);
        l1 = new ReserveNote(asset, "Cascade L1", "csL1", cascade, true);
        l2 = new ReserveNote(asset, "Cascade L2", "csL2", cascade, false);
        vm.prank(owner);
        cascade.setTiers(address(l1), address(l2));

        repo = new RepoFacility(l1, asset, cascade, TENOR, HAIRCUT_BPS, owner);

        asset.mint(borrower, 1_000_000e6);
        asset.mint(lender, 1_000_000e6);

        vm.prank(borrower);
        asset.approve(address(l1), type(uint256).max);
        vm.prank(borrower);
        l1.deposit(10_000e6, borrower);

        notesWorth1000 = l1.convertToShares(1000e6);

        vm.prank(borrower);
        l1.approve(address(repo), type(uint256).max);
        vm.prank(borrower);
        asset.approve(address(repo), type(uint256).max);
        vm.prank(lender);
        asset.approve(address(repo), type(uint256).max);
    }

    function _openAndFill(uint256 noteAmount, uint256 cashAmount, uint256 repurchasePrice)
        internal
        returns (uint256 repoId)
    {
        vm.prank(borrower);
        repoId = repo.openRepo(noteAmount, cashAmount, repurchasePrice);
        vm.prank(lender);
        repo.fillRepo(repoId);
    }

    function test_OpenRepo_PullsNoteCollateral() public {
        vm.prank(borrower);
        uint256 repoId = repo.openRepo(notesWorth1000, 900e6, 920e6);

        assertEq(l1.balanceOf(address(repo)), notesWorth1000);
        assertEq(_borrowerOf(repoId), borrower);
        assertFalse(_filledOf(repoId));
        assertFalse(_closedOf(repoId));
    }

    function test_RevertWhen_OpeningBeyondHaircut() public {
        // ~1000 worth of notes at a 5% haircut allows at most 950 cash.
        vm.prank(borrower);
        vm.expectRevert(RepoFacility.HaircutExceeded.selector);
        repo.openRepo(notesWorth1000, 960e6, 980e6);
    }

    function test_FillRepo_PaysBorrowerAndRecordsFill() public {
        uint256 balBefore = asset.balanceOf(borrower);
        uint256 repoId = _openAndFill(notesWorth1000, 900e6, 920e6);

        assertEq(asset.balanceOf(borrower) - balBefore, 900e6);
        assertEq(repo.fillsCount(), 1);
        assertTrue(_filledOf(repoId));
    }

    function test_Repurchase_ReturnsNoteAndPaysLender() public {
        uint256 shareBalBefore = l1.balanceOf(borrower);
        uint256 repoId = _openAndFill(notesWorth1000, 900e6, 920e6);
        uint256 lenderBalBefore = asset.balanceOf(lender);

        vm.prank(borrower);
        repo.repurchase(repoId);

        assertEq(l1.balanceOf(borrower), shareBalBefore); // note fully returned
        assertEq(asset.balanceOf(lender) - lenderBalBefore, 920e6);
        assertTrue(_closedOf(repoId));
    }

    function test_RevertWhen_NonBorrowerRepurchases() public {
        uint256 repoId = _openAndFill(notesWorth1000, 900e6, 920e6);
        vm.prank(lender);
        vm.expectRevert(RepoFacility.NotBorrower.selector);
        repo.repurchase(repoId);
    }

    function test_SettleDefault_TransfersNoteToLenderDeterministically() public {
        uint256 repoId = _openAndFill(notesWorth1000, 900e6, 920e6);

        vm.warp(block.timestamp + TENOR + 1);
        repo.settleDefault(repoId);

        assertEq(l1.balanceOf(lender), notesWorth1000);
        assertTrue(_closedOf(repoId));
    }

    function test_RevertWhen_SettlingDefaultBeforeExpiry() public {
        uint256 repoId = _openAndFill(notesWorth1000, 900e6, 920e6);
        vm.expectRevert(RepoFacility.NotYetExpired.selector);
        repo.settleDefault(repoId);
    }

    function test_Roll_KeepsCollateralInFacilityAndReopensTerms() public {
        uint256 repoId = _openAndFill(notesWorth1000, 900e6, 920e6);

        vm.prank(borrower);
        repo.roll(repoId, 910e6, 935e6);

        assertEq(l1.balanceOf(address(repo)), notesWorth1000); // never left
        assertEq(_cashAmountOf(repoId), 910e6);
        assertEq(_repurchasePriceOf(repoId), 935e6);
        assertFalse(_filledOf(repoId)); // needs a fresh fill
    }

    function test_ReserveRate_ReflectsVolumeWeightedAverageOfRecentFills() public {
        _openAndFill(notesWorth1000, 900e6, 920e6);

        uint256 rate = repo.reserveRate();
        assertGt(rate, 0);
    }

    function test_Haircut_CanBeLoweredFreely() public {
        vm.prank(owner);
        repo.setHaircutBps(200);

        assertEq(repo.haircutBps(), 200);
    }

    function test_RevertWhen_RaisingHaircutDuringStress() public {
        // Drive the Cascade into a stressed state: senior deposits far more than the pool
        // (idle + vaults) can actually back, by having the vault swallow a large loss.
        vm.prank(borrower);
        l1.deposit(100_000e6, borrower); // on top of the 10_000e6 from setUp
        registry.register(address(vault));
        vm.warp(block.timestamp + OBSERVATION_WINDOW);
        cascade.allocate(address(vault), 50_000e6);
        vault.simulateLoss(asset.balanceOf(address(vault)));

        assertTrue(cascade.isStressed());

        vm.prank(owner);
        vm.expectRevert(RepoFacility.HaircutCannotRiseDuringStress.selector);
        repo.setHaircutBps(HAIRCUT_BPS + 100);
    }

    function _borrowerOf(uint256 repoId) internal view returns (address b) {
        (b,,,,,,,,) = repo.repos(repoId);
    }

    function _filledOf(uint256 repoId) internal view returns (bool filled) {
        (,,,,,,, filled,) = repo.repos(repoId);
    }

    function _closedOf(uint256 repoId) internal view returns (bool closed) {
        (,,,,,,,, closed) = repo.repos(repoId);
    }

    function _cashAmountOf(uint256 repoId) internal view returns (uint256 cashAmount) {
        (,, , cashAmount,,,,,) = repo.repos(repoId);
    }

    function _repurchasePriceOf(uint256 repoId) internal view returns (uint256 repurchasePrice) {
        (,,, , repurchasePrice,,,,) = repo.repos(repoId);
    }
}
