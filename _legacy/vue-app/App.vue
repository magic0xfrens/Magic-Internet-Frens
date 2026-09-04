<template>
  <LandingHeader v-if="isLandingPage" />
  <AppHeader v-else />
  <Landing v-if="isLandingPage" />
  <div v-else class="router-wrap">
    <img
      class="mim-top-bg"
      src="@/assets/images/mif/wizard.png"
      alt="MIF Wizard"
      style="opacity: 0.06; max-width: 300px;"
    />
    <img
      class="mim-bottom-bg"
      src="@/assets/images/mif/cauldron.webp"
      alt="MIF Cauldron"
      style="opacity: 0.06; max-width: 250px;"
    />
    <MlpMigrationBanner />
    <router-view />
  </div>
  <NotificationContainer />
  <PopupsWrapper />
  <SkullBanner v-if="!isLandingPage" />
  <OldAllowanceBanner v-if="!isLandingPage" />
  <TenderlyMod v-if="!isLandingPage" />
</template>

<script>
import { defineAsyncComponent } from "vue";
import { useAnimation } from "@/helpers/useAnimation/useAnimation";
import { checkLocation } from "@/helpers/useLocation";

export default {
  data() {
    return {};
  },

  computed: {
    isLandingPage() {
      return this.$route.meta?.isLanding === true;
    },
  },

  methods: {
    ...useAnimation("fade"),
  },

  async beforeCreate() {
    // Location check disabled for development
  },

  components: {
    AppHeader: defineAsyncComponent(() =>
      import("@/components/app/AppHeader.vue")
    ),
    LandingHeader: defineAsyncComponent(() =>
      import("@/components/landing/LandingHeader.vue")
    ),
    Landing: defineAsyncComponent(() =>
      import("@/views/Landing.vue")
    ),
    NotificationContainer: defineAsyncComponent(() =>
      import("@/components/notifications/NotificationContainer.vue")
    ),
    PopupsWrapper: defineAsyncComponent(() =>
      import("@/components/popups/PopupsWrapper.vue")
    ),
    MlpMigrationBanner: defineAsyncComponent(() =>
      import("@/components/ui/MlpMigrationBanner.vue")
    ),
    SkullBanner: defineAsyncComponent(() =>
      import("@/components/ui/SkullBanner.vue")
    ),
    OldAllowanceBanner: defineAsyncComponent(() =>
      import("@/components/ui/OldAllowanceBanner.vue")
    ),
    TenderlyMod: defineAsyncComponent(() =>
      import("@/components/tenderly/TenderlyMod.vue")
    ),
  },
};
</script>

<style lang="scss" src="@/assets/styles/main.scss"></style>
