// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VaultRegistry} from "../../src/VaultRegistry.sol";

/// @notice Phase 1 of the live Sepolia demo (run after Deploy.s.sol). Registers Aave V3's real
/// StaticATokenV3 USDC vault and our own DemoInsolventVault. Both start at zero weight; wait at
/// least OBSERVATION_WINDOW (see Deploy.s.sol) before running Phase 2, so the real elapsed time
/// genuinely earns them full trust - this is live exercise of the observation window, not a
/// skipped feature (source.md's own point about this).
///
/// Required env vars: PRIVATE_KEY, REGISTRY, AAVE_USDC_STATIC_ATOKEN, ATTACKER_VAULT, USDC.
/// The registry must already hold at least 2x PROBATION_AMOUNT of Sepolia USDC (send it there
/// manually via `cast send` before running this - see README).
contract Phase1RegisterVaults is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        VaultRegistry registry = VaultRegistry(vm.envAddress("REGISTRY"));
        address aaveVault = vm.envAddress("AAVE_USDC_STATIC_ATOKEN");
        address attackerVault = vm.envAddress("ATTACKER_VAULT");

        vm.startBroadcast(deployerKey);
        registry.register(aaveVault);
        registry.register(attackerVault);
        vm.stopBroadcast();

        console2.log("Registered Aave vault and attacker vault. Both at zero weight.");
        console2.log("Wait for the observation window to pass, then run Phase2.");
    }
}
