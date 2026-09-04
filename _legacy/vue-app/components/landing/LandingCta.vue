<template>
  <section class="cta" ref="section">
    <div class="cta-inner">
      <div class="cta-box">
        <div class="cta-box-glow"></div>
        <div class="cta-box-noise"></div>
        <div class="cta-box-content">
          <h2 class="cta-title">
            Ready to enter the
            <span class="cta-title-accent">Cauldron</span>?
          </h2>
          <p class="cta-desc">
            Join thousands of frens borrowing, staking, and earning across
            multiple chains.
          </p>
          <router-link to="/cauldrons" class="cta-btn">
            <span>Launch App</span>
            <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
              <path d="M3 8h9M9 4l4 4-4 4" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
            </svg>
          </router-link>

          <div class="cta-socials">
            <Twitter :width="18" />
            <Discord :width="18" />
            <GitHub :width="18" />
          </div>
        </div>
      </div>
    </div>
  </section>
</template>

<script>
import { defineAsyncComponent } from "vue";
import { useScrollAnimations } from "@/helpers/useScrollAnimations";

export default {
  setup() {
    const { animateOnScroll } = useScrollAnimations();
    return { animateOnScroll };
  },

  mounted() {
    this.animateOnScroll(
      ".cta-box",
      { opacity: 0, y: 40 },
      { opacity: 1, y: 0, duration: 0.9, ease: "power2.out" }
    );
  },

  components: {
    Twitter: defineAsyncComponent(() => import("@/components/ui/icons/Twitter.vue")),
    Discord: defineAsyncComponent(() => import("@/components/ui/icons/Discord.vue")),
    GitHub: defineAsyncComponent(() => import("@/components/ui/icons/GitHub.vue")),
  },
};
</script>

<style lang="scss" scoped>
.cta {
  padding: 80px 0 120px;
}

.cta-inner {
  max-width: 1280px;
  margin: 0 auto;
  padding: 0 32px;
}

.cta-box {
  position: relative;
  border-radius: 24px;
  border: 1px solid rgba(247, 147, 26, 0.12);
  background: linear-gradient(160deg, rgba(20, 16, 36, 0.9) 0%, rgba(12, 10, 22, 0.95) 100%);
  overflow: hidden;
  opacity: 0;
}

.cta-box-glow {
  position: absolute;
  top: -50%;
  left: 50%;
  transform: translateX(-50%);
  width: 600px;
  height: 300px;
  background: radial-gradient(ellipse, rgba(247, 147, 26, 0.08) 0%, transparent 70%);
  pointer-events: none;
}

.cta-box-noise {
  position: absolute;
  inset: 0;
  background-image: url("data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.85' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)' opacity='0.02'/%3E%3C/svg%3E");
  pointer-events: none;
}

.cta-box-content {
  position: relative;
  text-align: center;
  padding: 72px 40px 64px;
}

.cta-title {
  font-family: "Prompt", sans-serif;
  font-size: clamp(28px, 3.5vw, 42px);
  font-weight: 700;
  color: #fff;
  line-height: 1.2;
  margin-bottom: 16px;
}

.cta-title-accent {
  background: linear-gradient(135deg, #F7931A, #FFD700);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
}

.cta-desc {
  font-size: 16px;
  color: rgba(255, 255, 255, 0.45);
  max-width: 440px;
  margin: 0 auto 36px;
  line-height: 1.65;
}

.cta-btn {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 15px 36px;
  border-radius: 10px;
  background: linear-gradient(135deg, #F7931A, #FFD700);
  color: #0a0c18;
  font-size: 15px;
  font-weight: 700;
  text-decoration: none;
  transition: all 0.3s cubic-bezier(0.16, 1, 0.3, 1);
  box-shadow: 0 4px 24px rgba(247, 147, 26, 0.25);
  position: relative;
  overflow: hidden;

  &::after {
    content: "";
    position: absolute;
    top: 0;
    left: -100%;
    width: 50%;
    height: 100%;
    background: linear-gradient(90deg, transparent, rgba(255, 255, 255, 0.2), transparent);
    animation: shimmer 4s ease-in-out infinite;
  }

  &:hover {
    transform: translateY(-2px);
    box-shadow: 0 8px 36px rgba(247, 147, 26, 0.35);
  }
}

@keyframes shimmer {
  0% { left: -100%; }
  100% { left: 250%; }
}

.cta-socials {
  margin-top: 32px;
  display: flex;
  justify-content: center;
  gap: 20px;
}

@media (max-width: 600px) {
  .cta-box-content { padding: 48px 24px 40px; }
}
</style>
