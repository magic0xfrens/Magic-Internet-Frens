import type { FC } from "react";
import { useWallet } from "@/hooks/useWallet";

interface ConnectWalletPromptProps {
  message?: string;
}

const ConnectWalletPrompt: FC<ConnectWalletPromptProps> = ({
  message = "Connect your wallet to continue",
}) => {
  const { openConnectModal } = useWallet();

  return (
    <div
      className="connect-wallet-prompt"
      style={{
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        gap: "20px",
        padding: "60px 24px",
        borderRadius: "16px",
        border: "1px solid rgba(247, 147, 26, 0.15)",
        background:
          "linear-gradient(146deg, rgba(0, 10, 35, 0.07) 0%, rgba(247, 147, 26, 0.05) 101.49%)",
        backdropFilter: "blur(12.5px)",
        textAlign: "center",
      }}
    >
      <svg
        width="48"
        height="48"
        viewBox="0 0 24 24"
        fill="none"
        stroke="rgba(255,255,255,0.3)"
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        <rect x="2" y="6" width="20" height="14" rx="2" />
        <path d="M2 10h20" />
        <path d="M16 14h2" />
      </svg>

      <p
        style={{
          color: "rgba(255, 255, 255, 0.6)",
          fontSize: "16px",
          lineHeight: "1.5",
          margin: 0,
        }}
      >
        {message}
      </p>

      <button
        onClick={openConnectModal}
        style={{
          padding: "12px 32px",
          borderRadius: "10px",
          border: "none",
          background: "linear-gradient(90deg, #d5fd51, #f5c542)",
          color: "#0c0f1c",
          fontSize: "15px",
          fontWeight: 600,
          fontFamily: "Poppins, sans-serif",
          cursor: "pointer",
          transition: "opacity 0.2s ease",
        }}
        onMouseEnter={(e) => {
          (e.target as HTMLButtonElement).style.opacity = "0.85";
        }}
        onMouseLeave={(e) => {
          (e.target as HTMLButtonElement).style.opacity = "1";
        }}
      >
        Connect Wallet
      </button>
    </div>
  );
};

export default ConnectWalletPrompt;
