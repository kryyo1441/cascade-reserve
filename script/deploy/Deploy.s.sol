// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VaultRegistry} from "../../src/VaultRegistry.sol";
import {Cascade} from "../../src/Cascade.sol";
import {ReserveNote} from "../../src/ReserveNote.sol";
import {RepoFacility} from "../../src/RepoFacility.sol";
import {DemoInsolventVault} from "../../src/DemoInsolventVault.sol";

/// @notice Deploys the full Cascade Reserve protocol to Sepolia. Wired against Sepolia EURS and
/// Aave V3's real StaticATokenV3 vault (decisions.md #7, updated per #N - EURS swap after the
/// USDC/DAI/USDT supply-cap wall) as the system's first real external market, plus our own
/// DemoInsolventVault for the required loss scenario (decisions.md #6).
///
/// Usage (see README for the full walkthrough):
///   forge script script/deploy/Deploy.s.sol:DeploySepolia \
///     --rpc-url $SEPOLIA_RPC_URL --account deployer --broadcast --verify
contract DeploySepolia is Script {
    // Aave V3 Sepolia addresses, confirmed from BGD Labs' own aave-address-book repo
    // (decisions.md #7) - independent of this project, genuinely deployed, genuinely real.
    // EURS, not USDC/DAI/USDT: those three are supply-capped (maxDeposit() == 0) on Aave's
    // Sepolia testnet as of this session - EURS has open capacity. 2 decimals, not 6.
    address constant SEPOLIA_EURS = 0x6d906e526a4e2Ca02097BA9d0caA3c382F52278E;
    address constant AAVE_EURS_STATIC_ATOKEN = 0x72B49a461900e11632C95dfa563e7173438D4e3E;

    // Testnet-scale config: a live chain can't be vm.warp'd, so these windows are deliberately
    // short (minutes, not days/hours) to let the full lifecycle actually be exercised within a
    // demo session. This is a parameterization for live exercise, not a skipped feature -
    // source.md's own suggestion for the observation window, extended to the repo tenor too.
    uint256 constant OBSERVATION_WINDOW = 10 minutes;
    uint256 constant PROBATION_AMOUNT = 100; // 1 EURS (2 decimals)
    uint256 constant L1_COUPON_RATE_WAD = 0.02e18; // 2% APR
    uint256 constant RESERVE_CUT_BPS = 1000; // 10%
    uint256 constant REPO_TENOR = 10 minutes;
    uint256 constant HAIRCUT_BPS = 500; // 5%

    function run() external {
        // Deliberately no PRIVATE_KEY env var: the signer comes from --account <keystore>
        // passed on the CLI, which prompts for the keystore password interactively. The
        // deployer's address is public information, not a secret, so it's fine as an env var.
        address deployer = vm.envAddress("DEPLOYER_ADDRESS");

        vm.startBroadcast(deployer);

        VaultRegistry registry =
            new VaultRegistry(IERC20(SEPOLIA_EURS), OBSERVATION_WINDOW, PROBATION_AMOUNT, deployer);

        Cascade cascade = new Cascade(IERC20(SEPOLIA_EURS), registry, L1_COUPON_RATE_WAD, RESERVE_CUT_BPS, deployer);

        ReserveNote l1 = new ReserveNote(IERC20(SEPOLIA_EURS), "Cascade Reserve L1", "csL1", cascade, true);
        ReserveNote l2 = new ReserveNote(IERC20(SEPOLIA_EURS), "Cascade Reserve L2", "csL2", cascade, false);
        cascade.setTiers(address(l1), address(l2));

        RepoFacility repo = new RepoFacility(l1, IERC20(SEPOLIA_EURS), cascade, REPO_TENOR, HAIRCUT_BPS, deployer);

        DemoInsolventVault attackerVault = new DemoInsolventVault(IERC20(SEPOLIA_EURS), deployer);

        vm.stopBroadcast();

        console2.log("=== Cascade Reserve deployed to Sepolia ===");
        console2.log("VaultRegistry:      ", address(registry));
        console2.log("Cascade:            ", address(cascade));
        console2.log("ReserveNote L1:     ", address(l1));
        console2.log("ReserveNote L2:     ", address(l2));
        console2.log("RepoFacility:       ", address(repo));
        console2.log("DemoInsolventVault: ", address(attackerVault));
        console2.log("");
        console2.log("Real external vault to register (Aave V3 Sepolia EURS StaticAToken):");
        console2.log(AAVE_EURS_STATIC_ATOKEN);
        console2.log("");
        console2.log("Next: fund `registry` with >= PROBATION_AMOUNT * 2 of Sepolia EURS, then");
        console2.log("run RunDemo.s.sol to register both vaults and exercise the full lifecycle.");
    }
}
