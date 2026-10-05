// EURS has 2 decimals (decisions.md #10) - every raw on-chain amount here is in EURS's
// own base units, not 1e18. wad values (prices, rates) are still 1e18 as usual.
const EURS_DECIMALS = 2;
// Share decimals = asset decimals (2) + the 6-decimal virtual offset (decisions.md #4).
const NOTE_DECIMALS = 8;

export function fmtEurs(raw: string): string {
  const n = Number(raw) / 10 ** EURS_DECIMALS;
  return n.toLocaleString(undefined, { maximumFractionDigits: 2 }) + " EURS";
}

export function fmtNotes(raw: string): string {
  const n = Number(raw) / 10 ** NOTE_DECIMALS;
  return n.toLocaleString(undefined, { maximumFractionDigits: 4 }) + " notes";
}

export function fmtWadPct(raw: string): string {
  const n = Number(raw) / 1e18;
  return (n * 100).toLocaleString(undefined, { maximumFractionDigits: 2 }) + "%";
}

export function fmtWeight(raw: string): string {
  // MAX_WEIGHT = 1e18 = fully trusted
  const n = Number(raw) / 1e18;
  return (n * 100).toFixed(0) + "%";
}

export function shortAddr(addr: string): string {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

export function fmtTimestamp(raw: string): string {
  if (raw === "0") return "—";
  return new Date(Number(raw) * 1000).toLocaleString();
}
