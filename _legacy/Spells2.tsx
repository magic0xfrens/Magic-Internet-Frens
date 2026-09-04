// @ts-nocheck
import React, { useState, useEffect } from "react";
import {
  usePrivy,
  useWallets,
  UnsignedTransactionRequest,
} from "@privy-io/react-auth";
import "./Styles.css"; // Import your CSS file here
import logo from "./assets/Logo.svg";
import cauldron from "./assets/cauldron.webp";
import skull from "./assets/skull.webp";
import potion from "./assets/Potion.svg";
import cauldronAbi from "./miCauldron.json";
import "./cauldron.css";
import eth from "./assets/EthLogo.svg";
import { ethers, Contract } from "ethers";
import * as dotenv from "dotenv";
import leaderboardAbi from "./LeaderBoard.json";
import contractAddresses from "./Contracts.json";
import fren from "./assets/PlebFren.svg";
import Image from "next/image";
const Cauldron = () => {
  const { login, ready, logout, user, sendTransaction } = usePrivy();
  const { authenticated, linkTwitter } = usePrivy();

  const { wallets } = useWallets();
  const [embeddedWallet, setEmbeddedWallet] = useState<any>();
  const [walletBalance, setWalletBalance] = useState<any>(0);

  const [contract, setContract] = useState<any>();

  const [leaderboard, setLeader] = useState();

  const [chainID, setchainID] = useState("0x2105");
  // State for modal
  const [isModalOpen, setModalOpen] = useState(false);
  const [pendingRewards, setPendingRewards] = useState(false);
  const [isModalRemoveOpen, setModalRemoveOpen] = useState(false);
  const [ethValue, setEthValue] = useState("");
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
  const inputGroupStyle = {
    display: "flex",
    alignItems: "center",
    justifyContent: "flex-end",
    padding: "10px",
    border: "1px solid #ddd",
    backgroundColor: "#f4f4f9", // Light grey background for the stake container

    boxShadow: "0 2px 4px rgba(0, 0, 0, 0.2)", // Softer shadow
    borderRadius: "5px",
    width: "100%", // full width of the parent container
    maxWidth: "300px", // maximum width of the input group
    margin: "20px 0", // margin around the input group for spacing
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
  const buttonContainerStyle = {
    width: "100px",
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
  };

  const stakeButtonRowStyle = {
    display: "flex",
    justifyContent: "center",
    width: "100%", // Ensure the container takes up the full width
    marginBottom: "10px", // Space between the row of buttons and the single button below
  };

  const stakeButtonStyle = {
    backgroundColor: "#212145", // button color
    color: "white",
    border: "none",

    padding: "10px 20px", // reduce padding
    fontSize: "0.7rem",
    cursor: "pointer",
    textAlign: "center",
    outline: "none",
    boxShadow: "0 2px 4px rgba(0, 0, 0, 0.2)", // softer shadow
    width: "100%", // make buttons wider
    marginLeft: "25px", // space around buttons, adjust as needed to fit your layout
    backgroundImage: `url("/dist/img/button.png")`,
    backgroundSize: "100% 100%",
    backgroundRepeat: " no-repeat",
  };
  const smallButtonStyle = {
    backgroundColor: "#212145", // button color
    color: "white",
    border: "none",
    borderRadius: "15px", // rounded corners
    padding: "10px 20px", // reduce padding
    fontSize: "1rem",
    cursor: "pointer",
    outline: "none",
    boxShadow: "0 2px 4px rgba(0, 0, 0, 0.2)", // softer shadow
    width: "28%", // make buttons wider
    margin: "0 5px", // space around buttons, adjust as needed to fit your layout
  };
  const playerListStyle = {
    display: "flex",
    flexDirection: "column",
    position: "relative",
    alignItems: "center",
    width: "100vw",
    maxHeight: "60vh", // Adjust this value as needed
    overflowY: "auto", // Enable vertical scrolling

    margin: "0 auto", // Center the container if needed
  };

  const playerItemStyle = {
    position: "relative",
    display: "flex",
    justifyContent: "space-between",
    alignItems: "center",
    width: "300px",
    margin: "10px 0",
    padding: "10px",
    backgroundColor: "#EEE", // Change as needed
    borderRadius: "10px",
  };

  const playerInfoStyle = {
    display: "flex",
    flexDirection: "column",
    alignItems: "flex-start",
  };

  const containerStyle = {
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    justifyContent: "flex-start",
    height: "55vh", // Adjust height to 'auto' if content should dictate the container size
    textAlign: "center",
    fontFamily: "sans-serif",
    width: "95%", // Full width
    maxWidth: "480px", // Max-width for mobile screens
    margin: "0 auto", // Center the container
    marginTop: "1%", //
    backgroundColor: "#f4f4f9", // Light grey background for the stake container
    borderRadius: "10px",

    overflow: "auto",
    overflowX: "hidden", // Prevent overflow
    position: "relative", // Position relative for absolute children
  };

  const headerStyle = {
    display: "flex",
    alignItems: "left", // align items vertically
    justifyContent: "center", // center items horizontally
    width: "100%", // take up full container width
    marginTop: "3vh", // push down from the top
    marginBottom: "3vh", // push down from the top
  };

  const logoStyle = {
    width: "75px", // Adjust logo size
    marginRight: "1rem", // Space to the right of the logo
  };
  const frenStyle = {
    width: "60px", // Adjust logo size
    marginLeft: "2rem", // Space to the right of the logo
    marginBottom: "1rem", // Space to the right of the logo
  };

  const textStyle = {
    fontSize: "48px",

    textAlign: "left", // align text to the left
  };

  useEffect(() => {
    if (!ready) {
      return;
    } else {
      setUp();
    }
  }, [ready, wallets, chainID]);
  const leaderboardAddress = contractAddresses[chainID].leaderboard;
  async function setUp() {
    const embeddedWallet = wallets.find(
      (wallet) => wallet.walletClientType === "privy"
    );

    if (embeddedWallet) {
      const provider = await embeddedWallet.getEthereumProvider();
      await provider.request({
        method: "wallet_switchEthereumChain",
        params: [{ chainId: chainID }],
      });
      const ethProvider = new ethers.providers.Web3Provider(provider);
      const walletBalance = await ethProvider.getBalance(
        embeddedWallet.address
      );
      const ethStringAmount = Number(ethers.utils.formatEther(walletBalance));
      setEmbeddedWallet(embeddedWallet);

      setWalletBalance(Math.round(ethStringAmount * 10000) / 10000);
      setEthValue(Math.round(((0.5 * ethStringAmount) / 100) * 1000) / 1000);
      const ca = new Contract(
        leaderboardAddress,
        leaderboardAbi,
        ethProvider.getSigner() as any
      );

      setContract(ca);
      const pending = await ca?.getTokensOrderedByXP();
      console.log("pending", pending[1]);
      setLeader(pending[1]);
    }
  }
  const openModal = () => {
    setModalOpen(true);
  };
  const openModalRemove = () => {
    setModalRemoveOpen(true);
  };
  const closeModalRemove = () => {
    setModalRemoveOpen(false);
  };

  const closeModal = () => {
    setModalOpen(false);
  };
  const Modal = ({ closeModal, children }) => {
    const handleOverlayClick = (e) => {
      if (e.target === e.currentTarget) {
        closeModal();
      }
    };

    return (
      <div style={modalBackdropStyle} onClick={handleOverlayClick}>
        <div style={modalContentStyle}>{children}</div>
      </div>
    );
  };

  const claimRewards = async () => {
    // Implement your code submission logic here

    const gasLimit = await contract.estimateGas.claimRewards();
    console.log("gas", gasLimit);

    const txUnsigned =
      (await contract.populateTransaction.claimRewards()) as UnsignedTransactionRequest;
    const txUiConfig = {
      header: "Rebalance your Cauldron",
      description: "Cauldron will rebalance to +/- 30% of current price",
      buttonText: "Rebalance",
    };

    const res = await sendTransaction(
      {
        ...txUnsigned,
        chainId: parseInt("0x5", 16),
        gasLimit: gasLimit.toNumber(),
      },
      txUiConfig
    );
    console.log(res);
    setUp();
  };

  return (
    <div style={containerStyle} className="rpgui-content">
      <div style={containerStyle} className="rpgui-container framed">
        {leaderboard?.map((address, index) => (
          <div key={index}>
            <div
              style={playerItemStyle}
              className="rpgui-container framed-grey"
            >
              <div style={playerInfoStyle}>
                <span>{address.substring(0, 6)}...</span>
                <span>XP:</span>
                <div className="rpgui-progress" style={{ height: "20px" }}>
                  <div
                    className="rpgui-progress-track "
                    style={{ height: "20px", left: "10px", width: "90px" }}
                  />
                  <div
                    className="rpgui-progress-fill blue "
                    style={{ width: "100%", height: "70%", top: "4px" }}
                  />
                  <div
                    className="rpgui-progress-left-edge "
                    style={{ height: "20px", width: "20px" }}
                  />

                  <div
                    className="rpgui-progress-right-edge "
                    style={{ height: "20px", width: "20px" }}
                  />
                </div>
                <span>HP:</span>
                <div className="rpgui-progress" style={{ height: "20px" }}>
                  <div
                    className="rpgui-progress-track "
                    style={{ height: "20px", left: "10px", width: "90px" }}
                  />
                  <div
                    className="rpgui-progress-fill green "
                    style={{ width: "100%", height: "70%", top: "4px" }}
                  />
                  <div
                    className="rpgui-progress-left-edge "
                    style={{ height: "20px", width: "20px" }}
                  />

                  <div
                    className="rpgui-progress-right-edge "
                    style={{ height: "20px", width: "20px" }}
                  />
                </div>
              </div>
              <div style={{ marginRight: "20px" }}>
                <Image
                  src={fren}
                  alt="My SVG"
                  width={20}
                  height={20}
                  style={frenStyle}
                />
                <div style={buttonContainerStyle}>
                  <button style={stakeButtonStyle}>Spell</button>
                </div>
              </div>
            </div>
            <hr />
          </div>
        ))}
      </div>
    </div>
  );
};

export default Cauldron;
