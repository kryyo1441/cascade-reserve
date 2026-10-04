// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Test-only ERC-4626 vault. Stands in for a real third-party vault in unit tests
/// (the real deploy against Aave V3 Sepolia's StaticATokenV3 is covered separately, per
/// decisions.md #7). Exposes `simulateLoss` to play the role of the "attacker vault" from
/// decisions.md #6: it drains underlying assets without burning shares, which drops
/// price-per-share exactly the way a real insolvent vault would.
contract MockERC4626Vault is ERC4626 {
    using SafeERC20 for IERC20;

    constructor(IERC20 asset_, string memory name_, string memory symbol_) ERC20(name_, symbol_) ERC4626(asset_) {}

    function simulateLoss(uint256 amount) external {
        IERC20(asset()).safeTransfer(address(0xdead), amount);
    }
}
