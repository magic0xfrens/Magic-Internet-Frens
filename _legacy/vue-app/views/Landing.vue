<template>
  <div class="landing-page">
    <LandingHero />
    <LandingStats />
    <LandingFeatures />
    <LandingHowItWorks />
    <LandingSecurity />
    <LandingCta />
    <LandingFooter />
  </div>
</template>

<script>
import { defineAsyncComponent } from "vue";

export default {
  components: {
    LandingHero: defineAsyncComponent(() =>
      import("@/components/landing/LandingHero.vue")
    ),
    LandingStats: defineAsyncComponent(() =>
      import("@/components/landing/LandingStats.vue")
    ),
    LandingFeatures: defineAsyncComponent(() =>
      import("@/components/landing/LandingFeatures.vue")
    ),
    LandingHowItWorks: defineAsyncComponent(() =>
      import("@/components/landing/LandingHowItWorks.vue")
    ),
    LandingSecurity: defineAsyncComponent(() =>
      import("@/components/landing/LandingSecurity.vue")
    ),
    LandingCta: defineAsyncComponent(() =>
      import("@/components/landing/LandingCta.vue")
    ),
    LandingFooter: defineAsyncComponent(() =>
      import("@/components/landing/LandingFooter.vue")
    ),
  },
};
</script>

<style lang="scss" scoped>
.landing-page {
  overflow-x: hidden;
}
</style>
