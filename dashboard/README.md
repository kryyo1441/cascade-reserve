# Cascade Reserve dashboard

A read-only Next.js dashboard over the live Sepolia deployment (see the root
`docs/PLAN.md` phase 8, `decisions.md` #3). Shows: note supply and value per
note for each tier (the "multiplier" reading), registered vault weights, the
current Reserve Rate, and the latest repo — plus two shadcn/recharts charts
(pool composition, Reserve Rate history from on-chain fills). Desktop gets a
stretched 2-3 column layout (`lg:` breakpoints); mobile stays single-column.
Chart colors come from the `dataviz` skill's validated categorical palette
(`app/globals.css`'s `--chart-1..5`), not shadcn's default grayscale.

No wallet connection, no writes — it's a viewer. All chain reads happen
server-side in `app/api/state/route.ts` (so the RPC URL never reaches the
client bundle) via a single `viem` multicall; the page polls that route
every 15s.

## Running it

```bash
cp .env.local.example .env.local   # fill in SEPOLIA_RPC_URL + the 6 contract addresses
npm install
npm run dev
```

## Files worth knowing about

- `lib/chain.ts` — the viem public client + contract addresses, read from env.
- `lib/abi.ts` — hand-trimmed ABIs (just the view functions this page calls).
- `lib/format.ts` (+ `format.test.ts`) — raw on-chain units → display strings.
  EURS has 2 decimals; ReserveNote shares have 8 (2 + the 6-decimal virtual
  offset from decisions.md #4) — getting these mixed up is the one way this
  page silently shows numbers that are wildly wrong instead of erroring, so
  there's a runnable check: `npx tsx lib/format.test.ts`.
- `app/api/state/route.ts` — the one server-side read.
- `app/page.tsx` — the whole UI (small enough not to split further yet).
