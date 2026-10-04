// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VaultRegistry} from "../../src/VaultRegistry.sol";
import {Cascade} from "../../src/Cascade.sol";
import {ReserveNote} from "../../src/ReserveNote.sol";

/// @notice Phase 2: deposits into both tiers, then allocates idle capital into both now-fully-
/// trusted vaults (Aave's real vault, and the attacker vault - the registry doesn't know yet
/// that one of them is about to be drained, exactly as source.md's "trust is earned, never
/// granted" design intends).
///
/// Required env vars: PRIVATE_KEY, USDC, CASCADE, L1, L2, AAVE_USDC_STATIC_ATOKEN, ATTACKER_VAULT.
/// The deployer must hold Sepolia USDC and have approved L1/L2 for the deposit amounts (the
/// script does the approvals itself).
contract Phase2DepositAndAllocate is Script {
    uint256 constant SENIOR_DEPOSIT = 10e6; // 10 USDC
    uint256 constant JUNIOR_DEPOSIT = 5e6; // 5 USDC
    uint256 constant ALLOCATE_TO_AAVE = 8e6;
    uint256 constant ALLOCATE_TO_ATTACKER = 4e6;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        IERC20 usdc = IERC20(vm.envAddress("USDC"));
        Cascade cascade = Cascade(vm.envAddress("CASCADE"));
        ReserveNote l1 = ReserveNote(vm.envAddress("L1"));
        ReserveNote l2 = ReserveNote(vm.envAddress("L2"));
        address aaveVault = vm.envAddress("AAVE_USDC_STATIC_ATOKEN");
        address attackerVault = vm.envAddress("ATTACKER_VAULT");

        vm.startBroadcast(deployerKey);

        usdc.approve(address(l1), SENIOR_DEPOSIT);
        l1.deposit(SENIOR_DEPOSIT, msg.sender);

        usdc.approve(address(l2), JUNIOR_DEPOSIT);
        l2.deposit(JUNIOR_DEPOSIT, msg.sender);

        cascade.allocate(aaveVault, ALLOCATE_TO_AAVE);
        cascade.allocate(attackerVault, ALLOCATE_TO_ATTACKER);

        vm.stopBroadcast();

        console2.log("Deposited into L1/L2 and allocated into both vaults.");
        console2.log("Senior claim: ", cascade.seniorClaim());
        console2.log("Junior claim: ", cascade.juniorClaim());
    }
}
