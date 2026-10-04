// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title DemoInsolventVault
/// @notice Deployed on Sepolia deliberately, as the honestly-labeled "malicious registrant" from
/// decisions.md #6: a real, independent ERC-4626 vault that self-registers with VaultRegistry
/// like any other, then has its owner intentionally drain it to exercise the loss-waterfall and
/// slashing paths with a genuine on-chain transaction trail. Not a stand-in for production code -
/// this contract exists only to produce the required "insolvent underlying vault" test scenario
/// (source.md point 6) against the real deployed protocol, not a local fork.
contract DemoInsolventVault is ERC4626, Ownable {
    using SafeERC20 for IERC20;

    constructor(IERC20 asset_, address owner_) ERC20("Demo Insolvent Vault", "DIV") ERC4626(asset_) Ownable(owner_) {}

    /// @notice Owner-only: drains `amount` of the vault's assets to simulate an on-chain loss
    /// (a bug, a hack, or negligence - mechanically identical to all three from the outside).
    function simulateLoss(uint256 amount) external onlyOwner {
        IERC20(asset()).safeTransfer(owner(), amount);
    }
}
