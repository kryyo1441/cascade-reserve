# Handoff

Read this first if you're a fresh Claude Code session picking this project
up. It has zero memory of the conversation that produced this repo - this
file is written to stand in for that memory. Read `source.md` (the brief),
`decisions.md` (every design decision and why), `docs/progress.md` (what
exists), and `docs/PLAN.md` (what's next) alongside this file.

## What this project is

**Cascade Reserve**: a DeFi hiring-task build for a web3/cybersecurity
internship. Full brief in `source.md`. Short version: a tiered credit
protocol (L1/L2 Reserve Notes, ERC-4626, real loss waterfall) with a repo
market on top (L1 notes repoable for cash, a real transaction-based
"Reserve Rate" benchmark). Built with Foundry + OpenZeppelin v5.7, deployed
to Sepolia with verified contracts, real transactions, no mainnet, no
simulation.

## Who's doing this and how they want to work

- The user (Aayush Nair) has **zero Solidity background** — full-stack
  (Next.js/TS/Prisma/FastAPI) with ZK/blockchain-tracing experience, but
  this is their first smart-contract project. Explain non-obvious design
  decisions, don't assume Solidity fluency.
- **`decisions.md` is a running log the user explicitly asked for**: every
  design/tooling choice gets an entry with the situation, the choices
  considered, what was picked, and why — written for them to learn from.
  Keep adding to it. **Do not mention `decisions.md` in git commit
  messages** (explicit instruction - log the decision in the file, commit
  it as part of a `docs:` commit, just don't reference the filename in the
  commit message text).
- **User wants to be told before mid-size/big decisions**, not just handed
  a finished result. Several questions were asked via the question tool
  mid-build (rebasing vs non-rebasing notes, repo bootstrap mechanism,
  real-vs-mock vaults, matching mechanism) - keep doing that for anything
  of similar weight.
- **Git workflow**: commit granularly (one logical unit per commit - one
  contract, one test file, one doc, etc.), use `feature/*` branches merged
  into `master` with `--no-ff` at natural checkpoints (one component =
  one branch = one merge commit). Never amend, never force-push.
- Ponytail mode (lazy-but-correct, no unrequested abstractions) and ultra
  effort apply throughout - keep solutions as small as they can be while
  still being real and well-tested.

## Where things actually stand

Everything through the four core contracts (`VaultRegistry`, `Cascade`,
`ReserveNote`, `RepoFacility`, plus `DemoInsolventVault`) is written,
tested (unit/fuzz/invariant, all passing - see `docs/progress.md` for
exact counts), and merged to `master`. The deploy scripts are written and
use secure keystore-based signing (`--account <name>`, never a raw private
key in any file or env var).

**The session paused mid-deployment, at a real external-world wall.**

## The wall we hit, in detail

1. Deployed all 6 contracts to Sepolia wired to Aave V3 Sepolia's USDC
   market (`0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8`, confirmed real and
   independently deployed via BGD Labs' `aave-address-book` repo -
   decisions.md #7). All 6 verified cleanly on Etherscan. Addresses are in
   `.env` (gitignored) and in `broadcast/Deploy.s.sol/11155111/run-latest.json`
   (committed - it's just transaction records, no secrets).
2. Funded the registry with 2 USDC, ran `Phase1_RegisterVaults.s.sol` to
   register Aave's real USDC vault + our own `DemoInsolventVault`.
3. **It reverted**: `ERC4626: deposit more than max`, inside
   `VaultRegistry.register()`'s probation deposit into Aave's vault.
4. Investigated with `cast call ... "maxDeposit(address)(uint256)"`:
   - Aave Sepolia USDC: `maxDeposit() == 0`
   - Aave Sepolia DAI: `maxDeposit() == 0`
   - Aave Sepolia USDT: `maxDeposit() == 0`
   - Aave Sepolia LINK/WETH/WBTC/AAVE/EURS: `maxDeposit() == uint256.max`
     (no cap set)
5. **Conclusion**: every major stablecoin market on Aave's Sepolia testnet
   is already at its supply cap (almost certainly other testers' faucet
   activity, totally outside our control). This isn't a bug in our
   contracts - it's a real constraint of the shared public testnet, which
   is exactly the kind of thing "no simulations, real environment" was
   supposed to surface, and did.
6. **A secondary, more interesting finding**: this blocked not just future
   capital allocation but *registration itself*, because
   `VaultRegistry.register()` bundles the probation deposit into the same
   transaction as registration (see `src/VaultRegistry.sol`). That's a
   legitimate design note worth a line in the eventual README: a target
   vault's own constraints (a supply cap, a pause) can block a new
   registration, which is in mild tension with "permissionless
   registration." Not fixing it now (would need decoupling registration
   from the first probation deposit into a separate, retryable step) -
   just documenting it as a known limitation unless there's time later.

## The fix in progress (see `docs/PLAN.md` step 7)

**Switch the whole protocol's asset from Aave Sepolia USDC to Aave Sepolia
EURS** (`0x72B49a461900e11632C95dfa563e7173438D4e3E`, underlying token
`0x6d906e526a4e2Ca02097BA9d0caA3c382F52278E`). Confirmed via `cast call`:
`decimals() == 2` (not 6 - this matters for every hardcoded amount in the
deploy scripts), `maxDeposit() == uint256.max` (open capacity). EURS is a
genuine Euro-pegged stablecoin, so it keeps source.md Text 2's "receive
stablecoin cash" framing intact - this is a real substitution, not a
downgrade to a mock.

This requires **no contract code changes** - `VaultRegistry`, `Cascade`,
`ReserveNote`, and `RepoFacility` are all decimals-agnostic already. Only
`script/deploy/*.sol` constants change (asset address, vault address, and
every hardcoded deposit/allocation amount needs to account for 2 decimals
instead of 6 - e.g. "1 unit" is `100`, not `1e6`).

**This was asked of the user and not yet answered when the session
paused**: confirm go-ahead on the EURS switch, or explore an alternative
first (e.g., a non-Aave protocol's real vault that happens to accept the
same Aave testnet USDC token - unlikely, since that token is Aave's own
internal `TestnetERC20` mock, not official Circle Sepolia USDC, so other
protocols probably don't recognize it at all).

## What's already provisioned, ready to reuse

- `.env` (gitignored, not committed) has: `SEPOLIA_RPC_URL`,
  `ETHERSCAN_API_KEY`, `DEPLOYER_ADDRESS`, `LENDER_ADDRESS`,
  `DEPOSITOR_ADDRESS`, plus the now-superseded USDC-wired addresses
  (`REGISTRY`, `CASCADE`, `L1`, `L2`, `REPO`, `ATTACKER_VAULT`) and
  `USDC`/`AAVE_USDC_STATIC_ATOKEN` constants that will need EURS
  equivalents added alongside (or in place of) them.
- Three local encrypted keystores: `deployer`
  (`0x912dF509297D640AeFd76e229c05909BaF2ef8F1`), `lender`
  (`0xF90242b7F993Fb04Bc08F63220aC918778850365`), `depositor`
  (`0x4fFb27244e48bEAb3a59425f5C8BA41C7cBbbc21`). Private keys were shown
  only in the user's own terminal during `cast wallet new` and are not
  stored anywhere in this repo.
- Deployer has Sepolia ETH (plenty) and 1000 Sepolia USDC (now stranded on
  the abandoned asset - fine, it cost nothing real). Will need Sepolia
  EURS instead: **Aave's Sepolia faucet is a plain contract**, no MetaMask
  or web UI needed -
  ```
  cast send 0xC959483DBa39aa9E78757139af0e9a2EDEb3f42D \
    "mint(address,address,uint256)" <EURS_UNDERLYING> <DEPLOYER_ADDRESS> <amount> \
    --rpc-url $SEPOLIA_RPC_URL --account deployer
  ```
  (same faucet contract used for the USDC mint - just pass the EURS token
  address and remember amounts are 2-decimal, e.g. `100000` = 1000 EURS).
- Lender has 0.02 Sepolia ETH (from deployer) and 100 Sepolia USDC (also
  now-stranded, same fix needed - send lender some Sepolia EURS from
  deployer the same way, via `transfer(address,uint256)` on the EURS
  token once deployer has some).

## Immediate next steps, in order

1. Get the user's go-ahead on the EURS switch (or their alternative).
2. Update `script/deploy/Deploy.s.sol` constants (asset + vault addresses,
   decimals-correct amounts). Update `Phase1-4` scripts' hardcoded amounts
   the same way if any assume 6 decimals.
3. `forge build` to confirm it still compiles (should be trivial - it's
   just constant values changing, no logic changes).
4. User funds deployer (and lender) with Sepolia EURS via the faucet
   contract command above.
5. User runs `Deploy.s.sol` again (`--broadcast --verify`) - new addresses,
   update `.env`.
6. Resume the phased demo: fund registry, Phase 1 (register), wait 10 min,
   Phase 2 (deposit/allocate), Phase 3a/3b (repo open/fill), wait tenor,
   Phase 4 (loss + default/repurchase).
7. Once the on-chain trail is complete, move to `docs/PLAN.md` phases 8
   (dashboard) and 9 (README).

## Prompt for tomorrow's session

Paste this to start the next session:

> Continue the Cascade Reserve project at
> `/home/kryyo1441/code/cascade-reserve`. Read `docs/handoff.md` first -
> it has the full context, including the wall we hit (Aave Sepolia's
> USDC/DAI/USDT markets are supply-capped, blocking vault registration)
> and the fix in progress (switch the protocol's asset to Aave Sepolia's
> EURS market instead, which has open capacity). Also read `source.md`
> (the brief), `decisions.md` (why every design choice was made), and
> `docs/progress.md` / `docs/PLAN.md` for full state. Pick up exactly
> where `docs/handoff.md`'s "Immediate next steps" list leaves off.
