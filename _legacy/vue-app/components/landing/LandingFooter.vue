<template>
  <footer class="ft">
    <div class="ft-inner">
      <div class="ft-top">
        <div class="ft-brand">
          <div class="ft-logo">
            <MainLogoIcon :width="28" :height="28" />
            <span class="ft-logo-name">Magic Internet Frens</span>
          </div>
          <p class="ft-tagline">
            Decentralized lending, staking, and NFTs — across every chain that matters.
          </p>
        </div>

        <div class="ft-col">
          <h5 class="ft-col-title">Protocol</h5>
          <nav class="ft-links">
            <router-link to="/cauldrons">Cauldrons</router-link>
            <router-link to="/staking">Staking</router-link>
            <router-link to="/swap">Swap</router-link>
            <router-link to="/nft">NFT</router-link>
          </nav>
        </div>

        <div class="ft-col">
          <h5 class="ft-col-title">Resources</h5>
          <nav class="ft-links">
            <a href="https://magicinternetfrensmoney.gitbook.io/magicinternetfrens-money-wiki/" target="_blank" rel="noreferrer noopener">Documentation</a>
            <a href="https://github.com/Magic Internet Frens-money" target="_blank" rel="noreferrer noopener">GitHub</a>
          </nav>
        </div>

        <div class="ft-col">
          <h5 class="ft-col-title">Community</h5>
          <div class="ft-socials">
            <Twitter :width="16" />
            <Discord :width="16" />
            <GitHub :width="16" />
          </div>
        </div>
      </div>

      <div class="ft-bottom">
        <span class="ft-copy">&copy; {{ year }} Magic Internet Frens</span>
        <span class="ft-sep"></span>
        <span class="ft-built">Built with magic</span>
      </div>
    </div>
  </footer>
</template>

<script>
import { defineAsyncComponent } from "vue";

export default {
  computed: {
    year() { return new Date().getFullYear(); },
  },
  components: {
    MainLogoIcon: defineAsyncComponent(() => import("@/components/ui/icons/MainLogoIcon.vue")),
    Twitter: defineAsyncComponent(() => import("@/components/ui/icons/Twitter.vue")),
    Discord: defineAsyncComponent(() => import("@/components/ui/icons/Discord.vue")),
    GitHub: defineAsyncComponent(() => import("@/components/ui/icons/GitHub.vue")),
  },
};
</script>

<style lang="scss" scoped>
.ft {
  position: relative;

  &::before {
    content: "";
    position: absolute;
    top: 0;
    left: 5%;
    right: 5%;
    height: 1px;
    background: linear-gradient(90deg, transparent, rgba(247, 147, 26, 0.1), transparent);
  }
}

.ft-inner {
  max-width: 1280px;
  margin: 0 auto;
  padding: 56px 32px 0;
}

.ft-top {
  display: grid;
  grid-template-columns: 2fr 1fr 1fr 1fr;
  gap: 40px;
  padding-bottom: 48px;
}

.ft-brand { max-width: 320px; }

.ft-logo {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 14px;
}

.ft-logo-name {
  font-family: "Prompt", sans-serif;
  font-size: 15px;
  font-weight: 600;
  color: #fff;
}

.ft-tagline {
  font-size: 13px;
  line-height: 1.65;
  color: rgba(255, 255, 255, 0.3);
}

.ft-col-title {
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.15em;
  text-transform: uppercase;
  color: rgba(255, 255, 255, 0.5);
  margin-bottom: 16px;
}

.ft-links {
  display: flex;
  flex-direction: column;
  gap: 10px;

  a {
    color: rgba(255, 255, 255, 0.35);
    text-decoration: none;
    font-size: 13px;
    transition: color 0.2s ease;

    &:hover { color: #FFD700; }
  }
}

.ft-socials {
  display: flex;
  gap: 14px;
}

.ft-bottom {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 16px;
  padding: 20px 0;
  border-top: 1px solid rgba(255, 255, 255, 0.04);
}

.ft-copy,
.ft-built {
  font-size: 11px;
  color: rgba(255, 255, 255, 0.2);
}

.ft-sep {
  width: 3px;
  height: 3px;
  border-radius: 50%;
  background: rgba(255, 255, 255, 0.1);
}

@media (max-width: 860px) {
  .ft-top {
    grid-template-columns: 1fr 1fr;
    gap: 32px;
  }

  .ft-brand {
    grid-column: 1 / -1;
    max-width: 100%;
    text-align: center;
  }

  .ft-logo { justify-content: center; }
}

@media (max-width: 480px) {
  .ft-top { grid-template-columns: 1fr; text-align: center; }
  .ft-socials { justify-content: center; }
}
</style>
