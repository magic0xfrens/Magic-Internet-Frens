import moment from "moment";
import { formatUnits } from "viem";
import { useImage } from "@/helpers/useImage";
import type { Address, PublicClient } from "viem";
import { ONE_ETHER_VIEM } from "@/constants/global";
import type { FrenStakeConfig } from "@/configs/stake/spellConfig";
import type { MFrenInfo, FrenInfo } from "@/helpers/stake/spell/types";

export const getMFrenInfo = async (
  { mFren }: FrenStakeConfig,
  spell: FrenInfo,
  price: bigint,
  account: Address,
  publicClient: PublicClient
): Promise<MFrenInfo> => {
  const [approvedAmount, totalSupply, mFrenUserInfo, rewardAmount] =
    await publicClient.multicall({
      contracts: [
        {
          ...spell.contract,
          functionName: "allowance",
          args: [account, mFren.contract.address],
        },
        {
          ...spell.contract,
          functionName: "balanceOf",
          args: [mFren.contract.address],
        },
        {
          ...mFren.contract,
          functionName: "userInfo",
          args: [account],
        },
        {
          ...mFren.contract,
          functionName: "pendingReward",
          args: [account],
        },
      ],
    });

  const [userMFrenBalance, _, lastAdded] = mFrenUserInfo.result as bigint[];
  const formatLastAdded = Number(formatUnits(lastAdded, 0));
  const currentTimestamp = moment();
  const lastAddedTimestamp = formatLastAdded
    ? moment.unix(formatLastAdded).add(1, "d")
    : moment.unix(0);
  const isLocked = lastAddedTimestamp.isAfter(currentTimestamp);
  const lockTimestamp = isLocked ? lastAddedTimestamp.unix().toString() : "0";

  return {
    name: mFren.name,
    icon: mFren.icon,
    rateIcon: useImage("assets/images/mspell-icon.svg"),
    decimals: mFren.decimals,
    contract: mFren.contract,
    price: price,
    rate: ONE_ETHER_VIEM,
    lockTimestamp,
    balance: userMFrenBalance,
    approvedAmount: approvedAmount.result as bigint,
    claimableAmount: rewardAmount.result as bigint,
    totalSupply: totalSupply.result as bigint,
  };
};
