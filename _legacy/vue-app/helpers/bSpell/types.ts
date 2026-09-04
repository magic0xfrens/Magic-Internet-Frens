import type { Address } from "viem";

export type bFrenConfig = {
  spell: {
    name: string;
    decimals: number;
    icon: string;
    contract: {
      address: Address;
      abi: any;
    };
  };
  bFren: {
    name: string;
    decimals: number;
    icon: string;
    contract: {
      address: Address;
      abi: any;
    };
  };
  tokenBank: {
    address: Address;
    abi: any;
  };
  stakeInfo?: {
    address: Address;
    abi: any;
  };
  rewardTokensInfo?: {
    name: string;
    decimals: number;
    icon: string;
    contract: {
      abi: any;
      address: Address;
      addressForPrice?: Address;
    };
  }[];
};

export type bFrenConfigs = {
  [key: number]: bFrenConfig;
};

export type AprInfo = {
  totalApr: number;
  tokensApr: {
    address: Address;
    apr: number;
    price: number;
    icon: string;
    name: string;
  }[];
};

export type RewardTokenInfo = {
  name: string;
  icon: string;
  decimals: number;
  rewardAmount: bigint;
  price: number;
  contract: {
    abi: any;
    address: Address;
    addressForPrice?: Address;
  };
};

export type BFrenInfo = {
  chainId: number;
  spell: {
    name: string;
    decimals: number;
    icon: string;
    contract: {
      address: Address;
      abi: any;
    };
    price: number;
    balance: bigint;
    approvedAmount: bigint;
  };
  bFren: {
    name: string;
    decimals: number;
    icon: string;
    contract: {
      address: Address;
      abi: any;
    };
    price: number;
    balance: bigint;
    approvedAmount: bigint;
    totalSupply: bigint;
  };
  tokenBank: {
    address: Address;
    abi: any;
  };
  lockInfo: {
    lockAmount: bigint;
    claimAmount: bigint;
    userLocks: {
      amount: bigint;
      unlockTime: bigint;
    }[];
    lockDuration: bigint;
    instantRedeemParams: {
      immediateBips: bigint;
      burnBips: bigint;
      feeCollector: Address;
    };
  };
  stakeInfo: {
    contract: {
      address: Address;
      abi: any;
    };
    stakeBalance: bigint;
    approvedAmount: bigint;
    totalSupply: bigint;
    lastAdded: bigint;
    lockupPeriod: bigint;
    unlockTime: number;
  } | null;
  rewardTokensInfo: RewardTokenInfo[] | null;
};

export type TokenPrice = {
  address: Address;
  price: number;
};

export type TabInfo = {
  name: string;
  title: string;
  icon?: string;
};
