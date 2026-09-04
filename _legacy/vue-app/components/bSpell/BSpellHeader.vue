<template>
  <div class="content-header">
    <div class="left-block">
      <div class="tabs-wrap">
        <button
          :class="['tab-btn', { 'tab-btn-active': activeTab === tabInfo.name }]"
          v-for="tabInfo in tabsInfo"
          :key="tabInfo.name"
          @click="changeActiveTab(tabInfo.name)"
        >
          <img
            class="tab-icon"
            v-if="tabInfo.icon"
            :src="tabInfo.icon"
            alt="bFREN icon"
          />

          {{ tabInfo.title }}
        </button>
      </div>

      <p class="header-title">
        Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod

        <a
          class="header-link"
          href="http://"
          target="_blank"
          rel="noopener noreferrer"
          >tempor</a
        >
      </p>
    </div>

    <div class="right-block">
      <div class="info">
        <p class="info-title">bFren In Curculation</p>

        <p class="info-text">
          <img
            class="info-icon"
            src="@/assets/images/tokens/bSPELL.png"
            alt="bFREN icon"
          />
          <RowSkeleton v-if="!bFrenInfo" height="32px" />
          <span v-else>
            {{ bFrenCurculation }}
          </span>
        </p>
      </div>
      <div class="line"></div>
      <div class="info">
        <p class="info-title">Staked</p>
        <p class="info-text">
          <img
            class="info-icon"
            src="@/assets/images/tokens/bSPELL.png"
            alt="bFREN icon"
          />

          <RowSkeleton v-if="!bFrenInfo" height="32px" />
          <span v-else>
            {{ totalStaked }}
          </span>
        </p>
      </div>
    </div>
  </div>
</template>

<script lang="ts">
import { formatUnits } from "viem";
import { useImage } from "@/helpers/useImage";
import { formatLargeSum } from "@/helpers/filters";
import type { BFrenInfo } from "@/helpers/bSpell/types";
import { defineAsyncComponent, type PropType } from "vue";

export default {
  emits: ["changeActiveTab"],

  props: {
    bFrenInfo: {
      type: Object as PropType<BFrenInfo | null>,
      required: true,
    },
  },

  data() {
    return {
      activeTab: "BSpellBlock",
      tabsInfo: [
        {
          name: "BSpellBlock",
          icon: useImage("assets/images/tokens/bSPELL.png"),
          title: "bFren",
        },
        {
          name: "SpellPowerBlock",
          icon: "",
          title: "Fren Power",
        },
      ],
    };
  },

  computed: {
    bFrenCurculation() {
      if (!this.bFrenInfo) return formatLargeSum(0);
      return formatLargeSum(
        formatUnits(this.bFrenInfo.bFren.totalSupply, 18)
      );
    },

    totalStaked() {
      if (!this.bFrenInfo || !this.bFrenInfo.stakeInfo)
        return formatLargeSum(0);

      return formatLargeSum(
        formatUnits(this.bFrenInfo.stakeInfo.totalSupply, 18)
      );
    },
  },

  methods: {
    changeActiveTab(tabName: string) {
      this.activeTab = tabName;
      this.$emit("changeActiveTab", tabName);
    },
  },

  components: {
    RowSkeleton: defineAsyncComponent(
      () => import("@/components/ui/skeletons/RowSkeleton.vue")
    ),
  },
};
</script>

<style lang="scss" scoped>
.content-header {
  z-index: 1;
  display: flex;
  justify-content: space-between;
}

.left-block {
  gap: 12px;
  display: flex;
  flex-direction: column;
}

.tabs-wrap {
  display: flex;
  align-items: center;
}

.tab-btn {
  max-width: 189px;
  width: 100%;
  height: 52px;
  border: transparent;
  outline: transparent;
  border-radius: 36px;
  cursor: pointer;
  background: transparent;
  gap: 8px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 20px;
  font-weight: 600;
  line-height: 150%;
  color: #fff;
}

.tab-btn-active {
  background: linear-gradient(
    90deg,
    rgba(45, 74, 150, 0.24) 0%,
    rgba(116, 92, 210, 0.24) 100%
  );
}

.tab-icon {
  width: 32px;
  height: 32px;
}

.header-title,
.header-link {
  font-size: 16px;
  font-weight: 400;
  line-height: 110%;
  color: #ffffff99;
}

.header-link {
  color: #F7931A;
  text-decoration: underline #F7931A;
}

.right-block {
  border-radius: 16px;
  border: 1px solid rgba(247, 147, 26, 0.15);
  background: linear-gradient(
    146deg,
    rgba(0, 10, 35, 0.07) 0%,
    rgba(0, 80, 156, 0.07) 101.49%
  );
  box-shadow: 0px 4px 32px 0px rgba(103, 103, 103, 0.14);
  backdrop-filter: blur(12.5px);
  padding: 12px 24px;
  gap: 20px;
  display: flex;
  align-items: center;
}

.line {
  height: 100%;
  width: 1px;
  background: linear-gradient(
    90deg,
    rgba(255, 255, 255, 0) 0%,
    rgba(255, 255, 255, 0.2) 46.5%,
    rgba(255, 255, 255, 0) 100%
  );
}

.info {
  min-width: 140px;
}

.info-title {
  color: #878b93;
  font-weight: 500;
  display: flex;
  justify-content: center;
}

.info-text {
  height: 42px;
  font-size: 28px;
  font-weight: 500;
  gap: 6px;
  display: flex;
  align-items: center;
  line-height: 150%;
}

.info-icon {
  width: 24px;
  height: 24px;
}

@media screen and (max-width: 1024px) {
  .right-block {
    display: none;
  }
}

@media (max-width: 600px) {
  .content-header {
    flex-direction: column;
  }

  .left-block {
    gap: 16px;
  }

  .header-title {
    color: rgba(255, 255, 255, 0.6);
    font-size: 14px;
    font-weight: 400;
    line-height: normal;
  }

  .tab-btn {
    max-width: 100%;
    height: 43px;
    font-size: 18px;
    line-height: normal;
  }

  .tab-icon {
    width: 24px;
    height: 24px;
  }
}
</style>
