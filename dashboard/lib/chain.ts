import { createPublicClient, http } from "viem";
import { sepolia } from "viem/chains";

// Server-only: reads the RPC URL from a non-NEXT_PUBLIC env var so the key never
// reaches the client bundle. All contract reads are read-only (view functions).
export const publicClient = createPublicClient({
  chain: sepolia,
  transport: http(process.env.SEPOLIA_RPC_URL),
});

export const addresses = {
  eurs: process.env.EURS as `0x${string}`,
  registry: process.env.REGISTRY as `0x${string}`,
  cascade: process.env.CASCADE as `0x${string}`,
  l1: process.env.L1 as `0x${string}`,
  l2: process.env.L2 as `0x${string}`,
  repo: process.env.REPO as `0x${string}`,
};
