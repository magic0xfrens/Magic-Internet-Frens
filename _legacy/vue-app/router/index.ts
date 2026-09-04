import { createRouter, createWebHashHistory } from "vue-router";
import type { RouteRecordRaw } from "vue-router";
import type { NavigationGuardNext, RouteLocationNormalized } from "vue-router";

function removeQueryParams(
  to: RouteLocationNormalized,
  from: RouteLocationNormalized,
  next: NavigationGuardNext
) {
  if (Object.keys(to.query).length)
    next({ path: to.path, query: {}, hash: to.hash });
  else next();
}

const routes: Array<RouteRecordRaw> = [
  {
    path: "/",
    name: "Landing",
    component: () => import("@/views/Landing.vue"),
    meta: { isLanding: true },
  },
  {
    path: "/cauldrons",
    name: "Cauldrons",
    component: () => import("@/views/Cauldrons.vue"),
  },
  {
    path: "/app",
    redirect: "/cauldrons",
  },
  {
    path: "/market/:chainId/:cauldronId",
    name: "Market",
    component: () => import("@/views/Market.vue"),
  },
  {
    path: "/staking",
    name: "StakeFren",
    component: () => import("@/views/stake/Spell.vue"),
  },
  {
    path: "/spell",
    redirect: "/staking",
  },
  {
    path: "/my-positions",
    name: "MyPositions",
    component: () => import("@/views/MyPositions.vue"),
  },
  {
    path: "/swap",
    name: "Swap",
    component: () => import("@/views/MimSwap.vue"),
  },
  {
    path: "/nft",
    name: "NFT",
    component: () => import("@/views/NFTMint.vue"),
  },
  {
    path: "/tenderlyTap",
    name: "TenderlyTap",
    component: () => import("@/views/TenderlyTap.vue"),
  },
  {
    path: "/:catchAll(.*)",
    redirect: "/",
  },
];

const router = createRouter({
  history: createWebHashHistory(),
  routes,
  scrollBehavior() {
    return { top: 0 };
  },
});

export default router;
