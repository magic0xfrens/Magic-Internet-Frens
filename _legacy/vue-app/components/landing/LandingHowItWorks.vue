<template>
  <section id="how-it-works" class="hiw" ref="section">
    <div class="hiw-inner">
      <div class="hiw-header">
        <span class="hiw-eyebrow">Process</span>
        <h2 class="hiw-title">From wallet to yield in 4 steps</h2>
      </div>

      <div class="hiw-steps">
        <div class="hiw-connector" ref="connector"></div>
        <div class="hiw-step" v-for="(step, i) in steps" :key="step.title">
          <div class="hiw-step-marker">
            <span class="hiw-step-num">{{ i + 1 }}</span>
            <div class="hiw-step-ring"></div>
          </div>
          <div class="hiw-step-body">
            <h3 class="hiw-step-title">{{ step.title }}</h3>
            <p class="hiw-step-desc">{{ step.description }}</p>
          </div>
        </div>
      </div>
    </div>
  </section>
</template>

<script>
import { useScrollAnimations } from "@/helpers/useScrollAnimations";

export default {
  setup() {
    const { createTimeline } = useScrollAnimations();
    return { createTimeline };
  },

  data() {
    return {
      steps: [
        { title: "Connect Wallet", description: "Link MetaMask, WalletConnect, or Coinbase Wallet to the protocol." },
        { title: "Choose a Cauldron", description: "Browse isolated lending markets and select one that fits your collateral." },
        { title: "Deposit Collateral", description: "Supply your assets to the cauldron smart contract as backing." },
        { title: "Borrow & Earn", description: "Take a loan against your collateral and deploy it across DeFi." },
      ],
    };
  },

  mounted() {
    const tl = this.createTimeline(this.$refs.section);

    tl.fromTo(".hiw-header", { opacity: 0, y: 24 }, { opacity: 1, y: 0, duration: 0.6 })
      .fromTo(this.$refs.connector, { scaleY: 0 }, { scaleY: 1, duration: 0.8, ease: "power2.inOut" }, "-=0.2")
      .fromTo(".hiw-step", { opacity: 0, x: -30 }, { opacity: 1, x: 0, stagger: 0.15, duration: 0.5, ease: "power2.out" }, "-=0.5");
  },
};
</script>

<style lang="scss" scoped>
.hiw {
  position: relative;
  padding: 120px 0;
}

.hiw-inner {
  max-width: 1280px;
  margin: 0 auto;
  padding: 0 32px;
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 80px;
  align-items: start;
}

.hiw-header {
  position: sticky;
  top: 120px;
}

.hiw-eyebrow {
  display: inline-block;
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.2em;
  text-transform: uppercase;
  color: #F7931A;
  margin-bottom: 16px;
}

.hiw-title {
  font-family: "Prompt", sans-serif;
  font-size: clamp(28px, 3.5vw, 44px);
  font-weight: 700;
  color: #fff;
  line-height: 1.2;
}

.hiw-steps {
  position: relative;
  display: flex;
  flex-direction: column;
  gap: 0;
}

.hiw-connector {
  position: absolute;
  left: 19px;
  top: 24px;
  bottom: 24px;
  width: 2px;
  background: linear-gradient(180deg, #F7931A, rgba(255, 215, 0, 0.15));
  transform-origin: top center;
  z-index: 0;
}

.hiw-step {
  position: relative;
  z-index: 1;
  display: flex;
  gap: 24px;
  padding: 24px 0;
  opacity: 0;
}

.hiw-step-marker {
  position: relative;
  flex-shrink: 0;
  width: 40px;
  height: 40px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.hiw-step-num {
  position: relative;
  z-index: 2;
  font-family: "Prompt", sans-serif;
  font-size: 14px;
  font-weight: 700;
  color: #0a0c18;
  width: 32px;
  height: 32px;
  border-radius: 50%;
  background: linear-gradient(135deg, #F7931A, #FFD700);
  display: flex;
  align-items: center;
  justify-content: center;
}

.hiw-step-ring {
  position: absolute;
  inset: -2px;
  border-radius: 50%;
  border: 1px solid rgba(247, 147, 26, 0.15);
}

.hiw-step-body {
  padding-top: 4px;
}

.hiw-step-title {
  font-family: "Prompt", sans-serif;
  font-size: 17px;
  font-weight: 600;
  color: #fff;
  margin-bottom: 6px;
}

.hiw-step-desc {
  font-size: 14px;
  line-height: 1.65;
  color: rgba(255, 255, 255, 0.42);
}

@media (max-width: 860px) {
  .hiw-inner {
    grid-template-columns: 1fr;
    gap: 40px;
  }

  .hiw-header {
    position: static;
    text-align: center;
  }

  .hiw { padding: 80px 0; }
}
</style>
