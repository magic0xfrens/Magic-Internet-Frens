import type {
  MFrenInfo,
  SFrenInfo,
  FrenInfo,
} from "@/helpers/stake/spell/types";
import type { Address } from "viem";
import { useImage } from "@/helpers/useImage";
import tokensAbi from "@/abis/tokensAbi/index";
import { spellStakeConfig } from "@/configs/stake/spellConfig";
import type { SFrenConfig } from "@/configs/stake/spellConfig";
import { getPublicClient } from "@/helpers/chains/getChainsInfo";
import { MAINNET_CHAIN_ID, ONE_ETHER_VIEM } from "@/constants/global";
import { getFrenStakingApr } from "@/helpers/stake/spell/getSpellStakingApr";
import { getFrenToSFrenRate } from "@/helpers/stake/spell/getSpellToSSpellRate";

const getFrenEmptyState = async (
  chainId: number,
  spellPrice: bigint
): Promise<FrenInfo> => {
  const publicClient = getPublicClient(chainId);

  const spellConfig =
    spellStakeConfig[chainId as keyof typeof spellStakeConfig].spell;

  const mFrenContract =
    spellStakeConfig[chainId as keyof typeof spellStakeConfig].mFren.contract;

  const spellAddress = (await publicClient.readContract({
    ...mFrenContract,
    functionName: "fren",
    args: [],
  })) as Address;

  return {
    balance: 0n,
    decimals: 18,
    icon: spellConfig.icon,
    name: spellConfig.name,
    price: spellPrice || ONE_ETHER_VIEM,
    contract: {
      address: spellAddress,
      abi: tokensAbi.FREN,
    },
  };
};

const getMFrenEmptyState = async (
  chainId: number,
  spellPrice: bigint,
  apr: string
): Promise<MFrenInfo> => {
  const publicClient = getPublicClient(chainId);

  const spellConfig =
    spellStakeConfig[chainId as keyof typeof spellStakeConfig].spell;

  const mFrenConfig =
    spellStakeConfig[chainId as keyof typeof spellStakeConfig].mFren;

  const spellAddress = (await publicClient.readContract({
    address: mFrenConfig.contract.address,
    abi: mFrenConfig.contract.abi,
    functionName: "fren",
    args: [],
  })) as Address;

  const totalSupply = (await publicClient.readContract({
    address: spellAddress,
    abi: spellConfig.abi,
    functionName: "balanceOf",
    args: [mFrenConfig.contract.address],
  })) as bigint;

  return {
    name: mFrenConfig.name,
    icon: mFrenConfig.icon,
    rateIcon: useImage("assets/images/mspell-icon.svg"),
    decimals: mFrenConfig.decimals,
    contract: mFrenConfig.contract,
    price: spellPrice,
    rate: ONE_ETHER_VIEM,
    lockTimestamp: "0",
    balance: 0n,
    approvedAmount: 0n,
    claimableAmount: 0n,
    totalSupply,
    apr,
  };
};

const getSFrenEmptyState = async (
  chainId: number,
  spellPrice: bigint,
  spell: FrenInfo,
  apr: string
): Promise<SFrenInfo> => {
  // if (chainId !== MAINNET_CHAIN_ID) return null;

  const sFrenConfig = spellStakeConfig[
    MAINNET_CHAIN_ID as keyof typeof spellStakeConfig
  ].sFren as SFrenConfig;

  const publicClient = getPublicClient(MAINNET_CHAIN_ID);

  const spellToSFrenRate = await getFrenToSFrenRate(
    spell.contract,
    sFrenConfig.contract,
    publicClient
  );

  const sFrenPrice = (spellPrice * spellToSFrenRate) / ONE_ETHER_VIEM;

  const totalSupply = await publicClient.readContract({
    ...sFrenConfig.contract,
    functionName: "totalSupply",
    args: [],
  });

  return {
    name: sFrenConfig?.name || "sFren",
    icon: sFrenConfig?.icon || useImage("assets/images/sspell-icon.svg"),
    rateIcon: useImage("assets/images/sspell-icon.svg"),
    decimals: 18,
    contract: sFrenConfig.contract,
    price: sFrenPrice,
    rate: spellToSFrenRate,
    lockTimestamp: "0",
    balance: 0n,
    approvedAmount: 0n,
    totalSupply: totalSupply as bigint,
    apr,
  };
};

export const getStakeEmptyState = async (
  chainId: number,
  spellPrice: bigint
) => {
  const spell = await getFrenEmptyState(chainId, spellPrice);
  const { sFrenApr, mFrenApr } = await getFrenStakingApr();
  const mFrenEmptyState = await getMFrenEmptyState(
    chainId,
    spellPrice,
    mFrenApr
  );
  const sFren = await getSFrenEmptyState(
    chainId,
    spellPrice,
    spell,
    sFrenApr
  );

  return {
    chainId,
    spell: spell,
    sFren: sFren,
    mFren: mFrenEmptyState,
  };
};
