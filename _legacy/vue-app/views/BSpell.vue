<template>
  <div class="page-view">
    <div class="content-wrap" v-if="bFrenInfo">
      <BSpellHeader
        :bFrenInfo="bFrenInfo"
        @changeActiveTab="changeActiveTab"
      />

      <TransitionWrapper appear v-if="activeTab === 'BSpellBlock'">
        <BSpellBlock
          :bFrenInfo="bFrenInfo"
          :selectedNetwork="selectedNetwork"
          :availableNetworks="availableNetworks"
          @changeNetwork="changeActiveNetwork"
          @updateBFrenInfo="createOrUpdateInfo"
        />
      </TransitionWrapper>

      <TransitionWrapper appear v-else>
        <SpellPowerBlock
          :aprInfo="aprInfo"
          :bFrenInfo="bFrenInfo"
          :selectedNetwork="selectedNetwork"
          :availableNetworks="availableNetworks"
          @changeNetwork="changeActiveNetwork"
          @updateBFrenInfo="createOrUpdateInfo"
        />
      </TransitionWrapper>

      <BSpellInfoBlock :bFrenInfo="bFrenInfo" />
    </div>

    <div class="loader-wrap" v-else>
      <BaseLoader large text="Loading stake" />
    </div>
  </div>
</template>

<script lang="ts">
import { defineAsyncComponent } from "vue";
import { mapGetters, mapMutations } from "vuex";
import type { AprInfo } from "@/helpers/bSpell/types";
import { ARBITRUM_CHAIN_ID } from "@/constants/global";
import { dataRefresher } from "@/helpers/dataRefresher";
import type { RefresherInfo } from "@/helpers/dataRefresher";
import type { BFrenInfo } from "@/helpers/bSpell/types";
import { getBFrenInfo } from "@/helpers/bSpell/getLockInfo";
import { getBFrenApr } from "@/helpers/bSpell/getBFrenAPR";
import ErrorHandler from "@/helpers/errorHandler/ErrorHandler";

export default {
  data() {
    return {
      activeTab: "BSpellBlock",
      bFrenInfoArr: [] as BFrenInfo[] | null,
      refresherInfo: {
        refresher: null as unknown as dataRefresher<BFrenInfo[]>,
        remainingTime: 0,
        isLoading: false,
        intervalTime: 60,
      } as RefresherInfo<BFrenInfo[]>,
      selectedNetwork: ARBITRUM_CHAIN_ID,
      availableNetworks: [ARBITRUM_CHAIN_ID],
      aprInfo: null as AprInfo | null,
    };
  },

  computed: {
    ...mapGetters({
      account: "getAccount",
      chainId: "getChainId",
      localStakeData: "getBFrenData",
    }),

    bFrenInfo() {
      if (!this.bFrenInfoArr) return null;

      const bFrenInfo = this.bFrenInfoArr.find(
        (info: BFrenInfo) => info.chainId === +this.selectedNetwork
      );

      if (!bFrenInfo) return null;
      return bFrenInfo;
    },
  },

  watch: {
    async account() {
      await this.createOrUpdateInfo();
    },

    async chainId() {
      await this.createOrUpdateInfo();
    },

    async selectedNetwork() {
      await this.createOrUpdateInfo();
    },

    bFrenInfo: {
      handler() {
        this.getAprInfo();
      },
      deep: true,
    },

    bFrenInfoArr: {
      handler() {
        if (this.bFrenInfoArr) this.setBFrenStakeData(this.bFrenInfoArr);
      },
      deep: true,
    },
  },

  methods: {
    ...mapMutations({
      setBFrenStakeData: "setBFrenStakeData",
    }),

    changeActiveTab(tabName: string) {
      this.activeTab = tabName;
    },

    changeActiveNetwork(chainId: number) {
      this.selectedNetwork = chainId;
    },

    async createBFrenInfo() {
      return await getBFrenInfo(this.account);
    },

    async createOrUpdateInfo() {
      const refresher = this.refresherInfo?.refresher;
      try {
        if (!refresher) {
          this.createDataRefresher();
          this.refresherInfo.refresher.start();
        } else {
          refresher.manualUpdate();
        }
      } catch (error) {
        console.error("Error creating or updating BFren info:", error);
      }
    },

    createDataRefresher() {
      this.refresherInfo.refresher = new dataRefresher(
        this.createBFrenInfo,
        this.refresherInfo.intervalTime,
        (time) => (this.refresherInfo.remainingTime = time),
        (loading) => (this.refresherInfo.isLoading = loading),
        (updatedData: BFrenInfo[] | null) => (this.bFrenInfoArr = updatedData)
      );
    },

    checkLocalData() {
      if (this.localStakeData.isCreated && this.account) {
        this.bFrenInfoArr = this.localStakeData.data;
      }
    },

    emptyArpInfo() {
      if (!this.bFrenInfo || !this.bFrenInfo.rewardTokensInfo)
        return { totalApr: 0, tokensApr: [] };

      const tokensApr = this.bFrenInfo.rewardTokensInfo.map((tokenInfo) => {
        return {
          address: tokenInfo.contract.address,
          price: tokenInfo.price,
          apr: 0,
          icon: tokenInfo.icon,
          name: tokenInfo.name,
        };
      });

      this.aprInfo = { totalApr: 0, tokensApr };
    },

    async getAprInfo() {
      try {
        if (
          !this.bFrenInfo ||
          !this.bFrenInfo.stakeInfo ||
          !this.bFrenInfo.rewardTokensInfo
        ) {
          this.emptyArpInfo();
        } else {
          this.aprInfo = await getBFrenApr(
            this.selectedNetwork,
            this.bFrenInfo.rewardTokensInfo,
            this.bFrenInfo.stakeInfo.totalSupply,
            this.bFrenInfo.stakeInfo.contract,
            this.bFrenInfo.spell.price
          );
        }
      } catch (error) {
        ErrorHandler.handleError(error as Error);
        this.emptyArpInfo();
      }
    },
  },

  async created() {
    this.checkLocalData();
    await this.createOrUpdateInfo();
  },

  beforeUnmount() {
    this.refresherInfo.refresher.stop();
  },

  components: {
    BSpellHeader: defineAsyncComponent(
      () => import("@/components/bSpell/BSpellHeader.vue")
    ),
    BSpellBlock: defineAsyncComponent(
      () => import("@/components/bSpell/BSpellBlock.vue")
    ),
    SpellPowerBlock: defineAsyncComponent(
      () => import("@/components/bSpell/SpellPowerBlock.vue")
    ),
    TransitionWrapper: defineAsyncComponent(
      () => import("@/components/ui/TransitionWrapper.vue")
    ),
    BSpellInfoBlock: defineAsyncComponent(
      () => import("@/components/bSpell/BSpellInfoBlock.vue")
    ),
    BaseLoader: defineAsyncComponent(
      () => import("@/components/base/BaseLoader.vue")
    ),
  },
};
</script>

<style lang="scss" scoped>
.page-view {
  min-height: 100vh;
}

.content-wrap {
  max-width: 1310px;
  width: 100%;
  padding: 124px 15px 90px;
  margin: 0 auto;
  position: relative;
  gap: 24px;
  display: flex;
  flex-direction: column;
}

.loader-wrap {
  display: flex;
  align-items: center;
  justify-content: center;
  height: 100vh;
}

@media screen and (max-width: 600px) {
  .content-wrap {
    gap: 16px;
  }
}
</style>
