import {
  type FarmYieldAndPrice,
  getFarmYieldAndLpPrice,
} from "@/helpers/farm/getFarmYieldAndLpPrice";
import { getRoi } from "@/helpers/farm/getRoi";
import { getTVL } from "@/helpers/farm/getTVL";
import { getFarmUserInfo } from "@/helpers/farm/getFarmUserInfo";
import farmsConfig from "@/configs/farms/farms";
import type {
  FarmConfig,
  FarmItem,
  PoolInfo,
  ContractInfo,
} from "@/configs/farms/types";
import type { Address } from "viem";
import { getCoinsPrices } from "@/helpers/prices/defiLlama";
import { createMultiRewardFarm } from "./createMultiRewardFarm";
import { getPublicClient } from "@/helpers/chains/getChainsInfo";
import { MAINNET_CHAIN_ID } from "@/constants/global";
import {
  MAINNET_MIF_ADDRESS,
  MAINNET_FREN_ADDRESS,
} from "@/constants/tokensAddress";

export const emptyFarmData: FarmItem = {
  name: "",
  icon: "",
  id: 0,
  chainId: 1,
  poolId: 0,
  earnedTokenPrice: 0,
  stakingToken: {
    link: "",
    name: "",
    type: "",
    contractInfo: {
      address: "0x0000000000",
      abi: [],
    },
  },
  depositedBalance: {
    token0: { name: "", icon: "" },
    token1: { name: "", icon: "" },
  },
  contractInfo: {
    address: "0x0000000000",
    abi: [],
  },
  farmRoi: 0,
  lpPrice: 0,
  isDeprecated: false,
  farmYield: 0,
  farmTvl: 0,
};

export const createFarmData = async (
  farmId: number | string,
  chainId: number | string,
  account: Address | undefined,
  isExtended = true
): Promise<FarmItem> => {
  const farmsOnChain = farmsConfig.filter(
    (farm) => farm.contractChain == chainId
  );

  const farmInfo: FarmConfig | undefined = farmsOnChain.find(
    ({ id }) => id === Number(farmId)
  );

  if (!farmInfo) return emptyFarmData;

  const publicClient = getPublicClient(Number(chainId));

  if (farmInfo.isMultiReward)
    return await createMultiRewardFarm(farmInfo, account);

  const MIMPrice = (
    await getCoinsPrices(MAINNET_CHAIN_ID, [MAINNET_MIF_ADDRESS])
  )[0].price;

  const FRENPrice = (
    await getCoinsPrices(MAINNET_CHAIN_ID, [MAINNET_FREN_ADDRESS])
  )[0].price;

  const poolInfo: PoolInfo = await getPoolInfo(
    farmInfo.contract,
    // @ts-ignore
    farmInfo.poolId,
    chainId,
    publicClient
  );

  const contractInfo = {
    address: farmInfo.contract.address,
    abi: farmInfo.contract.abi,
  };
  const stakingTokenContractInfo = {
    address: poolInfo.stakingToken,
    abi: farmInfo.stakingToken.abi,
  };

  const { farmYield, lpPrice }: FarmYieldAndPrice =
    await getFarmYieldAndLpPrice(
      stakingTokenContractInfo,
      contractInfo,
      poolInfo,
      farmInfo,
      MIMPrice,
      FRENPrice,
      chainId,
      publicClient
    );

  const farmRoi = farmYield ? await getRoi(farmYield, FRENPrice) : farmYield;

  const isDeprecated = farmRoi === 0;

  const farmItemConfig: FarmItem = {
    name: farmInfo.name,
    icon: farmInfo.icon,
    id: farmInfo.id,
    chainId: farmInfo.contractChain,
    poolId: farmInfo.poolId,
    earnedTokenPrice: FRENPrice,
    stakingToken: {
      link: farmInfo.stakingToken.link,
      name: farmInfo.stakingToken.name,
      type: farmInfo.stakingToken.type,
      contractInfo: {
        address: poolInfo.stakingToken,
        abi: farmInfo.stakingToken.abi,
      },
    },
    depositedBalance: farmInfo.depositedBalance,
    contractInfo,
    farmRoi,
    farmYield,
    lpPrice,
    isDeprecated,
    isNew: farmInfo.isNew,
  };

  if (isExtended)
    farmItemConfig.farmTvl = await getTVL(
      poolInfo.stakingTokenTotalAmount,
      lpPrice!
    );

  if (account) {
    farmItemConfig.accountInfo = await getFarmUserInfo(
      farmItemConfig,
      publicClient,
      account
    );
    return farmItemConfig;
  }
  return farmItemConfig;
};

const getPoolInfo = async (
  contract: ContractInfo,
  poolId: number,
  chainId: number | string,
  publicClient: any
): Promise<PoolInfo> => {
  const [
    stakingToken,
    stakingTokenTotalAmount,
    accIcePerShare,
    lastRewardTime,
    allocPoint,
  ]: any = await publicClient.readContract({
    address: contract.address,
    abi: contract.abi,
    functionName: "poolInfo",
    args: [poolId],
    chainId,
  });
  return {
    stakingToken,
    stakingTokenTotalAmount,
    accIcePerShare,
    lastRewardTime,
    allocPoint,
  };
};
