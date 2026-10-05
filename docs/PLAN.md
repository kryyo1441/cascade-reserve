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
   - [ ] **Current step:** fund deployer (and lender) with Sepolia EURS via
     Aave's faucet contract (same pattern as the USDC mint - see
     `handoff.md` for the exact faucet contract address and ABI), update
     `.env` with the EURS addresses and new deployment addresses, then
     re-run `forge script script/deploy/Deploy.s.sol:DeploySepolia
       --broadcast --verify` against the new constants. This abandons the
       USDC-wired deployment entirely (new addresses).
   - [ ] Fund the new registry with probation-amount EURS, run Phase 1
     (register Aave's real EURS vault + the attacker vault).
   - [ ] Wait out the observation window (10 min), run Phase 2 (deposit +
     allocate).
   - [ ] Run Phase 3a/3b (open + fill a real two-party repo).
   - [ ] Run Phase 4 (drain the attacker vault, checkpoint/slash it, settle
     the repo - either repurchased or defaulted, pick whichever produces
     the more interesting on-chain trail).
   - [ ] Double-check all 6 contracts verify cleanly on the new addresses.
8. **Dashboard** — not started. Next.js + shadcn/ui + lucide-react (user's
   explicit choice), using the `ui-ux-pro-max` skill for the design pass.
   Reads live testnet state: note supply per tier (the multiplier
   reading), registered vault weights, current Reserve Rate. Depends on
   phase 7 being complete (need final, stable contract addresses).
9. **README.md** — not started. Must state plainly: what's real vs
   simplified, the assumptions for undefined terms (discovery engine,
   floor, depth - already defined in `decisions.md`, just needs
   summarizing), known risks (Morpho Blue dependency risk - N/A here since
   we never integrated Morpho Blue, see decisions.md #7 - and repo haircut-
   spiral risk), and how to reproduce tests + deployment. Should also
   mention the `register()`-bundles-deposit limitation discovered during
   deployment (see `handoff.md` - "Minor design note for the README").
   Depends on phase 7's final addresses and phase 8's dashboard existing
   (or a note that it doesn't, if skipped).

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
