// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Cascade} from "./Cascade.sol";

/// @title ReserveNote
/// @notice One instance of this contract is deployed per cascade depth. Non-rebasing: a
/// holder's share balance never changes, and its redeemable value moves with the tier's live
/// claim on the Cascade. This contract never holds real funds itself - every deposit is
/// forwarded to the Cascade immediately, and every withdrawal is funded by the Cascade pulling
/// liquidity (possibly from registered vaults, or from the countercyclical reserve under
/// stress) and handing it back here to forward to the actual receiver.
contract ReserveNote is ERC4626 {
    using SafeERC20 for IERC20;

    Cascade public immutable cascade;
    bool public immutable isSenior;

    constructor(IERC20 asset_, string memory name_, string memory symbol_, Cascade cascade_, bool isSenior_)
        ERC20(name_, symbol_)
        ERC4626(asset_)
    {
        cascade = cascade_;
        isSenior = isSenior_;
    }

    /// @dev Inflation/first-depositor attack mitigation via virtual shares, per OZ's own
    /// guidance that a nonzero offset matters more for low-decimal underlying assets (Sepolia
    /// USDC-like tokens use 6 decimals here).
    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }

    function totalAssets() public view override returns (uint256) {
        return isSenior ? cascade.seniorClaim() : cascade.juniorClaim();
    }

    function _transferIn(address from, uint256 assets) internal override {
        super._transferIn(from, assets); // pulls from depositor into this tier contract
        IERC20(asset()).safeTransfer(address(cascade), assets); // forward to where funds live
        if (isSenior) {
            cascade.onSeniorDeposit(assets);
        } else {
            cascade.onJuniorDeposit(assets);
        }
    }

    function _transferOut(address to, uint256 assets) internal override {
        if (isSenior) {
            cascade.onSeniorWithdraw(assets); // Cascade sends `assets` here, to this tier
        } else {
            cascade.onJuniorWithdraw(assets);
        }
        super._transferOut(to, assets); // then forward on to the actual receiver
    }
}
