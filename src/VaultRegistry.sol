// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title VaultRegistry
/// @notice Permissionless registry of ERC-4626 vaults, standing in for the "discovery engine"
/// referenced in source.md (an undefined term from prior discussion — see decisions.md #5).
///
/// Design, per decisions.md #5: a vault can self-register in one transaction and starts at
/// zero weight. Instead of scoring a number the vault reports about itself, this registry
/// deposits a small, hard-capped "probation" allocation of its own funds into the vault and
/// watches what actually happens on-chain: it tracks the vault's price-per-share over time via
/// permissionless checkpoints, and any observed drop (a real loss) permanently zeroes the
/// vault's weight. Absent a detected loss, weight rises linearly over a configurable
/// observation window. This is deliberately simple and documented as such — a production
/// version would also weigh correlation across vaults, which source.md's own glossary notes
/// can't be computed meaningfully from a handful of vaults (see README "Simplifications").
contract VaultRegistry is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;
    uint256 public immutable observationWindow;
    uint256 public immutable probationAmount;
    uint256 public constant MAX_WEIGHT = 1e18;

    struct VaultInfo {
        bool registered;
        bool slashed;
        uint64 registeredAt;
        uint256 shares;
        uint256 lastPricePerShare;
    }

    mapping(address => VaultInfo) public vaults;
    address[] public registeredVaults;

    event VaultRegistered(address indexed vault, uint256 probationShares);
    event VaultCheckpointed(address indexed vault, uint256 pricePerShare, bool lossDetected);
    event VaultSlashed(address indexed vault);

    error AlreadyRegistered();
    error NotRegistered();
    error AssetMismatch();

    constructor(IERC20 _asset, uint256 _observationWindow, uint256 _probationAmount, address _owner)
        Ownable(_owner)
    {
        asset = _asset;
        observationWindow = _observationWindow;
        probationAmount = _probationAmount;
    }

    /// @notice Register any ERC-4626 vault over this registry's asset. Permissionless: a bad
    /// actor can register freely, because starting at zero weight buys them nothing to exploit
    /// (source.md Text 1, point 3). Pulls `probationAmount` of this registry's own asset balance
    /// into the vault, so the registry must be pre-funded by its owner before vaults can
    /// register (documented in the deploy script, not enforced here — ponytail: no on-chain
    /// treasury contract for a value that's set once at setup).
    function register(address vaultAddr) external nonReentrant {
        if (vaults[vaultAddr].registered) revert AlreadyRegistered();
        IERC4626 vault = IERC4626(vaultAddr);
        if (vault.asset() != address(asset)) revert AssetMismatch();

        VaultInfo storage info = vaults[vaultAddr];
        info.registered = true;
        info.registeredAt = uint64(block.timestamp);
        registeredVaults.push(vaultAddr);

        asset.forceApprove(vaultAddr, probationAmount);
        uint256 shares = vault.deposit(probationAmount, address(this));
        info.shares = shares;
        info.lastPricePerShare = _pricePerShare(vault, shares);

        emit VaultRegistered(vaultAddr, shares);
    }

    /// @notice Permissionless: anyone can checkpoint a registered vault's current
    /// price-per-share. A drop since the last checkpoint is treated as an observed loss and
    /// permanently zeroes the vault's weight (it must register again from scratch to be
    /// reconsidered). This is the "real redemption history" check, computed from what the
    /// registry itself observed, not a number the vault reports.
    function checkpoint(address vaultAddr) external nonReentrant {
        VaultInfo storage info = vaults[vaultAddr];
        if (!info.registered) revert NotRegistered();
        if (info.shares == 0) return;

        IERC4626 vault = IERC4626(vaultAddr);
        uint256 currentPPS = _pricePerShare(vault, info.shares);
        bool lossDetected = currentPPS < info.lastPricePerShare;

        if (lossDetected) {
            info.slashed = true;
            emit VaultSlashed(vaultAddr);
        }
        info.lastPricePerShare = currentPPS;
        emit VaultCheckpointed(vaultAddr, currentPPS, lossDetected);
    }

    /// @notice Current allocation weight for a vault, scaled to 1e18 = 100%. Zero until
    /// registered, rises linearly over `observationWindow` since registration, zero forever
    /// once slashed.
    function weightOf(address vaultAddr) public view returns (uint256) {
        VaultInfo storage info = vaults[vaultAddr];
        if (!info.registered || info.slashed) return 0;
        uint256 elapsed = block.timestamp - info.registeredAt;
        if (elapsed >= observationWindow) return MAX_WEIGHT;
        return (MAX_WEIGHT * elapsed) / observationWindow;
    }

    function allVaults() external view returns (address[] memory) {
        return registeredVaults;
    }

    function _pricePerShare(IERC4626 vault, uint256 shares) internal view returns (uint256) {
        if (shares == 0) return 0;
        return vault.convertToAssets(shares) * 1e18 / shares;
    }
}
