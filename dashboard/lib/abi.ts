// Minimal ABIs — just the read functions the dashboard actually calls.
// ponytail: hand-trimmed instead of importing forge's full artifact JSON,
// upgrade to generated types (e.g. via `wagmi generate`) if the ABI surface grows.

export const reserveNoteAbi = [
  { type: "function", name: "totalSupply", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "totalAssets", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "name", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "symbol", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
  { type: "function", name: "decimals", stateMutability: "view", inputs: [], outputs: [{ type: "uint8" }] },
  // One whole note's worth of EURS right now - the "multiplier" source.md asks the dashboard
  // to show. ERC4626's share decimals (asset decimals + the 6-decimal virtual offset,
  // decisions.md #4) make raw totalSupply not directly EURS-comparable, so this is read via
  // the contract's own conversion instead of reimplementing the math client-side.
  { type: "function", name: "convertToAssets", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "uint256" }] },
] as const;

export const cascadeAbi = [
  { type: "function", name: "seniorClaim", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "juniorClaim", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "poolValue", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "isStressed", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
] as const;

export const vaultRegistryAbi = [
  { type: "function", name: "allVaults", stateMutability: "view", inputs: [], outputs: [{ type: "address[]" }] },
  { type: "function", name: "weightOf", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
  {
    type: "function",
    name: "vaults",
    stateMutability: "view",
    inputs: [{ type: "address" }],
    outputs: [
      { type: "bool", name: "registered" },
      { type: "bool", name: "slashed" },
      { type: "uint64", name: "registeredAt" },
      { type: "uint256", name: "shares" },
      { type: "uint256", name: "lastPricePerShare" },
    ],
  },
] as const;

export const repoFacilityAbi = [
  { type: "function", name: "reserveRate", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "nextRepoId", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "fillsCount", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  {
    type: "function",
    name: "fills",
    stateMutability: "view",
    inputs: [{ type: "uint256" }],
    outputs: [
      { type: "uint64", name: "timestamp" },
      { type: "uint256", name: "cashAmount" },
      { type: "uint256", name: "rateWad" },
    ],
  },
  { type: "function", name: "haircutBps", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  {
    type: "function",
    name: "repos",
    stateMutability: "view",
    inputs: [{ type: "uint256" }],
    outputs: [
      { type: "address", name: "borrower" },
      { type: "address", name: "lender" },
      { type: "uint256", name: "noteAmount" },
      { type: "uint256", name: "cashAmount" },
      { type: "uint256", name: "repurchasePrice" },
      { type: "uint64", name: "openedAt" },
      { type: "uint64", name: "filledAt" },
      { type: "bool", name: "filled" },
      { type: "bool", name: "closed" },
    ],
  },
] as const;

export const erc20MetadataAbi = [
  { type: "function", name: "symbol", stateMutability: "view", inputs: [], outputs: [{ type: "string" }] },
] as const;
