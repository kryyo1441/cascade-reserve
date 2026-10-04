// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReserveNote} from "../../src/ReserveNote.sol";
import {RepoFacility} from "../../src/RepoFacility.sol";

/// @notice Phase 3: opens an L1 repo as the borrower, then fills it from a second funded
/// account as the lender - producing a real, two-party, transaction-based rate observation
/// (the actual point of the facility; source.md's whole argument for building it).
///
/// Required env vars: PRIVATE_KEY (borrower), LENDER_PRIVATE_KEY, USDC, L1, REPO.
/// The lender account needs its own Sepolia USDC and must not be the same address as the
/// borrower, or the "rate" produced is a self-trade and proves nothing.
contract Phase3RepoCycle is Script {
    uint256 constant NOTE_AMOUNT_FRACTION_BPS = 2000; // repo 20% of the borrower's L1 balance
    uint256 constant PREMIUM_BPS = 50; // 0.5% premium over the cycle -> annualizes via tenor

    function run() external {
        uint256 borrowerKey = vm.envUint("PRIVATE_KEY");
        uint256 lenderKey = vm.envUint("LENDER_PRIVATE_KEY");
        ReserveNote l1 = ReserveNote(vm.envAddress("L1"));
        RepoFacility repo = RepoFacility(vm.envAddress("REPO"));
        IERC20 usdc = IERC20(vm.envAddress("USDC"));

        address borrower = vm.addr(borrowerKey);

        vm.startBroadcast(borrowerKey);
        uint256 noteBalance = l1.balanceOf(borrower);
        uint256 noteAmount = (noteBalance * NOTE_AMOUNT_FRACTION_BPS) / 10_000;
        uint256 collateralValue = l1.convertToAssets(noteAmount);
        uint256 haircutBps = repo.haircutBps();
        uint256 cashAmount = (collateralValue * (10_000 - haircutBps)) / 10_000 - 1; // stay under the ceiling
        uint256 repurchasePrice = cashAmount + (cashAmount * PREMIUM_BPS) / 10_000 + 1;

        l1.approve(address(repo), noteAmount);
        usdc.approve(address(repo), repurchasePrice);
        uint256 repoId = repo.openRepo(noteAmount, cashAmount, repurchasePrice);
        vm.stopBroadcast();

        vm.startBroadcast(lenderKey);
        usdc.approve(address(repo), cashAmount);
        repo.fillRepo(repoId);
        vm.stopBroadcast();

        console2.log("Opened and filled repo #", repoId);
        console2.log("Reserve Rate (annualized, wad):", repo.reserveRate());
        console2.log("");
        console2.log("Call repo.repurchase(", repoId, ") from the borrower to close it normally,");
        console2.log("or wait past the tenor and run Phase4 to let it default instead.");
    }
}
