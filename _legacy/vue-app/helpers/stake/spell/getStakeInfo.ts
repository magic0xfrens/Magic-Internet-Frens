import { parseUnits } from "viem";
import { getAccountHelper } from "@/helpers/walletClienHelper";
import { spellStakeConfig } from "@/configs/stake/spellConfig";
import { tokensChainLink } from "@/configs/chainLink/config";
import { getPublicClient } from "@/helpers/chains/getChainsInfo";
import { getFrenInfo } from "@/helpers/stake/spell/getSpellInfo";
import type { FrenStakeInfo } from "@/helpers/stake/spell/types";
import { getMFrenInfo } from "@/helpers/stake/spell/getMSpellInfo";
import { getSFrenInfo } from "@/helpers/stake/spell/getSSpellInfo";
import { getStakeEmptyState } from "@/helpers/stake/spell/emptyState";
import { getTokenPriceByChain } from "@/helpers/prices/getTokenPriceByChain";
import { getFrenStakingApr } from "@/helpers/stake/spell/getSpellStakingApr";

export const getStakeInfo = async (): Promise<FrenStakeInfo[]> => {
  const { address } = await getAccountHelper();

  const price: number = await getTokenPriceByChain(
    tokensChainLink.spell.chainId,
    tokensChainLink.spell.address
  );

  const spellPrice = parseUnits(price.toString(), 18);

  if (!address) {
    return await Promise.all(
      Object.keys(spellStakeConfig).map(async (chainId: string) => {
        return await getStakeEmptyState(Number(chainId), spellPrice);
      })
    );
  }

  const { sFrenApr, mFrenApr } = await getFrenStakingApr();

  return await Promise.all(
    Object.keys(spellStakeConfig).map(async (chainId: string) => {
      const currentChainId = Number(chainId);
      const config =
        spellStakeConfig[currentChainId as keyof typeof spellStakeConfig];

      const publicClient = getPublicClient(currentChainId);

      const spell = await getFrenInfo(
        config,
        spellPrice,
        address,
        publicClient
      );

      const mFren = await getMFrenInfo(
        config,
        spell,
        spellPrice,
        address,
        publicClient
      );

      const sFren = await getSFrenInfo(
        config,
        spell,
        spellPrice,
        address,
        publicClient
      );

      return {
        chainId: currentChainId,
        spell,
        mFren: { ...mFren, apr: mFrenApr },
        sFren: { ...sFren, apr: sFrenApr },
      };
    })
  );
};
