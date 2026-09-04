import type { Address } from "viem";

export type FrenInfo = {
  icon: string;
  name: string;
  decimals: number;
  balance: bigint;
  price: bigint;
  contract: {
    address: Address;
    abi: any;
  };
};

export type MFrenInfo = {
  name: string;
  icon: string;
  rateIcon: string;
  decimals: number;
  contract: {
    address: Address;
    abi: any;
  };
  price: bigint;
  rate: bigint;
  lockTimestamp: string;
  balance: bigint;
  approvedAmount: bigint;
  claimableAmount: bigint;
  apr?: string;
  totalSupply: bigint;
};

export type SFrenInfo = {
  name: string;
  icon: string;
  rateIcon: string;
  decimals: number;
  contract: {
    address: Address;
    abi: any;
  };
  price: bigint;
  rate: bigint;
  lockTimestamp: string;
  balance: bigint;
  approvedAmount: bigint;
  apr?: string;
  totalSupply: bigint;
};

export type FrenStakeInfo = {
  chainId: number;
  spell: FrenInfo;
  mFren: MFrenInfo;
  sFren: SFrenInfo;
};
