<template>
  <HeaderLink to="Cauldrons">Cauldrons</HeaderLink>

  <HeaderLink to="StakeFren">Staking</HeaderLink>

  <HeaderLink to="Swap">Swap</HeaderLink>

  <HeaderLink to="NFT">NFT</HeaderLink>

  <HeaderLink to="MyPositions">My Positions</HeaderLink>
</template>

<script>
import { defineAsyncComponent } from "vue";

export default {
  components: {
    HeaderLink: defineAsyncComponent(() =>
      import("@/components/ui/links/HeaderLink.vue")
    ),
  },
};
</script>

<style lang="scss" scoped></style>
