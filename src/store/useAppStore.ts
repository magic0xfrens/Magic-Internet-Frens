import { create } from "zustand";
import { ACTIVE_CHAIN } from "@/config/chains";
import type { ProtocolStats } from "@/types/global";

type Network = typeof ACTIVE_CHAIN;

const PENDING_MINTS_KEY = "magicfrens_pending_mints";
const PENDING_BUYS_KEY = "magicfrens_pending_buys";
const PENDING_LISTINGS_KEY = "magicfrens_pending_listings";
const PENDING_RESERVATIONS_KEY = "magicfrens_pending_reservations";
const STALE_THRESHOLD_MS = 30 * 60 * 1000; // 30 minutes

export interface PendingMint {
  tokenId: string; // stored as string for JSON serialization
  txHash: string;
  timestamp: number;
}

export interface PendingBuy {
  tokenId: string;
  priceSats: string; // stored as string for JSON serialization
  timestamp: number;
}

export interface PendingListing {
  tokenId: string;
  priceSats: string;
  timestamp: number;
}

export interface PendingReservation {
  tokenId: string;
  timestamp: number;
}

function loadPendingMints(): PendingMint[] {
  try {
    const raw = localStorage.getItem(PENDING_MINTS_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as PendingMint[];
    // Filter out stale entries on load
    const now = Date.now();
    return parsed.filter((m) => now - m.timestamp < STALE_THRESHOLD_MS);
  } catch {
    return [];
  }
}

function savePendingMints(mints: PendingMint[]) {
  try {
    localStorage.setItem(PENDING_MINTS_KEY, JSON.stringify(mints));
  } catch {
    // localStorage full or unavailable
  }
}

function loadPendingBuys(): PendingBuy[] {
  try {
    const raw = localStorage.getItem(PENDING_BUYS_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as PendingBuy[];
    const now = Date.now();
    return parsed.filter((b) => now - b.timestamp < STALE_THRESHOLD_MS);
  } catch {
    return [];
  }
}

function savePendingBuys(buys: PendingBuy[]) {
  try {
    localStorage.setItem(PENDING_BUYS_KEY, JSON.stringify(buys));
  } catch {
    // localStorage full or unavailable
  }
}

function loadPendingListings(): PendingListing[] {
  try {
    const raw = localStorage.getItem(PENDING_LISTINGS_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as PendingListing[];
    const now = Date.now();
    return parsed.filter((l) => now - l.timestamp < STALE_THRESHOLD_MS);
  } catch {
    return [];
  }
}

function savePendingListings(listings: PendingListing[]) {
  try {
    localStorage.setItem(PENDING_LISTINGS_KEY, JSON.stringify(listings));
  } catch {
    // localStorage full or unavailable
  }
}

function loadPendingReservations(): PendingReservation[] {
  try {
    const raw = localStorage.getItem(PENDING_RESERVATIONS_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as PendingReservation[];
    const now = Date.now();
    return parsed.filter((r) => now - r.timestamp < STALE_THRESHOLD_MS);
  } catch {
    return [];
  }
}

function savePendingReservations(reservations: PendingReservation[]) {
  try {
    localStorage.setItem(PENDING_RESERVATIONS_KEY, JSON.stringify(reservations));
  } catch {
    // localStorage full or unavailable
  }
}

interface AppState {
  // Network
  network: Network;
  setNetwork: (network: Network) => void;

  // UI
  sidebarOpen: boolean;
  toggleSidebar: () => void;
  setSidebarOpen: (open: boolean) => void;

  // Cauldron nav badges — published by TheCauldron so the left rail can show
  // live counters (open perps / open proposals / iteration) without the rail
  // having to re-read the chain itself.
  cauldronNav: CauldronNav;
  setCauldronNav: (nav: Partial<CauldronNav>) => void;

  // Same idea for the MiFrens vault — the rail shows how many frens and
  // collectibles the wallet holds without mounting the vault itself.
  mifrensNav: MifrensNav;
  setMifrensNav: (nav: Partial<MifrensNav>) => void;

  // Protocol Stats
  protocolStats: ProtocolStats | null;
  setProtocolStats: (stats: ProtocolStats | null) => void;

  // Notifications
  notifications: AppNotification[];
  addNotification: (notification: Omit<AppNotification, "id" | "timestamp">) => void;
  removeNotification: (id: string) => void;
  clearNotifications: () => void;

  // Pending Mints
  pendingMints: PendingMint[];
  addPendingMint: (mint: PendingMint) => void;
  removePendingMint: (txHash: string) => void;
  removePendingMintByTokenId: (tokenId: string) => void;
  clearStalePendingMints: () => void;

  // Pending Buys
  pendingBuys: PendingBuy[];
  addPendingBuy: (buy: PendingBuy) => void;
  removePendingBuy: (tokenId: string) => void;
  clearStalePendingBuys: () => void;

  // Pending Listings
  pendingListings: PendingListing[];
  addPendingListing: (listing: PendingListing) => void;
  removePendingListing: (tokenId: string) => void;
  clearStalePendingListings: () => void;

  // Pending Reservations
  pendingReservations: PendingReservation[];
  addPendingReservation: (reservation: PendingReservation) => void;
  removePendingReservation: (tokenId: string) => void;
  clearStalePendingReservations: () => void;
}

export interface CauldronNav {
  /** False until a generation is live — the rail hides Leverage until then,
      because that view renders nothing without a summoned brew. */
  summoned: boolean;
  /** Open perp positions across the book (drives the Leverage badge). */
  perps: number;
  /** Live governance proposals. */
  proposals: number;
  /** Current iteration number — 0 until the first generation is summoned. */
  gen: number;
}

export interface MifrensNav {
  /** Frens held in the genesis MiFrens collection (OG + volume-minted). */
  frens: number;
  /** Forged creatures + Liquidatoor badges combined. */
  collectibles: number;
}

export interface AppNotification {
  id: string;
  type: "success" | "error" | "warning" | "info";
  title: string;
  message: string;
  timestamp: number;
  txHash?: string;
}

let notificationId = 0;

export const useAppStore = create<AppState>((set) => ({
  // Network — active chain (Robinhood on mainnet, Sepolia on testnet)
  network: ACTIVE_CHAIN,
  setNetwork: (network) => set({ network }),

  // UI
  sidebarOpen: false,
  toggleSidebar: () => set((s) => ({ sidebarOpen: !s.sidebarOpen })),
  setSidebarOpen: (open) => set({ sidebarOpen: open }),

  // Cauldron nav badges
  cauldronNav: { summoned: false, perps: 0, proposals: 0, gen: 0 },
  setCauldronNav: (nav) => set((s) => ({ cauldronNav: { ...s.cauldronNav, ...nav } })),

  // MiFrens nav badges
  mifrensNav: { frens: 0, collectibles: 0 },
  setMifrensNav: (nav) => set((s) => ({ mifrensNav: { ...s.mifrensNav, ...nav } })),

  // Protocol Stats
  protocolStats: null,
  setProtocolStats: (stats) => set({ protocolStats: stats }),

  // Notifications
  notifications: [],
  addNotification: (notification) =>
    set((s) => ({
      notifications: [
        ...s.notifications,
        {
          ...notification,
          id: `notif-${++notificationId}`,
          timestamp: Date.now(),
        },
      ],
    })),
  removeNotification: (id) =>
    set((s) => ({
      notifications: s.notifications.filter((n) => n.id !== id),
    })),
  clearNotifications: () => set({ notifications: [] }),

  // Pending Mints (persisted to localStorage)
  pendingMints: loadPendingMints(),
  addPendingMint: (mint) =>
    set((s) => {
      const updated = [...s.pendingMints, mint];
      savePendingMints(updated);
      return { pendingMints: updated };
    }),
  removePendingMint: (txHash) =>
    set((s) => {
      const updated = s.pendingMints.filter((m) => m.txHash !== txHash);
      savePendingMints(updated);
      return { pendingMints: updated };
    }),
  removePendingMintByTokenId: (tokenId) =>
    set((s) => {
      const updated = s.pendingMints.filter((m) => m.tokenId !== tokenId);
      savePendingMints(updated);
      return { pendingMints: updated };
    }),
  clearStalePendingMints: () =>
    set((s) => {
      const now = Date.now();
      const updated = s.pendingMints.filter(
        (m) => now - m.timestamp < STALE_THRESHOLD_MS,
      );
      savePendingMints(updated);
      return { pendingMints: updated };
    }),

  // Pending Buys (persisted to localStorage)
  pendingBuys: loadPendingBuys(),
  addPendingBuy: (buy) =>
    set((s) => {
      const updated = [...s.pendingBuys, buy];
      savePendingBuys(updated);
      return { pendingBuys: updated };
    }),
  removePendingBuy: (tokenId) =>
    set((s) => {
      const updated = s.pendingBuys.filter((b) => b.tokenId !== tokenId);
      savePendingBuys(updated);
      return { pendingBuys: updated };
    }),
  clearStalePendingBuys: () =>
    set((s) => {
      const now = Date.now();
      const updated = s.pendingBuys.filter(
        (b) => now - b.timestamp < STALE_THRESHOLD_MS,
      );
      savePendingBuys(updated);
      return { pendingBuys: updated };
    }),

  // Pending Listings (persisted to localStorage)
  pendingListings: loadPendingListings(),
  addPendingListing: (listing) =>
    set((s) => {
      const updated = [...s.pendingListings, listing];
      savePendingListings(updated);
      return { pendingListings: updated };
    }),
  removePendingListing: (tokenId) =>
    set((s) => {
      const updated = s.pendingListings.filter((l) => l.tokenId !== tokenId);
      savePendingListings(updated);
      return { pendingListings: updated };
    }),
  clearStalePendingListings: () =>
    set((s) => {
      const now = Date.now();
      const updated = s.pendingListings.filter(
        (l) => now - l.timestamp < STALE_THRESHOLD_MS,
      );
      savePendingListings(updated);
      return { pendingListings: updated };
    }),

  // Pending Reservations (persisted to localStorage)
  pendingReservations: loadPendingReservations(),
  addPendingReservation: (reservation) =>
    set((s) => {
      const updated = [...s.pendingReservations, reservation];
      savePendingReservations(updated);
      return { pendingReservations: updated };
    }),
  removePendingReservation: (tokenId) =>
    set((s) => {
      const updated = s.pendingReservations.filter((r) => r.tokenId !== tokenId);
      savePendingReservations(updated);
      return { pendingReservations: updated };
    }),
  clearStalePendingReservations: () =>
    set((s) => {
      const now = Date.now();
      const updated = s.pendingReservations.filter(
        (r) => now - r.timestamp < STALE_THRESHOLD_MS,
      );
      savePendingReservations(updated);
      return { pendingReservations: updated };
    }),
}));
