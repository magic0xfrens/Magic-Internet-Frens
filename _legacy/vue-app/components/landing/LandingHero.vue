<template>
  <section class="hero">
    <!-- Atmospheric layers -->
    <div class="hero-noise"></div>
    <div class="hero-orb hero-orb--1"></div>
    <div class="hero-orb hero-orb--2"></div>
    <div class="hero-orb hero-orb--3"></div>
    <div class="hero-grid-lines"></div>

    <div class="hero-inner">
      <div class="hero-content" ref="content">
        <div class="hero-tag">
          <span class="hero-tag-pulse"></span>
          <span class="hero-tag-text">Live on 5 Chains</span>
        </div>

        <h1 class="hero-h1">
          <span class="hero-h1-line hero-h1-line--1">Magic Internet</span>
          <span class="hero-h1-line hero-h1-line--2">
            <span class="hero-h1-gradient">Frens</span>
          </span>
        </h1>

        <p class="hero-desc">
          The arcane protocol for decentralized lending. Deposit collateral into
          Cauldrons, borrow against it, and earn yield — across Ethereum, Arbitrum,
          and beyond.
        </p>

        <div class="hero-actions">
          <router-link to="/cauldrons" class="hero-btn hero-btn--primary">
            <span>Enter the App</span>
            <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
              <path d="M3 8h9M9 4l4 4-4 4" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
            </svg>
          </router-link>
          <a
            href="https://magicinternetfrensmoney.gitbook.io/magicinternetfrens-money-wiki/"
            target="_blank"
            rel="noreferrer noopener"
            class="hero-btn hero-btn--ghost"
          >Documentation</a>
        </div>

        <div class="hero-proof">
          <div class="hero-proof-item">
            <span class="hero-proof-val">$150M+</span>
            <span class="hero-proof-label">TVL Secured</span>
          </div>
          <div class="hero-proof-sep"></div>
          <div class="hero-proof-item">
            <span class="hero-proof-val">10K+</span>
            <span class="hero-proof-label">Active Users</span>
          </div>
          <div class="hero-proof-sep"></div>
          <div class="hero-proof-item">
            <span class="hero-proof-val">25+</span>
            <span class="hero-proof-label">Cauldrons</span>
          </div>
        </div>
      </div>

      <div class="hero-visual" ref="visual">
        <div class="hero-wizard-ring"></div>
        <div class="hero-wizard-glow"></div>
        <img
          ref="wizard"
          src="@/assets/images/mif/wizard.png"
          alt="MIF Wizard"
          class="hero-wizard"
        />
      </div>
    </div>
  </section>
</template>

<script>
import gsap from "gsap";

export default {
  mounted() {
    const tl = gsap.timeline({ defaults: { ease: "power3.out" } });

    tl.fromTo(".hero-tag", { opacity: 0, y: 20 }, { opacity: 1, y: 0, duration: 0.6 }, 0.3)
      .fromTo(".hero-h1-line--1", { opacity: 0, y: 40, clipPath: "inset(0 0 100% 0)" }, { opacity: 1, y: 0, clipPath: "inset(0 0 0% 0)", duration: 0.9 }, 0.4)
      .fromTo(".hero-h1-line--2", { opacity: 0, y: 40, clipPath: "inset(0 0 100% 0)" }, { opacity: 1, y: 0, clipPath: "inset(0 0 0% 0)", duration: 0.9 }, 0.55)
      .fromTo(".hero-desc", { opacity: 0, y: 20 }, { opacity: 1, y: 0, duration: 0.7 }, 0.8)
      .fromTo(".hero-actions", { opacity: 0, y: 20 }, { opacity: 1, y: 0, duration: 0.6 }, 1.0)
      .fromTo(".hero-proof", { opacity: 0, y: 16 }, { opacity: 1, y: 0, duration: 0.6 }, 1.15);

    // Wizard entrance
    gsap.fromTo(this.$refs.visual,
      { opacity: 0, scale: 0.85, y: 40 },
      { opacity: 1, scale: 1, y: 0, duration: 1.2, ease: "power2.out", delay: 0.5 }
    );

    // Floating wizard
    gsap.to(this.$refs.wizard, {
      y: -18,
      duration: 3.5,
      ease: "sine.inOut",
      yoyo: true,
      repeat: -1,
    });

    // Ring rotation
    gsap.to(".hero-wizard-ring", {
      rotation: 360,
      duration: 40,
      ease: "none",
      repeat: -1,
    });

    // Orb drift
    gsap.to(".hero-orb--1", { x: 30, y: -20, duration: 8, ease: "sine.inOut", yoyo: true, repeat: -1 });
    gsap.to(".hero-orb--2", { x: -25, y: 15, duration: 10, ease: "sine.inOut", yoyo: true, repeat: -1 });
    gsap.to(".hero-orb--3", { x: 20, y: 25, duration: 7, ease: "sine.inOut", yoyo: true, repeat: -1 });
  },
};
</script>

