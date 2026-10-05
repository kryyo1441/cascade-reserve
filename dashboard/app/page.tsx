"use client";

import { useEffect, useState } from "react";
import { Bar, BarChart, CartesianGrid, Cell, Line, LineChart, XAxis, YAxis } from "recharts";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { ChartContainer, ChartTooltip, ChartTooltipContent, type ChartConfig } from "@/components/ui/chart";
import { Shield, Landmark, AlertTriangle, Percent, RefreshCw } from "lucide-react";
import type { CascadeState } from "@/lib/types";
import { fmtEurs, fmtNotes, fmtWadPct, fmtWeight, shortAddr, fmtTimestamp } from "@/lib/format";

const POLL_MS = 15_000;

const poolChartConfig = {
  claim: { label: "Claim on pool" },
  senior: { label: "L1 Senior", color: "var(--chart-1)" },
  junior: { label: "L2 Junior", color: "var(--chart-2)" },
} satisfies ChartConfig;

const rateChartConfig = {
  ratePct: { label: "Reserve Rate (annualized)", color: "var(--chart-1)" },
} satisfies ChartConfig;

export default function Dashboard() {
  const [state, setState] = useState<CascadeState | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    async function load() {
      try {
        const res = await fetch("/api/state", { cache: "no-store" });
        if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
        const data = await res.json();
        if (!cancelled) {
          setState(data);
          setError(null);
        }
      } catch (e) {
        if (!cancelled) setError(e instanceof Error ? e.message : "failed to load");
      }
    }
    load();
    const id = setInterval(load, POLL_MS);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, []);

  return (
    <main className="mx-auto max-w-7xl px-4 py-10 space-y-6">
      <header className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold">Cascade Reserve</h1>
          <p className="text-sm text-muted-foreground">Live Sepolia testnet state — read-only</p>
        </div>
        <div className="flex items-center gap-2 text-xs text-muted-foreground">
          <RefreshCw className="size-3" />
          {state ? `updated ${new Date(state.fetchedAt).toLocaleTimeString()}` : "loading…"}
        </div>
      </header>

      {error && (
        <Card className="border-destructive">
          <CardContent className="pt-6 text-destructive text-sm">Couldn&apos;t reach the chain: {error}</CardContent>
        </Card>
      )}

      {!state && !error && (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {Array.from({ length: 4 }).map((_, i) => (
            <Skeleton key={i} className="h-32 w-full" />
          ))}
        </div>
      )}

      {state && (
        <>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <TierCard title="L1 — Senior" icon={<Shield className="size-4" />} tier={state.tiers.l1} claim={state.cascade.seniorClaim} />
            <TierCard title="L2 — Junior" icon={<Landmark className="size-4" />} tier={state.tiers.l2} claim={state.cascade.juniorClaim} />

            <Card>
              <CardHeader className="flex-row items-center justify-between">
                <CardTitle className="text-base">Reserve status</CardTitle>
                {state.cascade.isStressed ? (
                  <Badge variant="destructive" className="gap-1">
                    <AlertTriangle className="size-3" /> Stressed
                  </Badge>
                ) : (
                  <Badge variant="secondary">Healthy</Badge>
                )}
              </CardHeader>
              <CardContent className="grid grid-cols-2 gap-4 text-sm">
                <Stat label="Pool value" value={fmtEurs(state.cascade.poolValue)} />
                <Stat label="Reserve Rate" value={fmtWadPct(state.repo.reserveRateWad)} icon={<Percent className="size-3" />} />
                <Stat label="Repo haircut" value={`${(Number(state.repo.haircutBps) / 100).toFixed(1)}%`} />
                <Stat label="Repos / fills" value={`${state.repo.repoCount} / ${state.repo.fillsCount}`} />
              </CardContent>
            </Card>
          </div>

          <div className="grid gap-4 lg:grid-cols-2">
            <Card>
              <CardHeader>
                <CardTitle className="text-base">Pool composition</CardTitle>
              </CardHeader>
              <CardContent>
                <PoolCompositionChart senior={state.cascade.seniorClaim} junior={state.cascade.juniorClaim} />
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle className="text-base">Reserve Rate history</CardTitle>
              </CardHeader>
              <CardContent>
                <ReserveRateChart fills={state.repo.fillHistory} />
              </CardContent>
            </Card>
          </div>

          <div className="grid gap-4 lg:grid-cols-2">
            <Card>
              <CardHeader>
                <CardTitle className="text-base">Registered vaults</CardTitle>
              </CardHeader>
              <CardContent className="space-y-3">
                {state.vaults.length === 0 && <p className="text-sm text-muted-foreground">None registered.</p>}
                {state.vaults.map((v) => (
                  <div key={v.address} className="flex items-center justify-between rounded-md border p-3 text-sm">
                    <div>
                      <div className="font-medium">{v.symbol}</div>
                      <div className="text-xs text-muted-foreground">{shortAddr(v.address)}</div>
                    </div>
                    <div className="text-right">
                      <div>{v.slashed ? <Badge variant="destructive">Slashed</Badge> : <Badge variant="outline">{fmtWeight(v.weightWad)} trust</Badge>}</div>
                      <div className="text-xs text-muted-foreground">registered {fmtTimestamp(v.registeredAt)}</div>
                    </div>
                  </div>
                ))}
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle className="text-base">Repo market</CardTitle>
              </CardHeader>
              <CardContent className="space-y-3 text-sm">
                <div className="flex gap-6 text-muted-foreground">
                  <span>{state.repo.repoCount} opened</span>
                  <span>{state.repo.fillsCount} fills</span>
                </div>
                {state.repo.lastRepo && (
                  <div className="rounded-md border p-3">
                    <div className="flex items-center justify-between">
                      <span className="font-medium">Repo #{state.repo.lastRepo.id}</span>
                      <StatusBadge repo={state.repo.lastRepo} />
                    </div>
                    <div className="mt-2 grid grid-cols-2 gap-2 text-xs text-muted-foreground">
                      <span>borrower {shortAddr(state.repo.lastRepo.borrower)}</span>
                      <span>lender {state.repo.lastRepo.lender === "0x0000000000000000000000000000000000000000" ? "—" : shortAddr(state.repo.lastRepo.lender)}</span>
                      <span>cash {fmtEurs(state.repo.lastRepo.cashAmount)}</span>
                      <span>repurchase {fmtEurs(state.repo.lastRepo.repurchasePrice)}</span>
                    </div>
                  </div>
                )}
              </CardContent>
            </Card>
          </div>
        </>
      )}
    </main>
  );
}

