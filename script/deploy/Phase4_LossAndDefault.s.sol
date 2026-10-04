// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {VaultRegistry} from "../../src/VaultRegistry.sol";
import {Cascade} from "../../src/Cascade.sol";
import {DemoInsolventVault} from "../../src/DemoInsolventVault.sol";
import {RepoFacility} from "../../src/RepoFacility.sol";

/// @notice Phase 4: the required failure scenario (source.md point 6) and the repo default
/// path, both exercised for real. Drains the attacker vault, permissionlessly checkpoints it
/// into a permanent slash, and - if the repo from Phase3 was left unrepurchased past its tenor -
/// settles it into a default: the lender keeps the note, no auction, no bot.
///
/// Required env vars: PRIVATE_KEY, REGISTRY, CASCADE, ATTACKER_VAULT, REPO, REPO_ID.
/// Run this only after the repo's tenor has actually elapsed if you want to exercise the
/// default path; otherwise settleDefault reverts (by design - see RepoFacility.NotYetExpired).
contract Phase4LossAndDefault is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        VaultRegistry registry = VaultRegistry(vm.envAddress("REGISTRY"));
        Cascade cascade = Cascade(vm.envAddress("CASCADE"));
        DemoInsolventVault attackerVault = DemoInsolventVault(vm.envAddress("ATTACKER_VAULT"));
        RepoFacility repo = RepoFacility(vm.envAddress("REPO"));
        uint256 repoId = vm.envUint("REPO_ID");

        vm.startBroadcast(deployerKey);

        uint256 vaultBalance = attackerVault.totalAssets();
        attackerVault.simulateLoss(vaultBalance); // the deliberate, labeled failure scenario
        registry.checkpoint(address(attackerVault)); // permissionless: anyone observes the loss

        console2.log("Attacker vault weight after slash:", registry.weightOf(address(attackerVault)));
        console2.log("Junior claim after loss:", cascade.juniorClaim());
        console2.log("Senior claim after loss:", cascade.seniorClaim());

        try repo.settleDefault(repoId) {
            console2.log("Repo", repoId, "defaulted - lender now holds the note.");
        } catch {
            console2.log("Repo", repoId, "not yet expired or already closed - nothing to settle.");
        }

        vm.stopBroadcast();
    }
}
