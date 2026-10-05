# Plan

This is the forward-looking plan, derived from `source.md` section 6
("Suggested scope") and the decisions already logged in `decisions.md`.
**This file is expected to change** if we hit another real-world wall like
the one described in `handoff.md` — update it in place rather than treating
it as fixed, and note *why* a step changed when it does.

## Phases

1. ~~Tooling~~ — done (Foundry, OpenZeppelin v5.7).
2. ~~Vault registry~~ — done (`VaultRegistry.sol`, tested).
3. ~~Reserve Notes + loss waterfall~~ — done (`Cascade.sol` +
   `ReserveNote.sol`, L1/L2, tested).
4. ~~Reserve Repo Facility~~ — done (`RepoFacility.sol`, tested).
5. ~~Countercyclical floor~~ — done, split across Cascade (reserve
   build/release) and RepoFacility (haircut can't rise under stress).
6. ~~Unit/fuzz/invariant tests~~ — done for all four contracts, including
   the required insolvent-vault failure scenario (via
   `DemoInsolventVault`).
7. **Deployment — in progress, currently blocked and pivoting.**
   - [x] Local tooling: RPC URL, Etherscan key, 3 keystores, funded wallets.
   - [x] First deploy attempt (wired to Sepolia USDC) — succeeded, verified
     on Etherscan, but turned out to be a dead end (see `handoff.md`).
   - [x] Redeploy scripts switched to Aave Sepolia's EURS market instead
     of USDC (chosen fix — confirmed via `cast call` that EURS still has
     open deposit capacity, unlike USDC/DAI/USDT which are all capped at
     `maxDeposit() == 0`). `Deploy.s.sol` constants renamed
     `SEPOLIA_USDC`/`AAVE_USDC_STATIC_ATOKEN` → `SEPOLIA_EURS`/
     `AAVE_EURS_STATIC_ATOKEN` with EURS's addresses; `Phase1-3b` env var
     names and hardcoded amounts (`PROBATION_AMOUNT`, `SENIOR_DEPOSIT`,
     `JUNIOR_DEPOSIT`, `ALLOCATE_TO_*`) rescaled from 6 decimals to EURS's
     2 (e.g. "1 unit" is now `100`, not `1e6`). No contract code changes —
     `VaultRegistry`/`Cascade`/`ReserveNote`/`RepoFacility` were already
     decimals-agnostic. `forge build` confirmed clean (decisions.md #10).
   - [x] Funded deployer/lender with Sepolia EURS via Aave's faucet
     contract, redeployed all 6 contracts to Sepolia wired to EURS,
     verified cleanly on Etherscan (new addresses in `.env`; old
     USDC-wired deployment abandoned - see `handoff.md`).
   - [x] Funded the new registry, ran Phase 1 (registered Aave's real
     EURS vault + the attacker vault, both at zero weight).
   - [x] Waited out the observation window (10 min), ran Phase 2
     (deposited 10 EURS into L1 / 5 EURS into L2, allocated 8 EURS to the
     Aave vault and 4 EURS to the attacker vault).
   - [x] Ran Phase 3a/3b: opened repo #0 (1.89 EURS cash, 1.90 EURS
     repurchase), lender filled it. Reserve Rate recorded (annualized wad
     ~278 - expected to look huge given the 10-minute tenor annualizing a
     0.5% premium, not a bug).
   - [x] Ran Phase 4 (waited past the repo tenor): drained the attacker
     vault, checkpointed it (permissionless loss detection - permanently
     slashed its weight to 0), settled repo #0 as **defaulted** (lender
     keeps the L1 note, no auction). The waterfall worked exactly as
     designed: senior claim held at 1000 through the loss, junior claim
     absorbed it (379 → 19).
   - [x] Double-checked all 6 contracts on Etherscan directly (API v2,
     `getsourcecode`): all verified with matching source
     (`VaultRegistry`, `Cascade`, `ReserveNote` ×2, `RepoFacility`,
     `DemoInsolventVault`).
8. ~~Dashboard~~ — done (`dashboard/`, see its own README). Next.js +
   shadcn/ui, read-only. All chain reads happen server-side in one `viem`
   multicall (`app/api/state/route.ts`) so the RPC URL never reaches the
   client; the page polls it every 15s. Shows note supply and value per
   note for each tier (the multiplier reading), registered vault weights
   and trust status, the current Reserve Rate, and the latest repo.
   Verified against the live post-Phase-4 deployment: correctly showed
   the slashed attacker vault, the junior tranche's loss, and the closed
   repo. Didn't end up invoking the `ui-ux-pro-max` skill - shadcn's
   defaults were clean enough for a read-only internal viewer; revisit if
   the dashboard becomes user-facing.
9. ~~README.md~~ — done. States what's real vs. simplified vs. not
   built, the assumptions for undefined terms (discovery engine, floor,
   depth), known risks (Reserve Rate manipulation, haircut-spiral,
   registration-blocks-on-deposit, Morpho Blue N/A), and how to reproduce
   tests, deployment, and the dashboard. Points to `decisions.md` for the
   full reasoning behind each choice rather than duplicating it.

## Out of scope (per source.md, revisit only if everything above is solid)
- Full Morpho Blue integration (impossible on any public testnet anyway -
  confirmed, not just unscoped).
- Full ERC-7540 async flows - only if core is complete and time remains.
- Manipulation-resistant production-grade benchmark rate - explicitly
  flagged as research-grade, not attempting.
- Audits and mainnet deployment - explicitly rejected, not just deferred.

## When to update this file
- Any time a planned step turns out to be blocked by something outside our
  control (like the Aave supply-cap wall) - document the wall, the
  investigation, and the chosen fix in `handoff.md`, then update *this*
  file's step list to reflect the new path forward.
- Any time a phase's scope changes (e.g., dropping L3/L4, skipping the
  dashboard) - note it here and in `decisions.md` with the reasoning.
