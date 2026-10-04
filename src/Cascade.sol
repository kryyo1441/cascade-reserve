// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {VaultRegistry} from "./VaultRegistry.sol";

/// @title Cascade
/// @notice The pool at the center of the protocol. Holds all real funds (decisions.md #8: lazy
/// valuation - the two ReserveNote tiers never hold assets themselves, they just read their live
/// claim from here). Deploys idle capital into fully-trusted registered vaults, and implements
/// the countercyclical floor (decisions.md and source.md point 5 / Text 2's repo risk section):
/// a reserve built from a cut of each allocation during calm, excluded from tier claims under
/// normal conditions, and released into the senior claim and into withdrawal liquidity the
/// moment the system is stressed.
///
/// Waterfall (decisions.md #8): senior (L1) claim = min(pool, seniorFloor); junior (L2) claim =
/// pool - seniorClaim. seniorFloor is net L1 principal plus a modest accruing coupon ("L1 ...
/// yields least" per source.md), so under normal conditions L1 only ever gets its floor back and
/// L2 absorbs 100% of any upside; under loss, L2's claim hits zero first and L1 only then starts
/// absorbing the remainder - a real waterfall with no separate loss-event bookkeeping to drift
/// out of sync with reality.
contract Cascade is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable asset;
    VaultRegistry public immutable registry;

    address public l1Tier;
    address public l2Tier;

    uint256 public l1Floor;
    uint64 public lastL1AccrualTime;
    uint256 public immutable l1CouponRateAnnualWad;

    uint256 public reserveBuffer;
    uint256 public immutable reserveCutBps;
    uint256 private constant BPS_DENOM = 10_000;
    uint256 private constant SECONDS_PER_YEAR = 365 days;

    event TiersSet(address l1Tier, address l2Tier);
    event SeniorDeposited(uint256 assets);
    event SeniorWithdrawn(uint256 assets);
    event JuniorDeposited(uint256 assets);
    event JuniorWithdrawn(uint256 assets);
    event Allocated(address indexed vault, uint256 invested, uint256 reserveCut);
    event ReserveReleased(uint256 amount);

    error TiersAlreadySet();
    error NotTier();
    error VaultNotFullyTrusted();
    error InsufficientIdle();

    constructor(
        IERC20 _asset,
        VaultRegistry _registry,
        uint256 _l1CouponRateAnnualWad,
        uint256 _reserveCutBps,
        address _owner
    ) Ownable(_owner) {
        asset = _asset;
        registry = _registry;
        l1CouponRateAnnualWad = _l1CouponRateAnnualWad;
        reserveCutBps = _reserveCutBps;
        lastL1AccrualTime = uint64(block.timestamp);
    }

    modifier onlyL1Tier() {
        if (msg.sender != l1Tier) revert NotTier();
        _;
    }

    modifier onlyL2Tier() {
        if (msg.sender != l2Tier) revert NotTier();
        _;
    }

    /// @notice Wires up the two ReserveNote tiers. One-time, owner-only: tiers must be deployed
    /// with this Cascade's address already in their constructor, so this closes the circular
    /// dependency exactly once at setup.
    function setTiers(address _l1Tier, address _l2Tier) external onlyOwner {
        if (l1Tier != address(0)) revert TiersAlreadySet();
        l1Tier = _l1Tier;
        l2Tier = _l2Tier;
        emit TiersSet(_l1Tier, _l2Tier);
    }

    // ---------------------------------------------------------------------
    // Tier entry points. Assets have already been moved into this contract
    // (deposit) or must be sent out to the calling tier (withdraw) by the
    // time these return - see ReserveNote's _transferIn/_transferOut.
    // ---------------------------------------------------------------------

    function onSeniorDeposit(uint256 assets) external nonReentrant onlyL1Tier {
        _accrueL1();
        l1Floor += assets;
        emit SeniorDeposited(assets);
    }

    function onSeniorWithdraw(uint256 assets) external nonReentrant onlyL1Tier {
        _accrueL1();
        _ensureLiquidity(assets);
        l1Floor -= assets;
        asset.safeTransfer(msg.sender, assets);
        emit SeniorWithdrawn(assets);
    }

    function onJuniorDeposit(uint256 assets) external nonReentrant onlyL2Tier {
        emit JuniorDeposited(assets);
    }

    function onJuniorWithdraw(uint256 assets) external nonReentrant onlyL2Tier {
        _ensureLiquidity(assets);
        asset.safeTransfer(msg.sender, assets);
        emit JuniorWithdrawn(assets);
    }

    // ---------------------------------------------------------------------
    // Allocation: the "discovery engine" handoff from VaultRegistry.sol.
    // Permissionless and purely rule-based (zero human discretion, per
    // source.md point 2): idle capital may only be deployed into a vault
    // that has reached full registry weight, i.e. survived its entire
    // observation window with no detected loss.
    // ---------------------------------------------------------------------

    /// @notice Deploy `amount` of idle (non-reserve) capital into a fully-trusted registered
    /// vault. During calm (not stressed), a `reserveCutBps` slice of the amount is withheld as
    /// countercyclical reserve instead of being invested - "built up in calm" (source.md point
    /// 5 / Text 2's final risk section). During stress, the cut is skipped entirely so no more
    /// is withheld from capital that may be needed for liquidity.
    function allocate(address vaultAddr, uint256 amount) external nonReentrant {
        if (registry.weightOf(vaultAddr) != registry.MAX_WEIGHT()) revert VaultNotFullyTrusted();
        if (amount > _idleNonReserve()) revert InsufficientIdle();

        uint256 reserveCut = isStressed() ? 0 : (amount * reserveCutBps) / BPS_DENOM;
        reserveBuffer += reserveCut;
        uint256 toInvest = amount - reserveCut;

        asset.forceApprove(vaultAddr, toInvest);
        IERC4626(vaultAddr).deposit(toInvest, address(this));
        emit Allocated(vaultAddr, toInvest, reserveCut);
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    /// @notice Senior (L1) claim: capped at its floor, never more than the pool actually holds.
    function seniorClaim() public view returns (uint256) {
        uint256 floor = l1Floor + _pendingL1Coupon();
        uint256 pv = poolValue();
        return floor < pv ? floor : pv;
    }

    /// @notice Junior (L2) claim: everything left over after the senior claim. Absorbs all
    /// upside above the senior floor, and absorbs losses down to zero before senior claim ever
    /// drops below its own floor.
    function juniorClaim() public view returns (uint256) {
        return poolValue() - seniorClaim();
    }

    /// @notice Total value the two tiers can lay claim to. Excludes the countercyclical reserve
    /// unless the system is currently stressed, in which case the reserve is released into the
    /// pool backing the senior claim (source.md's "released rather than tightened under stress").
    function poolValue() public view returns (uint256) {
        uint256 baseline = _baselinePool();
        return isStressed() ? baseline + reserveBuffer : baseline;
    }

    /// @notice Stress signal, deliberately simple and singular (per README's documented
    /// simplification): the system is stressed exactly when the senior floor exceeds what the
    /// pool holds *before* counting the reserve, i.e. senior would already be impaired without
    /// the reserve's help. Intentionally computed from the baseline (reserve-excluded) pool so
    /// this can never be circular with poolValue().
    function isStressed() public view returns (bool) {
        return _baselinePool() < (l1Floor + _pendingL1Coupon());
    }

    function allVaultsValue() public view returns (uint256) {
        return _vaultsValue();
    }

    function _baselinePool() internal view returns (uint256) {
        return _idleNonReserve() + _vaultsValue();
    }

    function _idleNonReserve() internal view returns (uint256) {
        return asset.balanceOf(address(this)) - reserveBuffer;
    }

    function _vaultsValue() internal view returns (uint256) {
        address[] memory vs = registry.allVaults();
        uint256 total = 0;
        for (uint256 i = 0; i < vs.length; i++) {
            IERC4626 v = IERC4626(vs[i]);
            uint256 shares = v.balanceOf(address(this));
            if (shares > 0) total += v.convertToAssets(shares);
        }
        return total;
    }

    function _pendingL1Coupon() internal view returns (uint256) {
        uint256 elapsed = block.timestamp - lastL1AccrualTime;
        if (elapsed == 0 || l1Floor == 0) return 0;
        return (l1Floor * l1CouponRateAnnualWad * elapsed) / SECONDS_PER_YEAR / 1e18;
    }

    function _accrueL1() internal {
        uint256 pending = _pendingL1Coupon();
        if (pending > 0) l1Floor += pending;
        lastL1AccrualTime = uint64(block.timestamp);
    }

    /// @notice Pulls in liquidity for a withdrawal of `need`: first from vault redemptions
    /// (available regardless of stress), then, only while stressed, from the countercyclical
    /// reserve itself - the actual "release" of the floor. If even that isn't enough the
    /// underlying transfer simply reverts: a genuine insolvency, which this function does not
    /// paper over.
    ///
    /// @dev Uses ERC-4626's asset-denominated `withdraw()`, not share-denominated `redeem()`:
    /// `redeem()` rounds the returned assets down from a share amount, which can come back 1
    /// wei short of what was asked for and silently drift the reserve accounting out of sync
    /// with the real balance (caught by the invariant suite - see test/invariant). `withdraw()`
    /// is defined to deliver exactly the requested asset amount or revert, so no such drift.
    function _ensureLiquidity(uint256 need) internal {
        if (_idleNonReserve() >= need) return;

        address[] memory vs = registry.allVaults();
        for (uint256 i = 0; i < vs.length && _idleNonReserve() < need; i++) {
            IERC4626 v = IERC4626(vs[i]);
            uint256 maxW = v.maxWithdraw(address(this));
            if (maxW == 0) continue;

            uint256 shortfall = need - _idleNonReserve();
            uint256 toPull = shortfall < maxW ? shortfall : maxW;
            if (toPull == 0) continue;
            v.withdraw(toPull, address(this), address(this));
        }

        if (_idleNonReserve() < need && isStressed()) {
            uint256 shortfall = need - _idleNonReserve();
            uint256 release = shortfall < reserveBuffer ? shortfall : reserveBuffer;
            reserveBuffer -= release;
            emit ReserveReleased(release);
        }
    }
}
