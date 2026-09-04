<template>
  <div class="wrapper" v-if="bFrenInfo">
    <div class="action-form">
      <TabsBlock
        :tabsInfo="tabsInfo"
        :activeTab="activeTab"
        @changeActiveTab="changeActiveTab"
      />

      <MintForm
        v-if="activeTab === 'MintForm'"
        :bFrenInfo="bFrenInfo"
        :selectedNetwork="selectedNetwork"
        @updateBFrenInfo="$emit('updateBFrenInfo')"
      />

      <RedeemForm
        v-else
        :bFrenInfo="bFrenInfo"
        :selectedNetwork="selectedNetwork"
        @updateBFrenInfo="$emit('updateBFrenInfo')"
      />
    </div>

    <div class="info-wrap">
      <ClaimBlock
        :bFrenInfo="bFrenInfo"
        :selectedNetwork="selectedNetwork"
        @updateBFrenInfo="$emit('updateBFrenInfo')"
      />

      <SpellLockTable :bFrenInfo="bFrenInfo" />
    </div>
  </div>
</template>

<script lang="ts">
import { mapGetters } from "vuex";
import type { BFrenInfo } from "@/helpers/bSpell/types";
import { defineAsyncComponent, type PropType } from "vue";

export default {
  emits: ["updateBFrenInfo", "changeNetwork"],

  props: {
    selectedNetwork: {
      type: Number,
      required: true,
    },

    availableNetworks: {
      type: Array as () => number[],
      required: true,
    },

    bFrenInfo: {
      type: Object as PropType<BFrenInfo | null>,
      required: true,
    },
  },

  data() {
    return {
      activeTab: "MintForm",
      tabsInfo: [
        {
          name: "MintForm",
          title: "Get bFren",
        },
        {
          name: "RedeemForm",
          title: "Redeem",
        },
      ],
    };
  },

  computed: {
    ...mapGetters({ account: "getAccount" }),
  },

  methods: {
    changeActiveTab(tabName: string) {
      this.activeTab = tabName;
    },
  },

  components: {
    TabsBlock: defineAsyncComponent(
      () => import("@/components/bSpell/TabsBlock.vue")
    ),
    MintForm: defineAsyncComponent(
      () => import("@/components/bSpell/MintForm.vue")
    ),
    RedeemForm: defineAsyncComponent(
      () => import("@/components/bSpell/RedeemForm.vue")
    ),
    ClaimBlock: defineAsyncComponent(
      () => import("@/components/bSpell/ClaimBlock.vue")
    ),
    SpellLockTable: defineAsyncComponent(
      () => import("@/components/bSpell/SpellLockTable.vue")
    ),
  },
};
</script>

<style lang="scss" scoped>
.wrapper {
  display: grid;
  grid-template-columns: 524px 1fr;
  grid-gap: 24px;
}

.action-form {
  gap: 16px;
  display: flex;
  flex-direction: column;
  padding: 24px;
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

.info-wrap {
  gap: 24px;
  display: flex;
  flex-direction: column;
}

@media screen and (max-width: 1024px) {
  .wrapper {
    grid-template-columns: 1fr;
    grid-gap: 16px;
  }

  .action-form {
    padding: 16px;
  }

  .info-wrap {
    gap: 16px;
  }
}
</style>
