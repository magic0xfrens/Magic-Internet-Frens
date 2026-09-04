// @ts-nocheck
import { usePrivy } from "@privy-io/react-auth";

const buttonStyle = {
  padding: "10px 20px",
  fontSize: "13px",
  fontWeight: "bold",
  cursor: "pointer",
  outline: "none",
  //border: "1px solid #ddd",
  borderRadius: "4px",
  margin: "5px",
  backgroundColor: "white", // match the input field color
};
const modalBackdropStyle = {
  position: "fixed", // Fixed position to cover the whole screen
  top: 0,
  left: 0,
  right: 0,
  bottom: 0,
  backgroundColor: "rgba(0, 0, 0, 0.5)", // Semi-transparent black
  display: "flex",
  alignItems: "center", // Center the modal vertically
  justifyContent: "center", // Center the modal horizontally
  zIndex: 1000, // Ensure it's on top of other elements
};

const modalContentStyle = {
  fontFamily: "sans-serif",
  color: "#212145",
  width: "300px",
  backgroundColor: "#FFF", // White background
  padding: "20px",
  borderRadius: "10px",
  boxShadow: "0 4px 8px rgba(0, 0, 0, 0.1)", // Add some shadow
  zIndex: 1001, // Above the backdrop
};

const closeButtonStyle = {
  position: "absolute",
  top: "10px",
  right: "10px",
  cursor: "pointer",
  fontSize: "20px",
  border: "none",
  background: "none",
};

const Modal = ({ closeModal }) => {
  const { ready, authenticated, user, logout, exportWallet } = usePrivy();

  const copyToClipboard = async () => {
    if (user?.wallet?.address) {
      try {
        if (user?.wallet?.address)
          await navigator.clipboard.writeText(user?.wallet?.address);
        console.log("Address copied to clipboard:", user?.wallet?.address);
        // Optionally, you can show a message to the user indicating success
      } catch (error) {
        console.error("Failed to copy:", error);
        // Handle error (e.g., show an error message to the user)
      }
    }
  };

  // Check that your user is authenticated
  const isAuthenticated = ready && authenticated;

  // Check that your user has an embedded wallet
  const hasEmbeddedWallet = !!user?.linkedAccounts.find(
    (account) => account.type === "wallet" && account.walletClient === "privy"
  );
  return (
    <div style={modalBackdropStyle} onClick={closeModal}>
      <div style={modalContentStyle} className="rpgui-container framed">
        <p>Do you want to export the private key of this address?</p>
        <button
          className="rpgui-button"
          onClick={exportWallet}
          disabled={!isAuthenticated || !hasEmbeddedWallet}
          style={buttonStyle}
        >
          Export my wallet
        </button>
        <button
          className="rpgui-button"
          onClick={copyToClipboard}
          style={buttonStyle}
        >
          Copy address
        </button>
        <button className="rpgui-button" onClick={logout} style={buttonStyle}>
          Log Out
        </button>
      </div>
    </div>
  );
};

export default Modal;
