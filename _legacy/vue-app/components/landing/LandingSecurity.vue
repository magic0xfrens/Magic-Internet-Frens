<template>
  <section id="security" class="sec" ref="section">
    <div class="sec-inner">
      <div class="sec-content" ref="contentCol">
        <span class="sec-eyebrow">Trust</span>
        <h2 class="sec-title">Battle-tested<br />smart contracts</h2>
        <p class="sec-desc">
          Security is the foundation, not a feature. The protocol is built on
          audited, open-source contracts with years of production history.
        </p>

        <div class="sec-items">
          <div class="sec-item" v-for="item in items" :key="item.title">
            <div class="sec-item-icon">
              <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
                <path d="M2 8.5l4 4 8-9" stroke="#F7931A" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
              </svg>
            </div>
            <div>
              <div class="sec-item-title">{{ item.title }}</div>
              <div class="sec-item-desc">{{ item.desc }}</div>
            </div>
          </div>
        </div>
      </div>

      <div class="sec-visual" ref="visualCol">
        <div class="sec-viz-glow"></div>
        <div class="sec-shield">
          <svg width="200" height="240" viewBox="0 0 200 240" fill="none">
            <path d="M100 8L12 52v80c0 55.2 37.6 106.8 88 120 50.4-13.2 88-64.8 88-120V52L100 8z"
              stroke="url(#shieldGrad)" stroke-width="1.5" fill="rgba(247,147,26,0.02)" />
            <defs>
              <linearGradient id="shieldGrad" x1="100" y1="8" x2="100" y2="240">
                <stop offset="0%" stop-color="#F7931A" stop-opacity="0.6"/>
                <stop offset="100%" stop-color="#FFD700" stop-opacity="0.1"/>
              </linearGradient>
            </defs>
          </svg>
          <img
            src="@/assets/images/mif/wizard.svg"
            alt="Wizard"
            class="sec-shield-wizard"
          />
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
      items: [
        { title: "Multiple Audits", desc: "Reviewed by top-tier security firms with public reports." },
        { title: "Production Proven", desc: "Years of mainnet deployment securing hundreds of millions." },
        { title: "Open Source", desc: "Every line of code verifiable on-chain and on GitHub." },
        { title: "Multi-Chain", desc: "Consistent security standards across all deployed networks." },
      ],
    };
  },

  mounted() {
    const tl = this.createTimeline(this.$refs.section);

    tl.fromTo(this.$refs.contentCol, { opacity: 0, x: -40 }, { opacity: 1, x: 0, duration: 0.8, ease: "power2.out" })
      .fromTo(this.$refs.visualCol, { opacity: 0, x: 40, scale: 0.95 }, { opacity: 1, x: 0, scale: 1, duration: 0.8, ease: "power2.out" }, "<0.15")
      .fromTo(".sec-item", { opacity: 0, y: 16 }, { opacity: 1, y: 0, stagger: 0.1, duration: 0.4 }, "-=0.4");
  },
};
</script>

<style lang="scss" scoped>
.sec {
  position: relative;
  padding: 120px 0;
}

.sec-inner {
  max-width: 1280px;
  margin: 0 auto;
  padding: 0 32px;
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 80px;
  align-items: center;
}

.sec-content { opacity: 0; }

.sec-eyebrow {
  display: inline-block;
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.2em;
  text-transform: uppercase;
  color: #F7931A;
  margin-bottom: 16px;
}

.sec-title {
  font-family: "Prompt", sans-serif;
  font-size: clamp(28px, 3.5vw, 44px);
  font-weight: 700;
  color: #fff;
  line-height: 1.15;
  margin-bottom: 16px;
}

.sec-desc {
  font-size: 15px;
  line-height: 1.7;
  color: rgba(255, 255, 255, 0.45);
  margin-bottom: 36px;
  max-width: 440px;
}

.sec-items {
  display: flex;
  flex-direction: column;
  gap: 20px;
}

.sec-item {
  display: flex;
  gap: 14px;
  opacity: 0;
}

.sec-item-icon {
  flex-shrink: 0;
  width: 32px;
  height: 32px;
  border-radius: 8px;
  background: rgba(247, 147, 26, 0.06);
  border: 1px solid rgba(247, 147, 26, 0.1);
  display: flex;
  align-items: center;
  justify-content: center;
  margin-top: 2px;
}

.sec-item-title {
  font-size: 14px;
  font-weight: 600;
  color: rgba(255, 255, 255, 0.85);
  margin-bottom: 2px;
}

.sec-item-desc {
  font-size: 13px;
  color: rgba(255, 255, 255, 0.38);
  line-height: 1.5;
}

// Visual column
.sec-visual {
  position: relative;
  display: flex;
  justify-content: center;
  align-items: center;
  min-height: 360px;
  opacity: 0;
}

.sec-viz-glow {
  position: absolute;
  width: 300px;
  height: 300px;
  border-radius: 50%;
  background: radial-gradient(circle, rgba(247, 147, 26, 0.1) 0%, transparent 70%);
  filter: blur(40px);
}

.sec-shield {
  position: relative;
  display: flex;
  align-items: center;
  justify-content: center;
}

.sec-shield-wizard {
  position: absolute;
  width: 100px;
  height: auto;
  opacity: 0.6;
  filter: drop-shadow(0 4px 20px rgba(247, 147, 26, 0.15));
}

@media (max-width: 860px) {
  .sec-inner {
    grid-template-columns: 1fr;
    gap: 48px;
    text-align: center;
  }

  .sec-desc { margin-left: auto; margin-right: auto; }
  .sec-items { align-items: center; }
  .sec-item { text-align: left; }
  .sec { padding: 80px 0; }
}
</style>
