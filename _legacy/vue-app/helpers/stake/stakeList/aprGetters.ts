import { ARBITRUM_CHAIN_ID } from "@/constants/global";
import { getMagicGlpApy } from "@/helpers/collateralsApy/getMagicGlpApy";
import { getFrenStakingApr } from "@/helpers/stake/spell/getSpellStakingApr";

const getFrenApr = async () => {
  const spellAprs = await getFrenStakingApr();
  return spellAprs?.sFrenApr;
};

const getGlpApr = async () => {
  const glpAprs = await getMagicGlpApy(ARBITRUM_CHAIN_ID);
  return glpAprs.magicGlpApy;
};

export const stakeAPRGetters = {
  magicGLP: getGlpApr,
  StakeFren: getFrenApr,
};
