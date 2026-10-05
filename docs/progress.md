# Progress snapshot

Last updated: end of the session where we hit the Sepolia deployment blocker
(see `handoff.md` for the full story). This file is a factual inventory of
what exists; `PLAN.md` is the forward-looking plan; `handoff.md` is the
narrative for picking the work back up.

## Done

### Contracts (`src/`)
- **`VaultRegistry.sol`** — permissionless vault registration, zero-weight
  start, capped probation deposit into the candidate vault, permissionless
  `checkpoint()` that slashes weight to zero on any detected loss, linear
  weight growth over a configurable observation window.
- **`Cascade.sol`** — the pool. Lazy-valuation waterfall (senior claim =
  `min(pool, floor)`, junior = residual), permissionless rule-based
  allocation into fully-trusted vaults only, countercyclical reserve
  (withheld during calm, released under stress).
- **`ReserveNote.sol`** — non-rebasing ERC-4626 tier token (one deployed per
  tier: L1 senior, L2 junior), reads its live claim from the Cascade, never
  holds funds itself.
- **`RepoFacility.sol`** — bilateral repo market (open/fill/repurchase/
  settleDefault/roll), VWAP Reserve Rate from real fills, haircut that can't
  be raised while the Cascade is stressed.
- **`DemoInsolventVault.sol`** — small real ERC-4626 vault for the live
  "insolvent underlying vault" scenario the brief requires; owner-only
  `simulateLoss()`.

### Tests (`test/`)
All passing as of last run. `forge test` (default profile): 36 tests in a
few seconds. `forge test --profile deep` reruns the invariant suites at
256 runs / deeper call depth (slow, ~4-5 minutes total) for a thorough pass.
- `test/unit/VaultRegistry.t.sol` — 11 tests
- `test/fuzz/VaultRegistry.fuzz.t.sol` — 2 fuzz tests (weight monotonicity,
  permanent slashing)
- `test/unit/Cascade.t.sol` — 10 tests (waterfall, allocation, reserve)
- `test/invariant/CascadeWaterfall.t.sol` — 3 invariants (claims never
  exceed pool, claims exactly partition pool, junior never underflows).
  This suite caught and led to fixing a real 1-wei ERC-4626 rounding bug in
  `Cascade._ensureLiquidity` (switched `redeem()`-by-shares to
  `withdraw()`-by-assets).
- `test/unit/RepoFacility.t.sol` — 11 tests (full lifecycle + stress-gated
  haircut discipline)
- `test/invariant/RepoFacility.t.sol` — 2 invariants (collateral solvency,
  lifecycle-flag consistency)

### Deploy infrastructure (`script/deploy/`)
- `Deploy.s.sol` — deploys all 6 contracts, wired to Sepolia EURS (switched
  from USDC mid-session — see decisions.md #10).
- `Phase1_RegisterVaults.s.sol` — registers the real external vault + the
  attacker vault.
- `Phase2_DepositAndAllocate.s.sol` — deposits into L1/L2, allocates into
  both vaults.
- `Phase3a_OpenRepo.s.sol` / `Phase3b_FillRepo.s.sol` — split because
  opening (borrower) and filling (lender) need different signers in one
  `forge script` run.
- `Phase4_LossAndDefault.s.sol` — drains the attacker vault, checkpoints it
  into a slash, settles a defaulted repo.
- All scripts use `vm.startBroadcast(address)` + CLI `--account <keystore>`
  signing. No script reads a raw private key from an env var — that was a
  bug I introduced and fixed before any money moved (see `handoff.md`).

### Local environment
- Foundry installed (`forge`/`cast`/`anvil` v1.8.4), added to `~/.bashrc`.
- Git initialized, `master` branch, feature branches merged with `--no-ff`
  per-component (`feature/vault-registry`, `feature/cascade-notes`,
  `feature/repo-facility` — all merged and deleted).
- Three local encrypted keystores exist at `~/.foundry/keystores/`:
  `deployer`, `lender`, `depositor` (addresses only recorded anywhere;
  private keys were only ever shown in the user's own terminal and are not
  stored in this repo or in `.env`).
- `.env` (gitignored) holds: `SEPOLIA_RPC_URL`, `ETHERSCAN_API_KEY`, and the
  public addresses for deployer/lender/depositor and (as of the last
  deploy) the USDC-wired contract addresses.
- Deployer wallet: funded with Sepolia ETH (via Google's faucet + an
  internal transfer) and with 1000 Sepolia USDC (via Aave's testnet faucet
  contract, called directly - see `handoff.md`). Lender wallet: funded with
  0.02 Sepolia ETH and 100 Sepolia USDC (both sent from deployer).

### Sepolia deployment — superseded, redeploy scripts ready
All 6 contracts were deployed to Sepolia and verified on Etherscan, wired
to Aave's Sepolia USDC (`0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8`). That
deployment is **abandoned**: Aave's Sepolia USDC market has hit its supply
cap (`maxDeposit() == 0`), which blocks even registering the real external
vault, because `VaultRegistry.register()` bundles a probation deposit into
the registration call itself. Full story and evidence are in `handoff.md`.

The fix — switching the protocol's asset to Aave Sepolia's EURS market —
is implemented in `script/deploy/*.sol` (constants + decimals-correct
amounts, `forge build` clean, no contract code changes needed since
`VaultRegistry`/`Cascade`/`ReserveNote`/`RepoFacility` are decimals-
agnostic). See decisions.md #10. Not yet redeployed on-chain.

## Not done yet
- Fund deployer/lender with Sepolia EURS and re-run `Deploy.s.sol` against
  the new constants (new addresses - old USDC-wired ones are abandoned).
- Re-run Phase 1-4 against the new deployment.
- Dashboard (Next.js + shadcn/ui + lucide-react, per earlier user request).
- `README.md` (still the default `forge init` placeholder).
