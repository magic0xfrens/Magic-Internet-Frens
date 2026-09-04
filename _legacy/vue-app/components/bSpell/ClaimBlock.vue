<template>
  <div class="claim-block" v-if="bFrenInfo">
    <img
      class="spell-left"
      src="@/assets/images/bFren/claim-spell-left.png"
      alt="Fren icon"
    />

    <div class="claim-wrap">
      <h3 class="claim-title">Fren to Claim</h3>
      <div class="action-wrap">
        <div class="claim-info">
          <img
            class="claim-token-icon"
            src="@/assets/images/tokens/SPELL.png"
            alt=""
          />
          <div class="claim-amounts">
            <span class="claim-amount">{{
              formatTokenBalance(claimAmount)
            }}</span>
            <span class="claim-amount-usd">{{ claimAmountUsd }}</span>
          </div>
        </div>

        <BaseButton primary :disabled="isClaimDisabled" @click="actionHandler">
          {{ claimButtonText }}
        </BaseButton>
      </div>
    </div>

    <img
      class="spell-right"
      src="@/assets/images/bFren/claim-spell-right.png"
      alt="Fren icon"
    />
  </div>
</template>

<script lang="ts">
import { formatUnits } from "viem";
import type { PropType } from "vue";
import { defineAsyncComponent } from "vue";
import { claim } from "@/helpers/bSpell/actions/claim";
import type { BFrenInfo } from "@/helpers/bSpell/types";
import { mapActions, mapGetters, mapMutations } from "vuex";
import notification from "@/helpers/notification/notification";
import ErrorHandler from "@/helpers/errorHandler/ErrorHandler";
import { formatTokenBalance, formatUSD } from "@/helpers/filters";
import { switchNetwork } from "@/helpers/chains/switchNetwork";
import { openConnectPopup } from "@/helpers/connect/utils";

export default {
  emits: ["updateBFrenInfo"],

  props: {
    bFrenInfo: {
      type: Object as PropType<BFrenInfo | null>,
      required: true,
    },

    selectedNetwork: {
      type: Number,
      required: true,
    },
  },

  computed: {
    ...mapGetters({ account: "getAccount", chainId: "getChainId" }),

    isUnsupportedChain() {
      return this.chainId === this.selectedNetwork;
    },

    claimButtonText() {
      if (!this.account) return "Connect Wallet";
      if (!this.isUnsupportedChain) return "Switch Network";
      return "Claim";
    },

    claimAmount() {
      if (!this.bFrenInfo) return 0;

      const { decimals } = this.bFrenInfo.spell;
      return formatUnits(
        this.bFrenInfo?.lockInfo?.claimAmount || 0n,
        decimals
      );
    },

    claimAmountUsd() {
      if (!this.bFrenInfo) return 0;
      return formatUSD(Number(this.claimAmount) * this.bFrenInfo.spell.price);
    },

    isClaimDisabled() {
      return !Number(this.claimAmount) && this.account;
    },
  },

  methods: {
    formatTokenBalance,
    ...mapActions({ createNotification: "notifications/new" }),
    ...mapMutations({
      deleteNotification: "notifications/delete",
    }),

    async actionHandler() {
      if (!this.account && this.isUnsupportedChain) return openConnectPopup();

      if (!this.isUnsupportedChain) return switchNetwork(this.selectedNetwork);
      await this.claimHandler();
    },

    async claimHandler() {
      try {
        const notificationId = await this.createNotification(
          notification.pending
        );

        await claim(this.bFrenInfo!.tokenBank);
        this.$emit("updateBFrenInfo");
        await this.deleteNotification(notificationId);
        await this.createNotification(notification.success);
      } catch (error) {
        ErrorHandler.handleError(error as Error);
      }
    },
  },

  components: {
    BaseButton: defineAsyncComponent(
      () => import("@/components/base/BaseButton.vue")
    ),
  },
};
</script>

<style scoped>
.claim-block {
  position: relative;
  overflow: hidden;
  display: flex;
  align-items: center;
  justify-content: center;
  height: 108px;
  border-radius: 16px;
  border: 1px #F7931A;
  background: linear-gradient(
      90deg,
      rgba(45, 74, 150, 0.32) 0%,
      rgba(116, 92, 210, 0.32) 100%
    ),
    linear-gradient(
      146deg,
      rgba(0, 10, 35, 0.07) 0%,
      rgba(0, 80, 156, 0.07) 101.49%
    );
  box-shadow: 0px 4px 32px 0px rgba(103, 103, 103, 0.14);
  backdrop-filter: blur(12.5px);
}

.spell-left,
.spell-right {
  max-width: 200px;
  width: 100%;
  position: absolute;
  top: 0;
  left: 0;
}

.spell-right {
  left: initial;
  right: 0;
}

.claim-wrap {
  z-index: 1;
}

.claim-title {
  font-size: 18px;
  font-weight: 500;
  margin-bottom: 10px;
  text-align: center;
}

.action-wrap,
.claim-info {
  gap: 14px;
  display: flex;
  align-items: center;
}

.claim-info {
  gap: 8px;
}

.claim-token-icon {
  width: 40px;
  height: 40px;
}

.claim-amounts {
  display: flex;
  flex-direction: column;
  min-width: 40px;
}

.claim-amount {
  font-size: 24px;
  font-weight: 500;
}

.claim-amount-usd {
  color: #878b93;
  font-size: 16px;
  font-weight: 500;
}

@media (max-width: 600px) {
  .spell-left,
  .spell-right {
    max-width: 160px;
  }

  .spell-left {
    left: -60px;
  }

  .spell-right {
    right: -60px;
  }

  .claim-title {
    font-size: 16px;
  }

  .claim-token-icon {
    width: 34px;
    height: 34px;
  }

  .claim-amount {
    font-size: 20px;
  }

  .claim-amount-usd {
    font-size: 14px;
  }
}
</style>
