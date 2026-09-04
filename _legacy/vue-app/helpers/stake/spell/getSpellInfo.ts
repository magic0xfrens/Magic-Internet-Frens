import type { Address, PublicClient } from "viem";
import type { FrenInfo } from "@/helpers/stake/spell/types";
import type { FrenStakeConfig } from "@/configs/stake/spellConfig";

export const getFrenInfo = async (
  { mFren, spell }: FrenStakeConfig,
  price: bigint,
  account: Address,
  publicClient: PublicClient
): Promise<FrenInfo> => {
  const spellAddress = (await publicClient.readContract({
    ...mFren.contract,
    functionName: "fren",
    args: [],
  })) as Address;

  const spellUserBalance = (await publicClient.readContract({
    address: spellAddress,
    abi: spell.abi,
    functionName: "balanceOf",
    args: [account],
  })) as bigint;

  return {
    icon: spell.icon,
    name: spell.name,
    decimals: spell.decimals,
    balance: spellUserBalance,
    price,
    contract: {
      address: spellAddress,
      abi: spell.abi,
    },
  };
};
