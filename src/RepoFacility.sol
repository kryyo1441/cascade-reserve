// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Cascade} from "./Cascade.sol";

/// @title RepoFacility
/// @notice The Reserve Repo Facility from source.md Text 2: L1 Reserve Notes only. A borrower
/// posts notes as collateral and names the cash they want now and the price they'll repurchase
/// at; any lender can fill that request. At expiry the borrower repurchases, or - no liquidation
/// auction, no bot dependency - the lender simply keeps the note (decisions.md #9).
///
/// The Reserve Rate is the volume-weighted average of the (annualized) rates implied by every
/// fill in the last `tenor`-length window: a real, transaction-based clearing price, not a
/// formula or a survey (source.md's whole point in building this at all).
///
/// The countercyclical floor extends here too (source.md's final risk section): the haircut can
/// never be *raised* while the Cascade is stressed - exactly the "released rather than
/// tightened under stress" discipline applied to this facility's own collateral requirement.
contract RepoFacility is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    IERC4626 public immutable l1Note;
    IERC20 public immutable asset;
    Cascade public immutable cascade;
    uint256 public immutable tenor;

    uint256 public haircutBps;
    uint256 private constant BPS_DENOM = 10_000;
    uint256 private constant SECONDS_PER_YEAR = 365 days;

    struct Repo {
        address borrower;
        address lender;
        uint256 noteAmount;
        uint256 cashAmount;
        uint256 repurchasePrice;
        uint64 openedAt;
        uint64 filledAt;
        bool filled;
        bool closed;
    }

    mapping(uint256 => Repo) public repos;
    uint256 public nextRepoId;

    struct Fill {
        uint64 timestamp;
        uint256 cashAmount;
        uint256 rateWad; // annualized, 1e18 = 100%
    }

    Fill[] public fills;

    event RepoOpened(uint256 indexed repoId, address indexed borrower, uint256 noteAmount, uint256 cashAmount, uint256 repurchasePrice);
    event RepoFilled(uint256 indexed repoId, address indexed lender, uint256 rateWad);
    event RepoRepurchased(uint256 indexed repoId);
    event RepoDefaulted(uint256 indexed repoId);
    event RepoRolled(uint256 indexed repoId, uint256 newCashAmount, uint256 newRepurchasePrice);
    event HaircutUpdated(uint256 newHaircutBps);

    error InvalidTerms();
    error HaircutExceeded();
    error NotFound();
    error AlreadyFilled();
    error NotFilled();
    error AlreadyClosed();
    error NotBorrower();
    error NotYetExpired();
    error HaircutCannotRiseDuringStress();

    constructor(
        IERC4626 _l1Note,
        IERC20 _asset,
        Cascade _cascade,
        uint256 _tenor,
        uint256 _haircutBps,
        address _owner
    ) Ownable(_owner) {
        l1Note = _l1Note;
        asset = _asset;
        cascade = _cascade;
        tenor = _tenor;
        haircutBps = _haircutBps;
    }

    /// @notice Post `noteAmount` of L1 notes as collateral and name this cycle's terms: cash
    /// wanted now, and the price to repurchase at expiry. The implied rate is unconstrained
    /// (any lender can simply decline to fill an unattractive request) - only the haircut is
    /// enforced on-chain.
    function openRepo(uint256 noteAmount, uint256 cashAmount, uint256 repurchasePrice)
        external
        nonReentrant
        returns (uint256 repoId)
    {
        if (noteAmount == 0 || cashAmount == 0 || repurchasePrice <= cashAmount) revert InvalidTerms();
        _checkHaircut(noteAmount, cashAmount);

        IERC20(address(l1Note)).safeTransferFrom(msg.sender, address(this), noteAmount);

        repoId = nextRepoId++;
        repos[repoId] = Repo({
            borrower: msg.sender,
            lender: address(0),
            noteAmount: noteAmount,
            cashAmount: cashAmount,
            repurchasePrice: repurchasePrice,
            openedAt: uint64(block.timestamp),
            filledAt: 0,
            filled: false,
            closed: false
        });

        emit RepoOpened(repoId, msg.sender, noteAmount, cashAmount, repurchasePrice);
    }

    /// @notice Any lender can fill an open repo request, supplying the named cash amount
    /// directly to the borrower. This is the moment the rate is discovered and recorded.
    function fillRepo(uint256 repoId) external nonReentrant {
        Repo storage r = repos[repoId];
        if (r.borrower == address(0)) revert NotFound();
        if (r.filled) revert AlreadyFilled();
        if (r.closed) revert AlreadyClosed();

        r.lender = msg.sender;
        r.filled = true;
        r.filledAt = uint64(block.timestamp);

        asset.safeTransferFrom(msg.sender, r.borrower, r.cashAmount);

        uint256 rateWad = _annualizedRateWad(r.cashAmount, r.repurchasePrice);
        fills.push(Fill({timestamp: uint64(block.timestamp), cashAmount: r.cashAmount, rateWad: rateWad}));

        emit RepoFilled(repoId, msg.sender, rateWad);
    }

    /// @notice Borrower repurchases: pays the lender, gets the note back, repo ends. Available
    /// any time before someone calls settleDefault - after expiry it's a race, exactly like a
    /// real repo desk racing a counterparty's close-out.
    function repurchase(uint256 repoId) external nonReentrant {
        Repo storage r = repos[repoId];
        if (!r.filled) revert NotFilled();
        if (r.closed) revert AlreadyClosed();
        if (msg.sender != r.borrower) revert NotBorrower();

        r.closed = true;
        asset.safeTransferFrom(r.borrower, r.lender, r.repurchasePrice);
        IERC20(address(l1Note)).safeTransfer(r.borrower, r.noteAmount);

        emit RepoRepurchased(repoId);
    }

    /// @notice Permissionless: once a filled repo is past its tenor and unrepurchased, anyone
    /// can finalize the default. The lender simply keeps the note - deterministic, no auction.
    function settleDefault(uint256 repoId) external nonReentrant {
        Repo storage r = repos[repoId];
        if (!r.filled) revert NotFilled();
        if (r.closed) revert AlreadyClosed();
        if (block.timestamp <= r.filledAt + tenor) revert NotYetExpired();

        r.closed = true;
        IERC20(address(l1Note)).safeTransfer(r.lender, r.noteAmount);

        emit RepoDefaulted(repoId);
    }

    /// @notice The borrower-callable stand-in for "auto-rolling" (decisions.md #9): pays off the
    /// current cycle and immediately reopens with new terms, without the collateral ever
    /// leaving the facility. The reopened cycle still needs a fresh fillRepo() - by the same
    /// lender or a different one.
    function roll(uint256 repoId, uint256 newCashAmount, uint256 newRepurchasePrice) external nonReentrant {
        Repo storage r = repos[repoId];
        if (!r.filled) revert NotFilled();
        if (r.closed) revert AlreadyClosed();
        if (msg.sender != r.borrower) revert NotBorrower();
        if (newCashAmount == 0 || newRepurchasePrice <= newCashAmount) revert InvalidTerms();
        _checkHaircut(r.noteAmount, newCashAmount);

        asset.safeTransferFrom(r.borrower, r.lender, r.repurchasePrice);

        r.lender = address(0);
        r.filled = false;
        r.filledAt = 0;
        r.cashAmount = newCashAmount;
        r.repurchasePrice = newRepurchasePrice;
        r.openedAt = uint64(block.timestamp);

        emit RepoRolled(repoId, newCashAmount, newRepurchasePrice);
    }

    /// @notice Owner-adjustable, but can never be *raised* while the Cascade is stressed - the
    /// countercyclical floor's discipline applied to this facility's own haircut.
    function setHaircutBps(uint256 newHaircutBps) external onlyOwner {
        if (newHaircutBps > haircutBps && cascade.isStressed()) revert HaircutCannotRiseDuringStress();
        haircutBps = newHaircutBps;
        emit HaircutUpdated(newHaircutBps);
    }

    /// @notice The Reserve Rate: volume-weighted average of annualized rates from every fill in
    /// the last `tenor`-length window. Zero if nothing has cleared yet in that window.
    /// @dev Iterates the fills array from the end; bounded in practice by fill frequency within
    /// one tenor window, which is fine at this scale. A production version serving high fill
    /// volume would want a ring buffer instead of scanning a growing array (documented
    /// simplification, same spirit as the registry's observation window).
    function reserveRate() external view returns (uint256) {
        if (fills.length == 0) return 0;
        uint256 cutoff = block.timestamp > tenor ? block.timestamp - tenor : 0;

        uint256 weightedSum = 0;
        uint256 totalCash = 0;
        for (uint256 i = fills.length; i > 0; i--) {
            Fill storage f = fills[i - 1];
            if (f.timestamp < cutoff) break;
            weightedSum += f.cashAmount * f.rateWad;
            totalCash += f.cashAmount;
        }

        return totalCash == 0 ? 0 : weightedSum / totalCash;
    }

    function fillsCount() external view returns (uint256) {
        return fills.length;
    }

    function _checkHaircut(uint256 noteAmount, uint256 cashAmount) internal view {
        uint256 collateralValue = l1Note.convertToAssets(noteAmount);
        uint256 maxCash = (collateralValue * (BPS_DENOM - haircutBps)) / BPS_DENOM;
        if (cashAmount > maxCash) revert HaircutExceeded();
    }

    function _annualizedRateWad(uint256 cashAmount, uint256 repurchasePrice) internal view returns (uint256) {
        uint256 premium = repurchasePrice - cashAmount;
        return (premium * 1e18 * SECONDS_PER_YEAR) / (cashAmount * tenor);
    }
}
