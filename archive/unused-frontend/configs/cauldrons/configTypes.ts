type CauldronSettings = {
  isSwappersActive: boolean;
  is0xSwap?: boolean;
  isOpenocean?: boolean;
  isDegenBox: boolean;
  strategyLink: boolean | string;
  isDepreciated: boolean;
  acceptUseDefaultBalance: boolean;
  healthMultiplier: number;
  hasAccountBorrowLimit: boolean;
  hasWithdrawableLimit: boolean;
  localBorrowAmountLimit: boolean;
  hasCrvClaimLogic: boolean;
  isNew?: boolean;
  executionPrice?: boolean;
  isMigrated?: boolean;
  oracleAddress?: string;
  isPrivate?: boolean;
  privatelyFor?: string[];
  isAlternativeInterest?: boolean;
  isMagicApe?: boolean;
  isSFren?: boolean;
  isGMXMarket?: boolean;
  isMimUsdtCurveLp?: boolean;
  isStargateUSDT?: boolean;
  isVelodrome?: boolean;
  isTesting?: boolean;
  hasWhitelistLogic?: boolean;
  useDegenBoxHelper?: boolean;
  isYvWethV2?: boolean;
  isCvxTricrypto?: boolean;
  isCvx3pool?: boolean;
  isMagicGLP?: boolean;
  iStdeUSD?: boolean;
  isNoDeleverage?: boolean;
  hasElixirPotions?: boolean;
  isUSD0?: boolean;
  isAprExist?: boolean;
  isBeraDesign?: boolean;
  weight?: number;
};

type MimInfo = {
  name: string;
  icon: string;
  decimals: number;
  address: string;
  abi: unknown;
};

export type CauldronConfig = {
  icon: string;
  name: string;
  chainId: number;
  id: number;
  liquidationFee: number;
  interest?: number;
  mcr: number;
  borrowFee: number;
  version: number;
  cauldronSettings: CauldronSettings;
  contract: {
    name: string;
    address: string;
    abi: unknown;
  };
  collateralInfo: {
    name: string;
    decimals: number;
    address: string;
    abi: unknown;
  };
  mimInfo: MimInfo;
  wrapInfo?: {
    isHiddenWrap: boolean;
    useUnwrappedByDefault: boolean;
    unwrappedToken: {
      name: string;
      icon: string;
      address: string;
      abi: unknown;
    };
    wrapper: {
      address: string;
      abi: unknown;
    };
  };
  leverageInfo?: {
    address: string;
    abi: unknown;
  };
  deleverageInfo?: {
    address: string;
    abi: unknown;
  };
};
