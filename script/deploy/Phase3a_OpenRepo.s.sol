// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ReserveNote} from "../../src/ReserveNote.sol";
import {RepoFacility} from "../../src/RepoFacility.sol";

/// @notice Phase 3a: borrower (deployer) posts L1 notes and opens a repo request.
///
/// Required env vars: DEPLOYER_ADDRESS, L1, REPO. Run with --account deployer.
/// Note the printed repoId - Phase3b needs it to fill the request.
contract Phase3aOpenRepo is Script {
    uint256 constant NOTE_AMOUNT_FRACTION_BPS = 2000; // repo 20% of the borrower's L1 balance
    uint256 constant PREMIUM_BPS = 50; // 0.5% premium over the cycle

    function run() external {
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        ReserveNote l1 = ReserveNote(vm.envAddress("L1"));
        RepoFacility repo = RepoFacility(vm.envAddress("REPO"));

        vm.startBroadcast(deployer);

        uint256 noteBalance = l1.balanceOf(deployer);
        uint256 noteAmount = (noteBalance * NOTE_AMOUNT_FRACTION_BPS) / 10_000;
        uint256 collateralValue = l1.convertToAssets(noteAmount);
        uint256 haircutBps = repo.haircutBps();
        uint256 cashAmount = (collateralValue * (10_000 - haircutBps)) / 10_000 - 1; // stay under the ceiling
        uint256 repurchasePrice = cashAmount + (cashAmount * PREMIUM_BPS) / 10_000 + 1;

        l1.approve(address(repo), noteAmount);
        uint256 repoId = repo.openRepo(noteAmount, cashAmount, repurchasePrice);

        vm.stopBroadcast();

        console2.log("Opened repo #", repoId);
        console2.log("cashAmount:      ", cashAmount);
        console2.log("repurchasePrice: ", repurchasePrice);
        console2.log("");
        console2.log("Run Phase3b with REPO_ID =", repoId, "and --account lender to fill it.");
    }
}
