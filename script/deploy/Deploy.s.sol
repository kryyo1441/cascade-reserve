// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VaultRegistry} from "../../src/VaultRegistry.sol";
import {Cascade} from "../../src/Cascade.sol";
import {ReserveNote} from "../../src/ReserveNote.sol";
import {RepoFacility} from "../../src/RepoFacility.sol";
import {DemoInsolventVault} from "../../src/DemoInsolventVault.sol";

/// @notice Deploys the full Cascade Reserve protocol to Sepolia. Wired against Sepolia USDC and
/// Aave V3's real StaticATokenV3 vault (decisions.md #7) as the system's first real external
/// market, plus our own DemoInsolventVault for the required loss scenario (decisions.md #6).
///
/// Usage (see README for the full walkthrough):
///   forge script script/deploy/Deploy.s.sol:DeploySepolia \
///     --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
contract DeploySepolia is Script {
    // Aave V3 Sepolia addresses, confirmed from BGD Labs' own aave-address-book repo
    // (decisions.md #7) - independent of this project, genuinely deployed, genuinely real.
    address constant SEPOLIA_USDC = 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8;
    address constant AAVE_USDC_STATIC_ATOKEN = 0x8A88124522dbBF1E56352ba3DE1d9F78C143751e;

    // Testnet-scale config: a live chain can't be vm.warp'd, so these windows are deliberately
    // short (minutes, not days/hours) to let the full lifecycle actually be exercised within a
    // demo session. This is a parameterization for live exercise, not a skipped feature -
    // source.md's own suggestion for the observation window, extended to the repo tenor too.
    uint256 constant OBSERVATION_WINDOW = 10 minutes;
    uint256 constant PROBATION_AMOUNT = 1e6; // 1 USDC
    uint256 constant L1_COUPON_RATE_WAD = 0.02e18; // 2% APR
    uint256 constant RESERVE_CUT_BPS = 1000; // 10%
    uint256 constant REPO_TENOR = 10 minutes;
    uint256 constant HAIRCUT_BPS = 500; // 5%

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        VaultRegistry registry =
            new VaultRegistry(IERC20(SEPOLIA_USDC), OBSERVATION_WINDOW, PROBATION_AMOUNT, deployer);

        Cascade cascade = new Cascade(IERC20(SEPOLIA_USDC), registry, L1_COUPON_RATE_WAD, RESERVE_CUT_BPS, deployer);

        ReserveNote l1 = new ReserveNote(IERC20(SEPOLIA_USDC), "Cascade Reserve L1", "csL1", cascade, true);
        ReserveNote l2 = new ReserveNote(IERC20(SEPOLIA_USDC), "Cascade Reserve L2", "csL2", cascade, false);
        cascade.setTiers(address(l1), address(l2));

        RepoFacility repo = new RepoFacility(l1, IERC20(SEPOLIA_USDC), cascade, REPO_TENOR, HAIRCUT_BPS, deployer);

        DemoInsolventVault attackerVault = new DemoInsolventVault(IERC20(SEPOLIA_USDC), deployer);

        vm.stopBroadcast();

        console2.log("=== Cascade Reserve deployed to Sepolia ===");
        console2.log("VaultRegistry:      ", address(registry));
        console2.log("Cascade:            ", address(cascade));
        console2.log("ReserveNote L1:     ", address(l1));
        console2.log("ReserveNote L2:     ", address(l2));
        console2.log("RepoFacility:       ", address(repo));
        console2.log("DemoInsolventVault: ", address(attackerVault));
        console2.log("");
        console2.log("Real external vault to register (Aave V3 Sepolia USDC StaticAToken):");
        console2.log(AAVE_USDC_STATIC_ATOKEN);
        console2.log("");
        console2.log("Next: fund `registry` with >= PROBATION_AMOUNT * 2 of Sepolia USDC, then");
        console2.log("run RunDemo.s.sol to register both vaults and exercise the full lifecycle.");
    }
}
