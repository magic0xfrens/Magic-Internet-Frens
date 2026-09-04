<template>
  <svg
    xmlns="http://www.w3.org/2000/svg"
    :style="`width: ${width}px; height: ${height}px;`"
    :class="{ pointer: pointer }"
    viewBox="0 0 42 42"
    fill="none"
  >
    <!-- MIF Wizard Hat Logo -->
    <defs>
      <linearGradient id="mifGrad" x1="0%" y1="0%" x2="100%" y2="100%">
        <stop offset="0%" style="stop-color:#F7931A;stop-opacity:1" />
        <stop offset="100%" style="stop-color:#FFD700;stop-opacity:1" />
      </linearGradient>
    </defs>
    <!-- Hat brim -->
    <ellipse cx="21" cy="36" rx="18" ry="4" fill="url(#mifGrad)" />
    <!-- Hat cone -->
    <path d="M8 36 L21 4 L34 36 Z" :fill="fill" />
    <!-- Hat band -->
    <rect x="8" y="32" width="26" height="4" rx="1" fill="url(#mifGrad)" />
    <!-- Star on hat -->
    <path d="M21 14 L22.5 18 L27 18 L23.5 21 L25 25 L21 22 L17 25 L18.5 21 L15 18 L19.5 18 Z" fill="url(#mifGrad)" />
  </svg>
</template>

<script>
export default {
  props: {
    width: {
      type: Number,
      default: 42,
    },
    height: {
      type: Number,
      default: 42,
    },
    fill: {
      type: String,
      default: "white",
    },
    pointer: {
      type: Boolean,
      default: false,
    },
  },
};
</script>

<style lang="scss" scoped>
path,
ellipse,
rect {
  transition: all 0.3s ease;
}

.pointer {
  cursor: pointer;
}
</style>
