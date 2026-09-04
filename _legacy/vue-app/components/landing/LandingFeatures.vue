<template>
  <section id="features" class="feat">
    <div class="feat-inner">
      <div class="feat-header">
        <span class="feat-eyebrow">Protocol</span>
        <h2 class="feat-title">
          Three pillars of
          <span class="feat-title-accent">magic</span>
        </h2>
        <p class="feat-subtitle">
          A composable DeFi ecosystem built for borrowers, stakers, and collectors.
        </p>
      </div>

      <div class="feat-grid">
        <div
          class="feat-card"
          v-for="(f, i) in features"
          :key="f.title"
          :class="`feat-card--${i}`"
        >
          <div class="feat-card-glow"></div>
          <div class="feat-card-inner">
            <div class="feat-card-icon">
              <img :src="f.icon" :alt="f.title" />
            </div>
            <div class="feat-card-num">0{{ i + 1 }}</div>
            <h3 class="feat-card-title">{{ f.title }}</h3>
            <p class="feat-card-desc">{{ f.description }}</p>
            <router-link :to="f.link" class="feat-card-link">
              {{ f.linkText }}
              <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
                <path d="M1 7h11M8 3l4 4-4 4" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
              </svg>
            </router-link>
          </div>
        </div>
      </div>
    </div>
  </section>
</template>

<script>
import { useScrollAnimations } from "@/helpers/useScrollAnimations";
import cauldronImg from "@/assets/images/mif/cauldron.webp";
import potionImg from "@/assets/images/mif/Potion.svg";
import plebFrenImg from "@/assets/images/mif/PlebFren.svg";

export default {
  setup() {
    const { createTimeline } = useScrollAnimations();
    return { createTimeline };
  },

  data() {
    return {
      features: [
        {
          icon: cauldronImg,
          title: "Magic Cauldrons",
          description: "Isolated lending markets with optimized risk. Deposit collateral, borrow stablecoins — each cauldron is independently managed.",
          link: "/cauldrons",
          linkText: "View Cauldrons",
        },
        {
          icon: potionImg,
          title: "FREN Staking",
          description: "Lock tokens to earn your share of protocol revenue. Longer commitments mean deeper magic and higher rewards.",
          link: "/staking",
          linkText: "Start Staking",
        },
        {
          icon: plebFrenImg,
          title: "MiFREN NFTs",
          description: "Companion NFTs that aren't just art — they unlock yield boosts, governance votes, and exclusive protocol perks.",
          link: "/nft",
          linkText: "Mint NFT",
        },
      ],
    };
  },

  mounted() {
    const tl = this.createTimeline(".feat");

    tl.fromTo(".feat-header", { opacity: 0, y: 30 }, { opacity: 1, y: 0, duration: 0.7 })
      .fromTo(".feat-card", { opacity: 0, y: 50, scale: 0.96 }, { opacity: 1, y: 0, scale: 1, stagger: 0.12, duration: 0.7, ease: "power2.out" }, "-=0.3");
  },
};
</script>

<style lang="scss" scoped>
.feat {
  position: relative;
  padding: 120px 0;
}

.feat-inner {
  max-width: 1280px;
  margin: 0 auto;
  padding: 0 32px;
}

.feat-header {
  text-align: center;
  margin-bottom: 64px;
}

.feat-eyebrow {
  display: inline-block;
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.2em;
  text-transform: uppercase;
  color: #F7931A;
  margin-bottom: 16px;
  position: relative;

  &::before,
  &::after {
    content: "";
    position: absolute;
    top: 50%;
    width: 32px;
    height: 1px;
    background: rgba(247, 147, 26, 0.3);
  }

  &::before { right: calc(100% + 12px); }
  &::after { left: calc(100% + 12px); }
}

.feat-title {
  font-family: "Prompt", sans-serif;
  font-size: clamp(32px, 4vw, 50px);
  font-weight: 700;
  color: #fff;
  line-height: 1.15;
  margin-bottom: 16px;
}

.feat-title-accent {
  background: linear-gradient(135deg, #F7931A, #FFD700);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
}

.feat-subtitle {
  font-size: 16px;
  color: rgba(255, 255, 255, 0.45);
  max-width: 480px;
  margin: 0 auto;
  line-height: 1.6;
}

.feat-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 20px;
}

.feat-card {
  position: relative;
  border-radius: 20px;
  border: 1px solid rgba(247, 147, 26, 0.08);
  background: linear-gradient(160deg, rgba(18, 16, 30, 0.8) 0%, rgba(12, 10, 22, 0.9) 100%);
  overflow: hidden;
  transition: border-color 0.4s ease, transform 0.4s cubic-bezier(0.16, 1, 0.3, 1);

  &:hover {
    border-color: rgba(247, 147, 26, 0.2);
    transform: translateY(-4px);

    .feat-card-glow { opacity: 1; }
    .feat-card-link { color: #FFD700; gap: 10px; }
  }
}

.feat-card-glow {
  position: absolute;
  inset: 0;
  background: radial-gradient(ellipse at 50% 0%, rgba(247, 147, 26, 0.06) 0%, transparent 60%);
  opacity: 0;
  transition: opacity 0.4s ease;
  pointer-events: none;
}

.feat-card-inner {
  position: relative;
  padding: 40px 32px 36px;
}

.feat-card-icon {
  width: 56px;
  height: 56px;
  display: flex;
  align-items: center;
  justify-content: center;
  margin-bottom: 24px;
  border-radius: 14px;
  background: rgba(247, 147, 26, 0.06);
  border: 1px solid rgba(247, 147, 26, 0.1);

  img {
    max-width: 32px;
    max-height: 32px;
  }
}

.feat-card-num {
  position: absolute;
  top: 32px;
  right: 32px;
  font-family: "Prompt", sans-serif;
  font-size: 13px;
  font-weight: 700;
  color: rgba(255, 255, 255, 0.06);
  letter-spacing: 0.05em;
}

.feat-card-title {
  font-family: "Prompt", sans-serif;
  font-size: 20px;
  font-weight: 600;
  color: #fff;
  margin-bottom: 12px;
}

.feat-card-desc {
  font-size: 14px;
  line-height: 1.7;
  color: rgba(255, 255, 255, 0.45);
  margin-bottom: 24px;
}

.feat-card-link {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 13px;
  font-weight: 600;
  color: rgba(255, 255, 255, 0.35);
  text-decoration: none;
  transition: all 0.3s ease;

  svg { transition: transform 0.3s ease; }
}

@media (max-width: 860px) {
  .feat-grid { grid-template-columns: 1fr; max-width: 480px; margin: 0 auto; }
  .feat { padding: 80px 0; }
}
</style>