<style lang="scss" scoped>
.hero {
  position: relative;
  min-height: 100vh;
  display: flex;
  align-items: center;
  padding-top: 80px;
  overflow: hidden;
}

// Noise overlay
.hero-noise {
  position: absolute;
  inset: 0;
  background-image: url("data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.85' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)' opacity='0.03'/%3E%3C/svg%3E");
  background-repeat: repeat;
  pointer-events: none;
  z-index: 1;
}

// Floating orbs
.hero-orb {
  position: absolute;
  border-radius: 50%;
  filter: blur(80px);
  pointer-events: none;
  z-index: 0;

  &--1 {
    width: 500px;
    height: 500px;
    top: -10%;
    right: -5%;
    background: radial-gradient(circle, rgba(247, 147, 26, 0.12) 0%, transparent 70%);
  }

  &--2 {
    width: 350px;
    height: 350px;
    bottom: 10%;
    left: -8%;
    background: radial-gradient(circle, rgba(116, 92, 210, 0.1) 0%, transparent 70%);
  }

  &--3 {
    width: 250px;
    height: 250px;
    top: 40%;
    left: 40%;
    background: radial-gradient(circle, rgba(255, 215, 0, 0.06) 0%, transparent 70%);
  }
}

// Subtle grid pattern
.hero-grid-lines {
  position: absolute;
  inset: 0;
  background-image:
    linear-gradient(rgba(247, 147, 26, 0.015) 1px, transparent 1px),
    linear-gradient(90deg, rgba(247, 147, 26, 0.015) 1px, transparent 1px);
  background-size: 80px 80px;
  pointer-events: none;
  z-index: 0;
  mask-image: radial-gradient(ellipse at 50% 50%, black 20%, transparent 70%);
  -webkit-mask-image: radial-gradient(ellipse at 50% 50%, black 20%, transparent 70%);
}

.hero-inner {
  position: relative;
  z-index: 2;
  max-width: 1280px;
  margin: 0 auto;
  padding: 0 32px;
  display: grid;
  grid-template-columns: 1.1fr 0.9fr;
  gap: 40px;
  align-items: center;
  width: 100%;
}

// Content — initial hidden state for GSAP entrance
.hero-content > .hero-tag,
.hero-content > .hero-desc,
.hero-content > .hero-actions,
.hero-content > .hero-proof {
  opacity: 0;
}

.hero-h1-line {
  opacity: 0;
}

.hero-tag {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 6px 14px 6px 10px;
  border-radius: 100px;
  background: rgba(247, 147, 26, 0.06);
  border: 1px solid rgba(247, 147, 26, 0.15);
  margin-bottom: 28px;
}

.hero-tag-pulse {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: #4ade80;
  box-shadow: 0 0 8px rgba(74, 222, 128, 0.6);
  animation: pulse 2s ease-in-out infinite;
}

@keyframes pulse {
  0%, 100% { opacity: 1; transform: scale(1); }
  50% { opacity: 0.5; transform: scale(0.8); }
}

.hero-tag-text {
  font-size: 12px;
  font-weight: 600;
  letter-spacing: 0.06em;
  color: rgba(255, 255, 255, 0.7);
  text-transform: uppercase;
}

.hero-h1 {
  margin-bottom: 24px;
}

.hero-h1-line {
  display: block;
  font-family: "Prompt", sans-serif;
  font-weight: 700;
  line-height: 1.05;
  letter-spacing: -0.02em;

  &--1 {
    font-size: clamp(42px, 5.5vw, 72px);
    color: #fff;
  }

  &--2 {
    font-size: clamp(48px, 6.5vw, 86px);
  }
}

