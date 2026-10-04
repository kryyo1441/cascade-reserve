# Decisions Log

Every design or tooling choice of any real weight, logged as it's made, so you
can see the reasoning and push back on anything. Format per entry: the
situation, the choices on the table, what was picked, and why.

---

## 1. Smart contract tooling: Foundry + OpenZeppelin

**Situation:** Need a Solidity dev framework to write, test, and deploy the
contracts. `source.md` already names a stack.

**Choices:**
- Foundry (forge/cast/anvil) + OpenZeppelin contracts
- Hardhat (JS/TS-based) + OpenZeppelin

**What I chose:** Foundry + OpenZeppelin v5.

**Why:** `source.md` section 6 specifies this explicitly. Beyond that, Foundry
has fuzz and invariant testing built into the test runner natively (`forge
test --fuzz`, `forge inspect ... invariant`), and the brief's scope requires
exactly that (fuzz + invariant tests). Hardhat would need a separate plugin
for the same coverage. Foundry tests are also written in Solidity itself, so
there's one language for contracts and tests instead of two.

---

## 2. Deployment target: Sepolia

**Situation:** `source.md` interprets "real environment, no simulations" as a
public testnet with verified contracts, not mainnet (too risky for an
unaudited protocol) and not a local-only fork (invisible to anyone but us).
It suggested Sepolia or Base Sepolia.

**Choices:**
- Sepolia (main Ethereum testnet)
- Base Sepolia (L2 testnet)

**What I chose:** Sepolia — your pick.

**Why:** It's the most established public testnet, with the widest faucet
and explorer-verification support, and the most likely place to find a real
third-party ERC-4626 vault already deployed if one exists (relevant to a
later decision on whether to register a real external vault, not just a mock
one, for the demo).

---

## 3. Dashboard: build it, Next.js + shadcn/ui + lucide-react

**Situation:** `source.md` lists a Next.js dashboard as optional but
valuable — a read-only viewer of live testnet state (note supply per tier,
vault weights, current Reserve Rate).

**Choices:**
- Skip it, contracts-only
- Build it

**What I chose:** Build it, using Next.js, shadcn/ui components, and
lucide-react icons — your call, and it fits your strongest area (Next.js) so
it's a cheap way to make the working system demonstrable without reading raw
contract calls off Etherscan.

**Why:** Direct user instruction. Will invoke the `ui-ux-pro-max` skill for
the actual design/layout work when that phase starts.

---

## 4. Reserve Note mechanics: non-rebasing, not rebasing

**Situation:** Source Text 1 explicitly calls the Reserve Note a "rebasing
token" on top of ERC-4626. But standard ERC-4626 doesn't rebase balances —
instead the share-to-asset conversion rate rises as the vault earns yield,
so your balance stays fixed while its redeemable value grows. "Rebasing
4626" is an unusual, non-standard combination: you'd need a second wrapper
layer on top of 4626 that rewrites `balanceOf` for every holder on every
accrual, which breaks composability with anything expecting a normal ERC20
(DEX pools, other protocols reading balances) and adds real complexity and
attack surface for no functional gain here.

**Choices:**
- Non-rebasing, standard ERC-4626 share-price accrual
- True rebasing balance (custom wrapper, non-standard)

**What I chose:** Non-rebasing.

