export type TierState = { supply: string; assets: string; perNote: string };

export type VaultState = {
  address: string;
  symbol: string;
  registered: boolean;
  slashed: boolean;
  registeredAt: string;
  shares: string;
  weightWad: string;
};

export type RepoState = {
  id: string;
  borrower: string;
  lender: string;
  noteAmount: string;
  cashAmount: string;
  repurchasePrice: string;
  openedAt: string;
  filledAt: string;
  filled: boolean;
  closed: boolean;
};

export type CascadeState = {
  fetchedAt: string;
  cascade: { seniorClaim: string; juniorClaim: string; poolValue: string; isStressed: boolean };
  tiers: { l1: TierState; l2: TierState };
  vaults: VaultState[];
  repo: { reserveRateWad: string; repoCount: string; fillsCount: string; haircutBps: string; lastRepo: RepoState | null };
};
