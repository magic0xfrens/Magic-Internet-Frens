import moment from "moment";
import { useImage } from "@/helpers/useImage";
import { ONE_ETHER_VIEM } from "@/constants/global";
import { formatUnits, type Address, type PublicClient } from "viem";
import type { FrenStakeConfig } from "@/configs/stake/spellConfig";
import type { SFrenInfo, FrenInfo } from "@/helpers/stake/spell/types";

export const getSFrenInfo = async (
  { sFren }: FrenStakeConfig,
  spell: FrenInfo,
  spellPrice: bigint,
  account: Address,
  publicClient: PublicClient
): Promise<SFrenInfo> => {
  if (!sFren)
    return {
      name: "sFREN",
      icon: useImage("assets/images/tokens/sSPELL.png"),
      rateIcon: useImage("assets/images/sspell-icon.svg"),
      decimals: 18,
      contract: {
        address: "0x26FA3fFFB6EfE8c1E69103aCb4044C26B9A106a9",
        abi: [],
      },
      price: 1n,
      rate: 1n,
      lockTimestamp: "0",
      balance: 0n,
      approvedAmount: 0n,
      totalSupply: 0n,
    };

  const [
    approvedAmount,
    spellSFrenBalance,
    aFrenUserBalance,
    sFrenUserInfo,
    totalSupply,
  ] = await publicClient.multicall({
    contracts: [
      {
        ...spell.contract,
        functionName: "allowance",
        args: [account, sFren.contract.address],
      },
      {
        ...spell.contract,
        functionName: "balanceOf",
        args: [sFren.contract.address],
      },
      {
        ...sFren.contract,
        functionName: "balanceOf",
        args: [account],
      },
      {
        ...sFren.contract,
        functionName: "users",
        args: [account],
      },
      {
        ...sFren.contract,
        functionName: "totalSupply",
        args: [],
      },
    ],
  });

  const spellToSFrenRate =
    ((spellSFrenBalance.result as bigint) * ONE_ETHER_VIEM) /
    (totalSupply.result as bigint);

  const sFrenPrice = (spellPrice * spellToSFrenRate) / ONE_ETHER_VIEM;

  const currentTimestamp = moment();
  const [_, lockedUntil] = sFrenUserInfo.result as bigint[];
  const formatLockedUntil = +formatUnits(lockedUntil, 0);
  const lockedUntilTimestamp = formatLockedUntil
    ? moment.unix(formatLockedUntil)
    : moment.unix(0);

  const isLocked = lockedUntilTimestamp.isAfter(currentTimestamp);
  const lockTimestamp = isLocked ? lockedUntilTimestamp.unix().toString() : "0";

  return {
    name: sFren.name,
    icon: sFren.icon,
    rateIcon: useImage("assets/images/sspell-icon.svg"),
    decimals: sFren.decimals,
    contract: sFren.contract,
    price: sFrenPrice,
    rate: spellToSFrenRate,
    lockTimestamp,
    balance: aFrenUserBalance.result as bigint,
    approvedAmount: approvedAmount.result as bigint,
    totalSupply: totalSupply.result as bigint,
  };
};
