import { useState, useEffect } from 'react';
import { ExternalLink } from 'lucide-react';

import { ROBINHOOD_CHAIN_ID, ROBINHOOD_RPC_URL, ROBINHOOD_EXPLORER_URL } from '@/config/chains';
import metamaskLogo from '@/assets/images/connect/io.metamask.png';
import rabbyLogo from '@/assets/images/connect/io.rabby.png';
import coinbaseLogo from '@/assets/images/connect/coinbaseWalletSDK.png';
import defaultWalletLogo from '@/assets/images/connect/default-wallet.png';

interface WalletOption {
  name: string;
  logo: string;
  detected: boolean;
  connectFn: () => Promise<void>;
  downloadUrl?: string;
}

interface WalletSelectorProps {
  onConnect: (address: string) => void;
  chainId: number;
}

export default function WalletSelector({ onConnect, chainId }: WalletSelectorProps) {
  const [wallets, setWallets] = useState<WalletOption[]>([]);
  const [connecting, setConnecting] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    detectWallets();
  }, []);

  const detectWallets = () => {
    const detectedWallets: WalletOption[] = [];

    // MetaMask
    if ((window as any).ethereum?.isMetaMask && !(window as any).ethereum?.isRabby) {
      detectedWallets.push({
        name: 'MetaMask',
        logo: metamaskLogo,
        detected: true,
        connectFn: async () => connectWallet('MetaMask'),
      });
    }

    // Rabby
    if ((window as any).ethereum?.isRabby) {
      detectedWallets.push({
        name: 'Rabby',
        logo: rabbyLogo,
        detected: true,
        connectFn: async () => connectWallet('Rabby'),
      });
    }

    // Coinbase Wallet
    if ((window as any).ethereum?.isCoinbaseWallet) {
      detectedWallets.push({
        name: 'Coinbase',
        logo: coinbaseLogo,
        detected: true,
        connectFn: async () => connectWallet('Coinbase'),
      });
    }

    // Trust Wallet
    if ((window as any).ethereum?.isTrust) {
      detectedWallets.push({
        name: 'Trust Wallet',
        logo: defaultWalletLogo,
        detected: true,
        connectFn: async () => connectWallet('Trust'),
      });
    }

    // Generic EVM wallet
    if ((window as any).ethereum && detectedWallets.length === 0) {
      detectedWallets.push({
        name: 'Browser Wallet',
        logo: defaultWalletLogo,
        detected: true,
        connectFn: async () => connectWallet('Generic'),
      });
    }

    // Add download options for wallets not detected
    if (!(window as any).ethereum?.isMetaMask) {
      detectedWallets.push({
        name: 'MetaMask',
        logo: metamaskLogo,
        detected: false,
        connectFn: async () => {},
        downloadUrl: 'https://metamask.io/download/',
      });
    }

    if (!(window as any).ethereum?.isRabby) {
      detectedWallets.push({
        name: 'Rabby',
        logo: rabbyLogo,
        detected: false,
        connectFn: async () => {},
        downloadUrl: 'https://rabby.io/',
      });
    }

    setWallets(detectedWallets);
  };

  const connectWallet = async (walletName: string) => {
    setConnecting(walletName);
    setError(null);

    try {
      if (!(window as any).ethereum) {
        throw new Error('No Web3 wallet detected');
      }

      // Request account access
      const accounts = await (window as any).ethereum.request({
        method: 'eth_requestAccounts',
      });

      if (!accounts || accounts.length === 0) {
        throw new Error('No accounts found');
      }

      // Check chain ID
      const currentChainIdHex = await (window as any).ethereum.request({
        method: 'eth_chainId',
      });
      const currentChainId = parseInt(currentChainIdHex, 16);

      if (currentChainId !== chainId) {
        // Attempt to switch network
        try {
          await (window as any).ethereum.request({
            method: 'wallet_switchEthereumChain',
            params: [{ chainId: `0x${chainId.toString(16)}` }],
          });
        } catch (switchError: any) {
          if (switchError.code === 4902) {
            const networkConfigs: Record<number, any> = {
              1: {
                chainId: '0x1',
                chainName: 'Ethereum',
                nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
                rpcUrls: ['https://eth.llamarpc.com'],
                blockExplorerUrls: ['https://etherscan.io'],
              },
              8453: {
                chainId: '0x2105',
                chainName: 'Base',
                nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
                rpcUrls: ['https://mainnet.base.org'],
                blockExplorerUrls: ['https://basescan.org'],
              },
              // Robinhood Chain — the mainnet target. Lets a wallet auto-add it
              // (error 4902) when the user isn't on it yet.
              [ROBINHOOD_CHAIN_ID]: {
                chainId: `0x${ROBINHOOD_CHAIN_ID.toString(16)}`,
                chainName: 'Robinhood Chain',
                nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
                rpcUrls: [ROBINHOOD_RPC_URL],
                blockExplorerUrls: [ROBINHOOD_EXPLORER_URL],
              },
              // Sepolia — testnet build.
              11155111: {
                chainId: '0xaa36a7',
                chainName: 'Sepolia',
                nativeCurrency: { name: 'Sepolia Ether', symbol: 'ETH', decimals: 18 },
                rpcUrls: ['https://ethereum-sepolia-rpc.publicnode.com'],
                blockExplorerUrls: ['https://sepolia.etherscan.io'],
              },
            };

            const networkConfig = networkConfigs[chainId];
            if (networkConfig) {
              await (window as any).ethereum.request({
                method: 'wallet_addEthereumChain',
                params: [networkConfig],
              });
            }
          } else {
            throw switchError;
          }
        }
      }

      // Success - return address
      onConnect(accounts[0]);
    } catch (err: any) {
      console.error('Wallet connection error:', err);
      setError(err.message || 'Failed to connect wallet');
    } finally {
      setConnecting(null);
    }
  };

  return (
    <div className="ws-root">
      {error && (
        <div className="ws-error">
          {error}
        </div>
      )}

      <div className="ws-grid">
        {wallets.map((wallet) => (
          <button
            key={wallet.name + (wallet.detected ? '-detected' : '-install')}
            className={`ws-card ${!wallet.detected ? 'ws-card--dim' : ''}`}
            onClick={wallet.detected ? wallet.connectFn : undefined}
            disabled={!wallet.detected || connecting === wallet.name}
          >
            <img src={wallet.logo} alt={wallet.name} className="ws-logo" />
            <span className="ws-name">{wallet.name}</span>
            {connecting === wallet.name && (
              <span className="ws-spinner" />
            )}
            {!wallet.detected && wallet.downloadUrl && (
              <a
                href={wallet.downloadUrl}
                target="_blank"
                rel="noopener noreferrer"
                className="ws-install"
                onClick={(e) => e.stopPropagation()}
              >
                <ExternalLink size={12} />
                Install
              </a>
            )}
          </button>
        ))}
      </div>

      <style>{`
        .ws-root {
          /* no wrapper background — inherits from parent */
        }

        .ws-error {
          padding: 10px 14px;
          background: rgba(239, 68, 68, 0.08);
          border: 1px solid rgba(239, 68, 68, 0.2);
          border-radius: var(--r-sm);
          color: #DC2626;
          font-family: 'DM Sans', sans-serif;
          font-size: 12px;
          margin-bottom: 12px;
        }

        .ws-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(100px, 1fr));
          gap: 8px;
        }

        .ws-card {
          position: relative;
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 6px;
          padding: 12px 8px;
          background: white;
          border: 2px solid rgba(42, 31, 84, 0.12);
          border-radius: var(--r-sm);
          cursor: pointer;
          transition: all 0.2s ease;
          font-family: inherit;
        }

        .ws-card:hover:not(:disabled):not(.ws-card--dim) {
          border-color: #564785;
          transform: translateY(-2px);
          box-shadow: 0 4px 12px rgba(42, 31, 84, 0.1);
        }

        .ws-card--dim {
          opacity: 0.5;
          cursor: default;
        }

        .ws-card:disabled {
          opacity: 0.6;
          cursor: wait;
        }

        .ws-logo {
          width: 30px;
          height: 30px;
          border-radius: var(--r-chip);
          object-fit: contain;
        }

        .ws-name {
          font-family: 'Fredoka', sans-serif;
          font-size: 12px;
          font-weight: 600;
          color: #2A1F54;
        }

        .ws-spinner {
          position: absolute;
          top: 8px;
          right: 8px;
          width: 14px;
          height: 14px;
          border: 2px solid rgba(86, 71, 133, 0.2);
          border-top-color: #564785;
          border-radius: 50%;
          animation: ws-spin 0.6s linear infinite;
        }

        @keyframes ws-spin {
          to { transform: rotate(360deg); }
        }

        .ws-install {
          display: inline-flex;
          align-items: center;
          gap: 4px;
          padding: 3px 8px;
          background: rgba(86, 71, 133, 0.08);
          border-radius: var(--r-chip);
          color: #564785;
          font-family: 'Fredoka', sans-serif;
          font-size: 10px;
          font-weight: 600;
          text-decoration: none;
          transition: background 0.2s;
        }

        .ws-install:hover {
          background: rgba(86, 71, 133, 0.15);
        }

        @media (max-width: 640px) {
          .ws-grid {
            grid-template-columns: repeat(auto-fill, minmax(90px, 1fr));
            gap: 8px;
          }
          .ws-card { padding: 12px 8px; }
          .ws-logo { width: 30px; height: 30px; }
          .ws-name { font-size: 11px; }
        }
      `}</style>
    </div>
  );
}
