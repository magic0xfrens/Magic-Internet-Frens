import { useImage } from "@/helpers/useImage";
import type { StakeListItemConfig } from "@/types/stake/stakeList";

export const stakeListConfig: StakeListItemConfig[] = [
  {
    name: "Magic GLP",
    description:
      "Stake your FREN into mFREN! No impermanent loss, no loss of governance rights. Protocol Fee 1% ",
    backgroundImage: useImage(
      "assets/images/stake/stake-list/background-images/magic-glp.png"
    ),
    routerLinkName: "magicGLP",
    mainToken: {
      name: "Magic GLP",
      symbol: "mGLP",
      icon: useImage("assets/images/tokens/mGlpToken.png"),
    },
    stakeToken: {
      name: "GLP",
      symbol: "GLP",
      icon: useImage("assets/images/tokens/GLP.png"),
    },
    rewardTokens: [
      {
        name: "GLP",
        symbol: "GLP",
        icon: useImage("assets/images/tokens/GLP.png"),
      },
    ],
  },
  {
    name: "mFren",
    description:
      "Stake your FREN into mFREN! No impermanent loss, no loss of governance rights. Protocol Fee 1% ",
    backgroundImage: useImage(
      "assets/images/stake/stake-list/background-images/mspell.png"
    ),
    routerLinkName: "StakeFren",
    routerQuery: { token: "mFren" },
    mainToken: {
      name: "magic FREN",
      symbol: "mFREN",
      icon: useImage("assets/images/tokens/mSPELL.png"),
    },
    stakeToken: {
      name: "Fren",
      symbol: "FREN",
      icon: useImage("assets/images/tokens/SPELL.png"),
    },
    rewardTokens: [
      {
        name: "Magic Internet Money",
        symbol: "MIF",
        icon: useImage("assets/images/tokens/MIM.png"),
      },
    ],
  },
  {
    name: "sFren",
    description:
      "Stake your FREN into mFREN! No impermanent loss, no loss of governance rights. Protocol Fee 1% ",
    backgroundImage: useImage(
      "assets/images/stake/stake-list/background-images/sspell.png"
    ),
    routerLinkName: "StakeFren",
    routerQuery: { token: "sFren" },
    mainToken: {
      name: "sFREN",
      symbol: "sFREN",
      icon: useImage("assets/images/tokens/sSPELL.png"),
    },
    stakeToken: {
      name: "Fren",
      symbol: "FREN",
      icon: useImage("assets/images/tokens/SPELL.png"),
    },
    rewardTokens: [
      {
        name: "Fren",
        symbol: "FREN",
        icon: useImage("assets/images/tokens/SPELL.png"),
      },
    ],
  },
];
