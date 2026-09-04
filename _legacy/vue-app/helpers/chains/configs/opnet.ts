import { useImage } from "@/helpers/useImage";
import { OPNET_CHAIN_ID } from "@/constants/global";
import { initPublicClient } from "@/helpers/chains/initPublicClient";
import type { Chain } from "viem";

const viemConfig = {
  id: OPNET_CHAIN_ID,
  name: "OP_NET",
  network: "opnet",
  nativeCurrency: {
    decimals: 8,
    name: "Bitcoin",
    symbol: "BTC",
  },
  rpcUrls: {
    public: {
      http: ["https://node1.opnet.org"],
    },
    default: {
      http: ["https://node1.opnet.org"],
    },
  },
  blockExplorers: {
    default: {
      name: "OP_NET Explorer",
      url: "https://explorer.opnet.org",
    },
  },
} as const satisfies Chain;

const publicClient = initPublicClient(viemConfig);

export const opnetConfig = {
  viemConfig,
  publicClient,
  chainId: OPNET_CHAIN_ID,
  chainName: "OP_NET",
  symbol: "Bitcoin L1",
  icon: useImage("assets/images/networks/opnet.svg"),
  baseTokenIcon: useImage("assets/images/tokens/BTC.png"),
  baseTokenSymbol: "BTC",
  networkIcon: useImage("assets/images/networks/opnet.svg"),
};