.hero-h1-gradient {
  background: linear-gradient(135deg, #F7931A 0%, #FFD700 45%, #FFA726 80%, #FF8F00 100%);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
  filter: drop-shadow(0 0 40px rgba(247, 147, 26, 0.15));
}

.hero-desc {
  font-size: 16px;
  line-height: 1.75;
  color: rgba(255, 255, 255, 0.5);
  max-width: 500px;
  margin-bottom: 36px;
}

.hero-actions {
  display: flex;
  gap: 14px;
  flex-wrap: wrap;
  margin-bottom: 48px;
}

.hero-btn {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 14px 28px;
  border-radius: 10px;
  font-size: 14px;
  font-weight: 600;
  text-decoration: none;
  transition: all 0.3s cubic-bezier(0.16, 1, 0.3, 1);
  cursor: pointer;

  &--primary {
    background: linear-gradient(135deg, #F7931A 0%, #FFD700 100%);
    color: #0a0c18;
    box-shadow: 0 4px 20px rgba(247, 147, 26, 0.25), inset 0 1px 0 rgba(255, 255, 255, 0.2);

    &:hover {
      transform: translateY(-2px);
      box-shadow: 0 8px 32px rgba(247, 147, 26, 0.35), inset 0 1px 0 rgba(255, 255, 255, 0.2);
    }
  }

  &--ghost {
    border: 1px solid rgba(255, 255, 255, 0.1);
    color: rgba(255, 255, 255, 0.65);
    background: rgba(255, 255, 255, 0.02);

    &:hover {
      border-color: rgba(255, 255, 255, 0.2);
      color: #fff;
      background: rgba(255, 255, 255, 0.04);
    }
  }
}

// Social proof strip
.hero-proof {
  display: flex;
  align-items: center;
  gap: 28px;
}

.hero-proof-sep {
  width: 1px;
  height: 32px;
  background: linear-gradient(180deg, transparent, rgba(255, 255, 255, 0.1), transparent);
}

.hero-proof-val {
  display: block;
  font-family: "Prompt", sans-serif;
  font-size: 22px;
  font-weight: 700;
  color: #fff;
}

.hero-proof-label {
  display: block;
  font-size: 11px;
  font-weight: 500;
  color: rgba(255, 255, 255, 0.35);
  letter-spacing: 0.05em;
  text-transform: uppercase;
  margin-top: 2px;
}

// Wizard visual
.hero-visual {
  position: relative;
  display: flex;
  justify-content: center;
  align-items: center;
  opacity: 0;
}

.hero-wizard-glow {
  position: absolute;
  width: 380px;
  height: 380px;
  border-radius: 50%;
  background: radial-gradient(circle,
    rgba(247, 147, 26, 0.18) 0%,
    rgba(247, 147, 26, 0.06) 40%,
    transparent 70%
  );
  filter: blur(20px);
}

.hero-wizard-ring {
  position: absolute;
  width: 440px;
  height: 440px;
  border-radius: 50%;
  border: 1px dashed rgba(247, 147, 26, 0.08);
  pointer-events: none;
}

.hero-wizard {
  position: relative;
  max-width: 440px;
  width: 100%;
  height: auto;
  z-index: 1;
  filter: drop-shadow(0 20px 60px rgba(0, 0, 0, 0.4));
}

@media (max-width: 960px) {
  .hero-inner {
    grid-template-columns: 1fr;
    text-align: center;
    gap: 48px;
    padding: 0 20px;
  }

  .hero-desc { margin-left: auto; margin-right: auto; }
  .hero-actions { justify-content: center; }
  .hero-proof { justify-content: center; }

  .hero-visual { order: -1; }

  .hero-wizard {
    max-width: 320px;
  }

  .hero-wizard-glow {
    width: 260px;
    height: 260px;
  }

  .hero-wizard-ring {
    width: 320px;
    height: 320px;
  }
}

@media (max-width: 480px) {
  .hero-proof {
    flex-direction: column;
    gap: 16px;
  }

  .hero-proof-sep { width: 40px; height: 1px; }
}
</style>