function TierCard({ title, icon, tier, claim }: { title: string; icon: React.ReactNode; tier: { supply: string; perNote: string }; claim: string }) {
  return (
    <Card>
      <CardHeader className="flex-row items-center gap-2">
        {icon}
        <CardTitle className="text-base">{title}</CardTitle>
      </CardHeader>
      <CardContent className="grid grid-cols-2 gap-3 text-sm">
        <Stat label="Notes outstanding" value={fmtNotes(tier.supply)} />
        <Stat label="Claim on pool" value={fmtEurs(claim)} />
        <Stat label="Value per note" value={fmtEurs(tier.perNote)} />
      </CardContent>
    </Card>
  );
}

function Stat({ label, value, icon }: { label: string; value: string; icon?: React.ReactNode }) {
  return (
    <div>
      <div className="flex items-center gap-1 text-xs text-muted-foreground">
        {icon}
        {label}
      </div>
      <div className="font-medium">{value}</div>
    </div>
  );
}

function StatusBadge({ repo }: { repo: { filled: boolean; closed: boolean } }) {
  if (!repo.filled) return <Badge variant="outline">Open</Badge>;
  if (!repo.closed) return <Badge variant="secondary">Filled</Badge>;
  return <Badge variant="default">Closed</Badge>;
}

// Two categories (Senior, Junior) - identity, not magnitude alone, so each bar keeps its own
// fixed categorical slot (chart-1/chart-2) rather than a single uniform series color.
function PoolCompositionChart({ senior, junior }: { senior: string; junior: string }) {
  const data = [
    { tier: "L1 Senior", claim: Number(senior) / 100, fill: "var(--color-senior)" },
    { tier: "L2 Junior", claim: Number(junior) / 100, fill: "var(--color-junior)" },
  ];
  return (
    <ChartContainer config={poolChartConfig} className="h-[220px] w-full">
      <BarChart data={data} layout="vertical" margin={{ left: 8 }}>
        <CartesianGrid horizontal={false} stroke="var(--border)" />
        <XAxis type="number" tickLine={false} axisLine={false} tickFormatter={(v) => `${v} EURS`} />
        <YAxis type="category" dataKey="tier" tickLine={false} axisLine={false} width={80} />
        <ChartTooltip content={<ChartTooltipContent formatter={(value) => `${value} EURS`} />} />
        <Bar dataKey="claim" radius={4}>
          {data.map((entry) => (
            <Cell key={entry.tier} fill={entry.fill} />
          ))}
        </Bar>
      </BarChart>
    </ChartContainer>
  );
}

// Single series (one Reserve Rate line) - no legend needed, title names the series.
function ReserveRateChart({ fills }: { fills: { timestamp: string; rateWad: string }[] }) {
  if (fills.length === 0) {
    return <p className="flex h-[220px] items-center justify-center text-sm text-muted-foreground">No fills yet.</p>;
  }
  const data = fills.map((f) => ({
    time: new Date(Number(f.timestamp) * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }),
    ratePct: (Number(f.rateWad) / 1e18) * 100,
  }));
  return (
    <ChartContainer config={rateChartConfig} className="h-[220px] w-full">
      <LineChart data={data} margin={{ left: 8, right: 8 }}>
        <CartesianGrid vertical={false} stroke="var(--border)" />
        <XAxis dataKey="time" tickLine={false} axisLine={false} />
        <YAxis tickLine={false} axisLine={false} tickFormatter={(v) => `${v}%`} width={60} />
        <ChartTooltip content={<ChartTooltipContent formatter={(value) => `${Number(value).toFixed(2)}%`} />} />
        <Line type="monotone" dataKey="ratePct" stroke="var(--color-ratePct)" strokeWidth={2} dot={{ r: 4 }} />
      </LineChart>
    </ChartContainer>
  );
}
