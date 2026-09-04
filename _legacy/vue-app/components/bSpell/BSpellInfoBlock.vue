<template>
  <div class="bspell-info-block">
    <img class="mim-icon" src="@/assets/images/bFren/mim-left-bg.png" alt="" />

    <div class="info">
      <p class="info-title">bFren In Curculation</p>

      <p class="info-text">
        <img
          class="info-icon"
          src="@/assets/images/tokens/bSPELL.png"
          alt="bFREN icon"
        />
        <span>
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

        <span>
          {{ totalStaked }}
        </span>
      </p>
    </div>
  </div>
</template>

<script lang="ts">
import { formatUnits } from "viem";
import type { PropType } from "vue";
import { formatLargeSum } from "@/helpers/filters";
import type { BFrenInfo } from "@/helpers/bSpell/types";

export default {
  props: {
    bFrenInfo: {
      type: Object as PropType<BFrenInfo | null>,
      required: true,
    },
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
};
</script>

<style scoped>
.bspell-info-block {
  gap: 8px;
  display: none;
  flex-direction: column;
  padding: 12px;
  position: relative;
  border-radius: 16px;
  border: 1px solid rgba(247, 147, 26, 0.15);
  background: linear-gradient(
    146deg,
    rgba(0, 10, 35, 0.07) 0%,
    rgba(0, 80, 156, 0.07) 101.49%
  );
  box-shadow: 0px 4px 32px 0px rgba(103, 103, 103, 0.14);
  backdrop-filter: blur(12.5px);
}

.mim-icon {
  max-width: 60px;
  width: 100%;
  position: absolute;
  top: 16px;
  left: 0;
}

.info {
  min-width: 140px;
}

.info-title {
  color: #878b93;
  font-size: 14px;
  font-weight: 500;
  line-height: normal;
  display: flex;
  text-align: center;
  justify-content: center;
}

.info-text {
  font-size: 24px;
  font-weight: 500;
  gap: 6px;
  display: flex;
  align-items: center;
  justify-content: center;
  line-height: 150%;
}

.info-icon {
  width: 24px;
  height: 24px;
}

.line {
  height: 1px;
  width: 100%;
  background: linear-gradient(
    90deg,
    rgba(255, 255, 255, 0) 0%,
    rgba(255, 255, 255, 0.2) 46.5%,
    rgba(255, 255, 255, 0) 100%
  );
}

@media screen and (max-width: 1024px) {
  .bspell-info-block {
    display: flex;
  }
}
</style>
