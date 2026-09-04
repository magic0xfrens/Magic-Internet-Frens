// Window type extensions for Web3 wallets
// NOTE: We do NOT declare window.ethereum here to avoid conflicts with wallet extensions
// Instead, use type assertions where needed: (window as any).ethereum

export interface EthereumProvider {
  isMetaMask?: boolean;
  isRabby?: boolean;
  isCoinbaseWallet?: boolean;
  isTrust?: boolean;
  request: (args: { method: string; params?: any[] }) => Promise<any>;
  on: (event: string, callback: (params: any) => void) => void;
  removeListener?: (event: string, callback: (params: any) => void) => void;
  selectedAddress?: string;
  chainId?: string;
}

declare global {
  interface WindowEventMap {
    'ethereum#initialized': CustomEvent;
  }
}
