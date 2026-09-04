import type { PublicClient } from "viem";
import type { ContractInfo } from "@/types/global";
import { ONE_ETHER_VIEM } from "@/constants/global";
import { MAINNET_FREN_ADDRESS } from "@/constants/tokensAddress";

export const getFrenToSFrenRate = async (
  spell: ContractInfo,
  sFren: ContractInfo,
  publicClient: PublicClient
) => {
  try {
    const [spellSFrenBalance, totalSupply] = await publicClient.multicall({
      contracts: [
        {
          address: MAINNET_FREN_ADDRESS,
          abi: spell.abi,
          functionName: "balanceOf",
          args: [sFren.address],
        },
        {
          ...sFren,
          functionName: "totalSupply",
          args: [],
        },
      ],
    });

    return (
      ((spellSFrenBalance.result as bigint) * ONE_ETHER_VIEM) /
      (totalSupply.result as bigint)
    );
  } catch (error) {
    return ONE_ETHER_VIEM;
  }
};