**Why I deviated from the literal source text:** The source text's own
"interpretation" section (source.md §5.2) flags this exact tension and
recommends picking non-rebasing and justifying it — so the brief itself
already expects a deviation here, not blind literal implementation.
Economically, what the source text actually wants — note value rising with
earned yield, deeper notes earning more — is fully achievable with standard
non-rebasing 4626 share pricing; "rebasing" isn't a requirement of the
economics, it's an implementation detail the source text got loosely
specified (most likely because it's describing stETH-style rebasing tokens
by analogy, without being precise about how 4626 actually represents yield).
Following the literal word "rebasing" here would mean building a
non-standard, harder-to-audit token for a cosmetic property (balance number
visibly growing) instead of the substance (value growing) — exactly the kind
of over-literal implementation the brief's own "likely evaluation criteria"
section (source.md §5.4) warns against ("whether the candidate blindly
implements everything... or scopes sensibly"). Given zero Solidity
experience on the team, standard/audited patterns are also the safer choice
to be able to explain and defend under questioning.

---

## 5. Vault scoring bootstrap: small capped probation allocation

**Situation:** A registered vault starts at zero allocation weight, and
weight is supposed to grow from "observed redemption history" over the
observation window. But neither source text resolves the chicken-and-egg
problem: if zero weight means zero cascade capital ever flows to a vault,
the cascade never actually observes any redemption behavior from it, so
weight could never rise. This gap is one of the "undefined component" issues
flagged in source.md §5.2 ("discovery engine... never specified").

**Choices:**
- Small, hard-capped probation allocation: deposit a small fixed amount into
  a newly registered vault during its observation window, so the cascade
  genuinely observes real deposit/redeem behavior from its own on-chain
  interactions with that vault
- Zero-capital checkpointing: never deposit cascade capital during probation;
  instead let anyone permissionlessly call a checkpoint function that records
  the vault's own reported share price over time

**What I chose:** Small capped probation allocation.

**Why I'm making this case (the term isn't in the source texts at all, so
this is filled in from scratch, not a deviation from a stated choice):**
The texts repeatedly emphasize that trust must be "earned, never granted"
and scored from "each candidate market's own on-chain redemption history" —
not from numbers the vault reports about itself. Checkpointing a vault's own
share price is just reading a number the vault computes and exposes itself;
if the vault is malicious it can misreport that number, so checkpointing
alone doesn't actually test anything adversarial. A capped probation
allocation means the cascade itself calls `deposit`/`redeem` against the
candidate vault and watches what actually happens to its own funds — a
genuine behavioral test, with the blast radius bounded by the cap. This
matches the "bad actor can register freely, because registering with no
track record buys them nothing to exploit" principle in source.md: the cap
is what keeps "nothing to exploit" true even while real capital is used to
generate real data.

---

## 6. Sepolia demo: real external vault + our own attacker vault

**Situation:** The brief's "no simulations, real environment" instruction
should mean the permissionless registration is tested against something we
don't control, not just our own mocks end to end.

**Choices:**
- Register a real, independent ERC-4626 vault deployed by someone else on
  Sepolia (if one can be found), plus a vault we deploy and deliberately
  make insolvent for the loss/waterfall test scenario
- Use only vaults we deploy ourselves for everything

**What I chose:** Real external vault + our own attacker vault — your call.

**Why:** Proves permissionless registration actually works against a genuine
third-party contract we have no special relationship with, not just our own
code pretending to be external. The insolvent vault is framed honestly as a
malicious/negligent registrant — which is exactly the adversarial case
Text 1's "bad actor can register freely" design is meant to survive — rather
than quietly mislabeling a mock as something it isn't.

---

## 7. Real external vault pick: Aave V3 Sepolia `StaticATokenV3`, not Morpho Blue

**Situation:** Text 1 frames Morpho Blue as "the market layer" to sit on.
I checked Morpho's own official SDK (`@morpho-org/morpho-ts`, cloned from
`morpho-org/sdks` on GitHub) — its `ChainId` enum lists only mainnets/L2
mainnets (Ethereum, Base, Arbitrum, Optimism, Polygon, etc.). No Sepolia, no
Base Sepolia, anywhere in the SDK or Morpho Blue's own repo. Morpho Blue is
not deployed on any public testnet we can use.

**Choices:**
- Treat the registry as protocol-agnostic (which is how source.md already
  specifies it — "any ERC-4626-compliant vault can register") and register a
  different real, independently-deployed ERC-4626 vault on Sepolia instead
  of Morpho specifically
- Deploy our own mock contract that mimics a Morpho Blue market, labeled as
  a stand-in
- Use a mainnet fork to reach the real Morpho Blue (rejected already —
  source.md §5.3 calls a mainnet fork "arguably a simulation")

**What I chose:** Register Aave V3's real Sepolia deployment — specifically
its `StaticATokenV3` wrapper (confirmed deployed at
`0x8A88124522dbBF1E56352ba3DE1d9F78C143751e` for USDC, from BGD Labs' own
`aave-address-book` repo), which is a genuine, independent, ERC-4626-
compliant vault, alongside our own deliberately-insolvent vault for the loss
test (decision 6).

**Why:** This isn't actually a deviation from your brief — source.md's own
"out of scope unless clearly achievable" list already names "full Morpho
Blue integration across live markets." The registry's job is to accept any
4626-compliant vault permissionlessly; Morpho was the source text's
illustrative example of *why* that's valuable (because Morpho vaults happen
to be 4626-compatible), not a hard dependency of the registry contract
itself. Aave V3 being genuinely live on Sepolia, audited, and 4626-compliant
via its official wrapper makes it a stronger real-world proof point than a
mock would be, for zero extra custom code.

---
</content>
