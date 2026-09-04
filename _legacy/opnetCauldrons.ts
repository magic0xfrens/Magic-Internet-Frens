import poolsAbi from "@/abis/borrowPoolsAbi/index";
import tokensAbi from "@/abis/tokensAbi/index";
import { OPNET_CHAIN_ID } from "@/constants/global";

import type { CauldronConfig } from "@/configs/cauldrons/configTypes";

/** Resolve asset path relative to project root (Vite handles these at build time). */
function tokenIcon(filename: string): string {
  return new URL(`../../assets/images/tokens/${filename}`, import.meta.url).href;
}

const mimInfo = {
  name: "MIF",
  icon: tokenIcon("MIM.png"),
  decimals: 18,
  address: "0xOP00000000000000000000000000000000000MIF",
  abi: tokensAbi.MIM,
};

const config: Array<CauldronConfig> = [
  {
    icon: tokenIcon("BTC.png"),
    name: "BTC",
    chainId: OPNET_CHAIN_ID,
    id: 1,
    liquidationFee: 5,
    interest: 3,
    mcr: 80,
    borrowFee: 0.5,
    version: 4,
    cauldronSettings: {
      isSwappersActive: false,
      isDegenBox: true,
      strategyLink: false,
      isDepreciated: false,
      acceptUseDefaultBalance: true,
      healthMultiplier: 1,
      hasAccountBorrowLimit: false,
      hasWithdrawableLimit: false,
      localBorrowAmountLimit: false,
      hasCrvClaimLogic: false,
      isNew: true,
      weight: 10,
    },
    contract: {
      name: "CauldronV4",
      address: "0xOP00000000000000000000000000CauldronBTC01",
      abi: poolsAbi.CauldronV4,
    },
    collateralInfo: {
      name: "BTC",
      decimals: 8,
      address: "0xOP0000000000000000000000000000000000000BTC",
      abi: tokensAbi.OP20,
    },
    mimInfo,
  },
  {
    icon: tokenIcon("MOTO.svg"),
    name: "MOTO",
    chainId: OPNET_CHAIN_ID,
    id: 2,
    liquidationFee: 10,
    interest: 5,
    mcr: 70,
    borrowFee: 1,
    version: 4,
    cauldronSettings: {
      isSwappersActive: false,
      isDegenBox: true,
      strategyLink: false,
      isDepreciated: false,
      acceptUseDefaultBalance: false,
      healthMultiplier: 1,
      hasAccountBorrowLimit: false,
      hasWithdrawableLimit: false,
      localBorrowAmountLimit: false,
      hasCrvClaimLogic: false,
      isNew: true,
      weight: 8,
    },
    contract: {
      name: "CauldronV4",
      address: "0xOP0000000000000000000000000CauldronMOTO02",
      abi: poolsAbi.CauldronV4,
    },
    collateralInfo: {
      name: "MOTO",
      decimals: 18,
      address: "0xOP000000000000000000000000000000000MOTO",
      abi: tokensAbi.OP20,
    },
    mimInfo,
  },
  {
    icon: tokenIcon("PILL.svg"),
    name: "PILL",
    chainId: OPNET_CHAIN_ID,
    id: 3,
    liquidationFee: 10,
    interest: 5,
    mcr: 70,
    borrowFee: 1,
    version: 4,
    cauldronSettings: {
      isSwappersActive: false,
      isDegenBox: true,
      strategyLink: false,
      isDepreciated: false,
      acceptUseDefaultBalance: false,
      healthMultiplier: 1,
      hasAccountBorrowLimit: false,
      hasWithdrawableLimit: false,
      localBorrowAmountLimit: false,
      hasCrvClaimLogic: false,
      isNew: true,
      weight: 7,
    },
    contract: {
      name: "CauldronV4",
      address: "0xOP0000000000000000000000000CauldronPILL03",
      abi: poolsAbi.CauldronV4,
    },
    collateralInfo: {
      name: "PILL",
      decimals: 18,
      address: "0xOP000000000000000000000000000000000PILL",
      abi: tokensAbi.OP20,
    },
    mimInfo,
  },
];

export default config;
