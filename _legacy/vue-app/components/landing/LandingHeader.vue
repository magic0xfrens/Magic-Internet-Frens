<template>
  <header class="lh" :class="{ scrolled: isScrolled }">
    <div class="lh-inner">
      <router-link to="/" class="lh-brand">
        <MainLogoIcon :width="34" :height="34" />
        <span class="lh-wordmark">MIF</span>
      </router-link>

      <nav class="lh-nav">
        <a
          v-for="link in navLinks"
          :key="link.id"
          :href="`#${link.id}`"
          class="lh-nav-link"
          @click.prevent="scrollTo(link.id)"
        >
          <span class="lh-nav-dot"></span>
          {{ link.label }}
        </a>
      </nav>

      <router-link to="/cauldrons" class="lh-cta">
        <span class="lh-cta-text">Launch App</span>
        <svg class="lh-cta-arrow" width="14" height="14" viewBox="0 0 14 14" fill="none">
          <path d="M1 7h11M8 3l4 4-4 4" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
        </svg>
      </router-link>
    </div>
  </header>
</template>

<script>
import { defineAsyncComponent } from "vue";

export default {
  data() {
    return {
      isScrolled: false,
      navLinks: [
        { id: "features", label: "Features" },
        { id: "how-it-works", label: "Process" },
        { id: "security", label: "Security" },
      ],
    };
  },

  mounted() {
    window.addEventListener("scroll", this.handleScroll, { passive: true });
  },

  beforeUnmount() {
    window.removeEventListener("scroll", this.handleScroll);
  },

  methods: {
    handleScroll() {
      this.isScrolled = window.scrollY > 50;
    },
    scrollTo(id) {
      const el = document.getElementById(id);
      if (el) el.scrollIntoView({ behavior: "smooth", block: "start" });
    },
  },

  components: {
    MainLogoIcon: defineAsyncComponent(() =>
      import("@/components/ui/icons/MainLogoIcon.vue")
    ),
  },
};
</script>

<style lang="scss" scoped>
.lh {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  z-index: 200;
  transition: all 0.4s cubic-bezier(0.16, 1, 0.3, 1);

  &::after {
    content: "";
    position: absolute;
    bottom: 0;
    left: 5%;
    right: 5%;
    height: 1px;
    background: linear-gradient(90deg, transparent, rgba(247, 147, 26, 0.08), transparent);
    transition: opacity 0.4s ease;
    opacity: 0;
  }

  &.scrolled {
    background: rgba(10, 12, 24, 0.82);
    backdrop-filter: blur(24px) saturate(1.4);
    -webkit-backdrop-filter: blur(24px) saturate(1.4);

    &::after {
      opacity: 1;
    }
  }
}

.lh-inner {
  max-width: 1280px;
  margin: 0 auto;
  padding: 18px 32px;
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.lh-brand {
  display: flex;
  align-items: center;
  gap: 11px;
  text-decoration: none;
}

.lh-wordmark {
  font-family: "Prompt", sans-serif;
  font-size: 19px;
  font-weight: 700;
  letter-spacing: 0.08em;
  background: linear-gradient(135deg, #F7931A 0%, #FFD700 60%, #FFA726 100%);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
}

.lh-nav {
  display: flex;
  gap: 36px;
}

.lh-nav-link {
  display: flex;
  align-items: center;
  gap: 6px;
  color: rgba(255, 255, 255, 0.44);
  text-decoration: none;
  font-size: 13px;
  font-weight: 500;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  transition: color 0.25s ease;

  .lh-nav-dot {
    width: 4px;
    height: 4px;
    border-radius: 50%;
    background: rgba(247, 147, 26, 0);
    transition: all 0.25s ease;
  }

  &:hover {
    color: rgba(255, 255, 255, 0.9);

    .lh-nav-dot {
      background: #F7931A;
      box-shadow: 0 0 8px rgba(247, 147, 26, 0.5);
    }
  }
}

.lh-cta {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 22px;
  border-radius: 8px;
  border: 1px solid rgba(247, 147, 26, 0.35);
  background: rgba(247, 147, 26, 0.06);
  color: #FFD700;
  font-size: 13px;
  font-weight: 600;
  letter-spacing: 0.03em;
  text-decoration: none;
  transition: all 0.3s cubic-bezier(0.16, 1, 0.3, 1);

  &:hover {
    background: linear-gradient(135deg, #F7931A, #FFD700);
    color: #0a0c18;
    border-color: transparent;
    box-shadow: 0 4px 24px rgba(247, 147, 26, 0.3);

    .lh-cta-arrow {
      transform: translateX(3px);
    }
  }
}

.lh-cta-arrow {
  transition: transform 0.3s ease;
}

@media (max-width: 860px) {
  .lh-nav { display: none; }
  .lh-inner { padding: 14px 20px; }
}
</style>
