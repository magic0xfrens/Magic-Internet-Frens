import { useCallback, useState } from "react";
import toast from "react-hot-toast";

/**
 * PHASE 2 STUB — the Robinhood FrenMarket contract has no EVM equivalent deployed on
 * Robinhood Chain yet. This preserves the hook's public shape so the Marketplace
 * UI compiles and renders an empty state. Wire real functions once a Solidity
 * marketplace contract is deployed.
 */

export interface MarketListing {
  tokenId: bigint;
  priceSats: bigint;
  classIdx: number;
  bodyIdx: number;
  faceIdx: number;
  itemIdx: number;
  bodyFile: string;
  faceFile: string;
  itemFile: string;
  sellerAddress: string;
  reservedBy: bigint;
  reserveExpiry: bigint;
}

export interface ReservationStatus {
  reserved: boolean;
  reservedByMe: boolean;
  expired: boolean;
  blocksRemaining: number;
  expiryBlock: bigint;
  currentBlock: bigint;
  listingExists: boolean;
}

export type ApprovalStatus =
  | "unknown"
  | "checking"
  | "approved"
  | "not_approved"
  | "approving"
  | "waiting_confirm";

const EMPTY_RESERVATION: ReservationStatus = {
  reserved: false,
  reservedByMe: false,
  expired: false,
  blocksRemaining: -1,
  expiryBlock: 0n,
  currentBlock: 0n,
  listingExists: false,
};

function notAvailable() {
  toast.error("Marketplace is coming soon on Robinhood Chain");
}

export function useMarketplace() {
  const [listings] = useState<MarketListing[]>([]);
  const [loading] = useState(false);
  const [error] = useState<string | null>(null);
  const [approvalStatus] = useState<ApprovalStatus>("unknown");
  const [buyerFeeBps] = useState<bigint>(690n);

  const refresh = useCallback(async () => {}, []);
  const listNFT = useCallback(async (_tokenId: bigint, _priceSats: bigint) => {
    notAvailable();
  }, []);
  const reserveBuy = useCallback(async (_tokenId: bigint): Promise<boolean> => {
    notAvailable();
    return false;
  }, []);
  const claimReserved = useCallback(
    async (
      _tokenId: bigint,
      _priceSats: bigint,
      _sellerAddress: string,
      _feeRate?: number,
    ): Promise<boolean> => {
      notAvailable();
      return false;
    },
    [],
  );
  const checkReservation = useCallback(
    async (_tokenId: bigint): Promise<ReservationStatus> => EMPTY_RESERVATION,
    [],
  );
  const cancelListing = useCallback(async (_tokenId: bigint) => {
    notAvailable();
  }, []);
  const cancelReservation = useCallback(async (_tokenId: bigint) => {
    notAvailable();
  }, []);
  const checkApproval = useCallback(async () => {}, []);
  const approveMarketplace = useCallback(async () => {
    notAvailable();
  }, []);

  return {
    listings,
    loading,
    error,
    refresh,
    listNFT,
    reserveBuy,
    claimReserved,
    checkReservation,
    cancelListing,
    cancelReservation,
    approvalStatus,
    checkApproval,
    approveMarketplace,
    buyerFeeBps,
    contractReady: false,
  };
}
