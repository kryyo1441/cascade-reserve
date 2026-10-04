// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RepoFacility} from "../../src/RepoFacility.sol";

/// @notice Phase 3b: lender fills the repo opened in Phase3a, supplying the cash. This is the
/// moment the Reserve Rate actually gets a real, two-party, transaction-based data point
/// (source.md's whole argument for building the facility at all).
///
/// Required env vars: LENDER_ADDRESS, USDC, REPO, REPO_ID. Run with --account lender.
contract Phase3bFillRepo is Script {
    function run() external {
        address lender = vm.envAddress("LENDER_ADDRESS");
        IERC20 usdc = IERC20(vm.envAddress("USDC"));
        RepoFacility repo = RepoFacility(vm.envAddress("REPO"));
        uint256 repoId = vm.envUint("REPO_ID");

        (,, , uint256 cashAmount,,,,,) = repo.repos(repoId);

        vm.startBroadcast(lender);
        usdc.approve(address(repo), cashAmount);
        repo.fillRepo(repoId);
        vm.stopBroadcast();

        console2.log("Filled repo #", repoId);
        console2.log("Reserve Rate (annualized, wad):", repo.reserveRate());
        console2.log("");
        console2.log("Call repo.repurchase(repoId) from deployer to close it normally,");
        console2.log("or wait past the tenor and run Phase4 to let it default instead.");
    }
}
