import { useImage } from "@/helpers/useImage";
import tokensAbi from "@/abis/tokensAbi/index";
import type { ContractInfo } from "@/types/global";

export type FrenStakeConfigs = {
  1: FrenStakeConfig;
  // 250: FrenStakeConfig;
  42161: FrenStakeConfig;
  43114: FrenStakeConfig;
};

export type FrenStakeConfig = {
  spell: FrenConfig;
  sFren?: SFrenConfig;
  mFren: MFrenConfig;
};

export type FrenConfig = {
  name: string;
  decimals: number;
  icon: string;
  abi: any;
};

export type SFrenConfig = {
  name: string;
  decimals: number;
  icon: string;
  contract: ContractInfo;
};

export type MFrenConfig = {
  name: string;
  decimals: number;
  icon: string;
  contract: ContractInfo;
};

export const spellStakeConfig: FrenStakeConfigs = {
  1: {
    spell: {
      name: "FREN",
      decimals: 18,
      icon: useImage("assets/images/tokens/SPELL.png"),
      abi: tokensAbi.FREN,
    },
    sFren: {
      name: "sFREN",
      decimals: 18,
      icon: useImage("assets/images/tokens/sSPELL.png"),
      contract: {
        address: "0x26FA3fFFB6EfE8c1E69103aCb4044C26B9A106a9",
        abi: tokensAbi.sFREN,
      },
    },
    mFren: {
      name: "mFREN",
      decimals: 18,
      icon: useImage("assets/images/tokens/mSPELL.png"),
      contract: {
        address: "0xbD2fBaf2dc95bD78Cf1cD3c5235B33D1165E6797",
        abi: tokensAbi.mFREN,
      },
    },
  },
  // 250: {
  //   spell: {
  //     name: "FREN",
  //     decimals: 18,
  //     icon: useImage("assets/images/tokens/SPELL.png"),
  //     abi: tokensAbi.FREN,
  //   },
  //   mFren: {
  //     name: "mFREN",
  //     decimals: 18,
  //     icon: useImage("assets/images/tokens/mSPELL.png"),
  //     contract: {
  //       address: "0xa668762fb20bcd7148Db1bdb402ec06Eb6DAD569",
  //       abi: tokensAbi.mFREN,
  //     },
  //   },
  // },
  42161: {
    spell: {
      name: "FREN",
      decimals: 18,
      icon: useImage("assets/images/tokens/SPELL.png"),
      abi: tokensAbi.FREN,
    },
    mFren: {
      name: "mFREN",
      decimals: 18,
      icon: useImage("assets/images/tokens/mSPELL.png"),
      contract: {
        address: "0x1DF188958A8674B5177f77667b8D173c3CdD9e51",
        abi: tokensAbi.mFREN,
      },
    },
  },
  43114: {
    spell: {
      name: "FREN",
      decimals: 18,
      icon: useImage("assets/images/tokens/SPELL.png"),
      abi: tokensAbi.FREN,
    },
    mFren: {
      name: "mFREN",
      decimals: 18,
      icon: useImage("assets/images/tokens/mSPELL.png"),
      contract: {
        address: "0xBd84472B31d947314fDFa2ea42460A2727F955Af",
        abi: tokensAbi.mFREN,
      },
    },
  },
};
