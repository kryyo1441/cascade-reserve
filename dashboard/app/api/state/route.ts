import { publicClient, addresses } from "@/lib/chain";
import { cascadeAbi, reserveNoteAbi, vaultRegistryAbi, repoFacilityAbi, erc20MetadataAbi } from "@/lib/abi";

// Not cached (default for a route handler) - every request is a fresh read of live
// Sepolia state. The dashboard polls this on an interval; no need to opt into caching.

// ReserveNote share decimals = asset decimals (2, EURS) + the 6-decimal virtual offset
// (decisions.md #4) = 8. Fixed because both tiers share the same asset; if that ever stops
// being true, read each note's own `decimals()` instead of hardcoding this.
const ONE_NOTE = 10n ** 8n;

export async function GET() {
  const [
    seniorClaim,
    juniorClaim,
    poolValue,
    isStressed,
    l1Supply,
    l1Assets,
    l1PerNote,
    l2Supply,
    l2Assets,
    l2PerNote,
    vaultList,
    reserveRate,
    nextRepoId,
    fillsCount,
    haircutBps,
  ] = await publicClient.multicall({
    contracts: [
      { address: addresses.cascade, abi: cascadeAbi, functionName: "seniorClaim" },
      { address: addresses.cascade, abi: cascadeAbi, functionName: "juniorClaim" },
      { address: addresses.cascade, abi: cascadeAbi, functionName: "poolValue" },
      { address: addresses.cascade, abi: cascadeAbi, functionName: "isStressed" },
      { address: addresses.l1, abi: reserveNoteAbi, functionName: "totalSupply" },
      { address: addresses.l1, abi: reserveNoteAbi, functionName: "totalAssets" },
      { address: addresses.l1, abi: reserveNoteAbi, functionName: "convertToAssets", args: [ONE_NOTE] },
      { address: addresses.l2, abi: reserveNoteAbi, functionName: "totalSupply" },
      { address: addresses.l2, abi: reserveNoteAbi, functionName: "totalAssets" },
      { address: addresses.l2, abi: reserveNoteAbi, functionName: "convertToAssets", args: [ONE_NOTE] },
      { address: addresses.registry, abi: vaultRegistryAbi, functionName: "allVaults" },
      { address: addresses.repo, abi: repoFacilityAbi, functionName: "reserveRate" },
      { address: addresses.repo, abi: repoFacilityAbi, functionName: "nextRepoId" },
      { address: addresses.repo, abi: repoFacilityAbi, functionName: "fillsCount" },
      { address: addresses.repo, abi: repoFacilityAbi, functionName: "haircutBps" },
    ],
    allowFailure: false,
  });

  const vaultAddrs = vaultList as readonly `0x${string}`[];
  const vaultDetails = vaultAddrs.length
    ? await publicClient.multicall({
        contracts: vaultAddrs.flatMap((addr) => [
          { address: addresses.registry, abi: vaultRegistryAbi, functionName: "vaults", args: [addr] },
          { address: addresses.registry, abi: vaultRegistryAbi, functionName: "weightOf", args: [addr] },
          { address: addr, abi: erc20MetadataAbi, functionName: "symbol" },
        ]),
        allowFailure: true,
      })
    : [];

  const vaults = vaultAddrs.map((address, i) => {
    const info = vaultDetails[i * 3];
    const weight = vaultDetails[i * 3 + 1];
    const symbol = vaultDetails[i * 3 + 2];
    const [registered, slashed, registeredAt, shares] = (info?.result as unknown as readonly [boolean, boolean, bigint, bigint, bigint]) ?? [false, false, 0n, 0n, 0n];
    return {
      address,
      symbol: symbol?.status === "success" ? (symbol.result as string) : "?",
      registered,
      slashed,
      registeredAt: registeredAt?.toString() ?? "0",
      shares: shares?.toString() ?? "0",
      weightWad: weight?.result ? (weight.result as unknown as bigint).toString() : "0",
    };
  });

  const nextRepoIdBig = nextRepoId as unknown as bigint;
  const repoId = nextRepoIdBig > 0n ? nextRepoIdBig - 1n : null;
  const lastRepo =
    repoId !== null
      ? await publicClient.readContract({ address: addresses.repo, abi: repoFacilityAbi, functionName: "repos", args: [repoId] })
      : null;

  return Response.json({
    fetchedAt: new Date().toISOString(),
    cascade: {
      seniorClaim: (seniorClaim as bigint).toString(),
      juniorClaim: (juniorClaim as bigint).toString(),
      poolValue: (poolValue as bigint).toString(),
      isStressed: isStressed as boolean,
    },
    tiers: {
      l1: { supply: (l1Supply as bigint).toString(), assets: (l1Assets as bigint).toString(), perNote: (l1PerNote as bigint).toString() },
      l2: { supply: (l2Supply as bigint).toString(), assets: (l2Assets as bigint).toString(), perNote: (l2PerNote as bigint).toString() },
    },
    vaults,
    repo: {
      reserveRateWad: (reserveRate as bigint).toString(),
      repoCount: (nextRepoId as bigint).toString(),
      fillsCount: (fillsCount as bigint).toString(),
      haircutBps: (haircutBps as bigint).toString(),
      lastRepo: lastRepo
        ? (() => {
            const [borrower, lender, noteAmount, cashAmount, repurchasePrice, openedAt, filledAt, filled, closed] = lastRepo as readonly [
              string,
              string,
              bigint,
              bigint,
              bigint,
              bigint,
              bigint,
              boolean,
              boolean,
            ];
            return {
              id: repoId!.toString(),
              borrower,
              lender,
              noteAmount: noteAmount.toString(),
              cashAmount: cashAmount.toString(),
              repurchasePrice: repurchasePrice.toString(),
              openedAt: openedAt.toString(),
              filledAt: filledAt.toString(),
              filled,
              closed,
            };
          })()
        : null,
    },
  });
}
