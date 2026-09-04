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

import contractAddresses from "./Contracts.json";
import Image from "next/image";
const Cauldron = ({ chainID }) => {
  const { login, ready, logout, user, sendTransaction } = usePrivy();
  const { authenticated, linkTwitter } = usePrivy();

  const { wallets } = useWallets();
  const [embeddedWallet, setEmbeddedWallet] = useState<any>();
  const [walletBalance, setWalletBalance] = useState<any>(0);
  const [hasCauldron, setCauldron] = useState<any>();
  const [isCauldronSafe, setCauldronSafe] = useState<any>();
  const [contract, setContract] = useState<any>();
  const [ethBalance, setEthBalance] = useState(0);
  const [temperature, setTemperature] = useState(0);
  const [liquidity, setLiquidityBalance] = useState(0);
  const [maxliquidity, setMaxLiquidityBalance] = useState(0);

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

  useEffect(() => {
    if (!ready) {
      return;
    } else {
      setUp();
    }
  }, [ready, wallets, chainID]);
  console.log("chainID cauldron", chainID);
  const miCauldronAddress = contractAddresses[chainID].miCauldronAddress;
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
        miCauldronAddress,
        cauldronAbi,
        ethProvider.getSigner() as any
      );

      setContract(ca);
      const _isCauldronSafe = await ca?.isCauldronInRange(
        user?.wallet?.address
      );
      setCauldronSafe(_isCauldronSafe);
      const pending = await ca?.pendingRewards(user?.wallet?.address);
      console.log("pending", pending);
      setPendingRewards(Number(ethers.utils.formatEther(pending)));
      const rf = await ca?.stakedPositions(user?.wallet?.address);

      console.log("stakedPositions", rf);
      if (rf[1] > 0) {
        setCauldron(rf);
        console.log();
        const value = await ca?.getPositionValue(rf[0]);
        console.log("value", value);
        console.log("liquidity Amount", rf[1]);

        const tick = await ca?.getCurrentTick();

        console.log("tiks", tick);

        console.log("tickUp ", value[4]);
        console.log("tickDown ", value[3]);
        const percentage = ((tick - value[3]) / (value[4] - value[3])) * 100;
        console.log("cauldron is at", percentage, "%");
        setTemperature(percentage);
        setLiquidityBalance(Number(ethers.utils.formatEther(rf[1])));

        setMaxLiquidityBalance(rf[1]);
      }
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
        <div
          style={modalContentStyle}
          className="rpgui-container framed rpgui-draggable"
        >
          {children}
        </div>
      </div>
    );
  };

  const brewMana = async () => {
    // Implement your code submission logic here

    const etherAmount = String((ethValue * walletBalance) / 100); // Use the value from the input field
    const weiValue = ethers.utils.parseEther(etherAmount);
    console.log("minting Cauldron with ", etherAmount);
    const hexWeiValue = ethers.utils.hexlify(weiValue);
    const gasLimit = await contract.estimateGas.brewManaFromETH({
      value: hexWeiValue,
    });
    console.log("gas", gasLimit);

    const txUnsigned = (await contract.populateTransaction.brewManaFromETH({
      value: hexWeiValue,
    })) as UnsignedTransactionRequest;
    const txUiConfig = {
      header: "Add ETH to your Cauldron",
      description:
        "Cauldron will buy miMana and create a UniswapV3 position for you",
      buttonText: "Mint",
    };

    const res = await sendTransaction(
      {
        ...txUnsigned,
        chainId: parseInt("0x5", 16),
        gasLimit: gasLimit.toNumber(),
        value: hexWeiValue,
      },
      txUiConfig
    );
    console.log(res);
    console.log();
    setUp();
  };
  const rebalanceCauldron = async () => {
    // Implement your code submission logic here

    const gasLimit = await contract.estimateGas.rebalancePosition(
      user?.wallet?.address
    );
    console.log("gas", gasLimit);

    const txUnsigned = (await contract.populateTransaction.rebalancePosition(
      user?.wallet?.address
    )) as UnsignedTransactionRequest;
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
  const decreaseCauldron = async () => {
    // Implement your code submission logic here
    let weiValue = 0;
    let etherAmount = 0;
    if (ethValue == 100) {
      console.log("removingALL");
      weiValue = maxliquidity;
      console.log("removing Cauldron with ", weiValue);
    } else {
      etherAmount = String((ethValue * liquidity) / 100); // Use the value from the input field
      weiValue = ethers.utils.parseEther(etherAmount);
      console.log("removing Cauldron with ", weiValue);
    }

    const hexWeiValue = ethers.utils.hexlify(weiValue);
    const gasLimit = await contract.estimateGas.decreaseLiquidity(
      hexWeiValue,
      user?.wallet?.address
    );
    console.log("gas", gasLimit);

    const txUnsigned = (await contract.populateTransaction.decreaseLiquidity(
      hexWeiValue,
      user?.wallet?.address
    )) as UnsignedTransactionRequest;
    const txUiConfig = {
      header: "Remove Liquidity from your Cauldron",
      description: "Remove Liquidity from your Cauldron",
      buttonText: "Remove",
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
  // Component
  const temperatureBarStyle = {
    position: "relative",
    top: "10%", // Adjust as needed
    left: "0%",
    height: "10px", // Adjust as needed
    width: "70%", // Adjust as needed
    background: `linear-gradient(to left, #00ff00 0%, #ff0000 100%)`, // Adjust colors
    borderRadius: "5px",
    marginTop: "2%",
  };
  const temperaturePointStyle = {
    position: "absolute",
    top: "-5px", // Adjust as needed
    left: `${temperature}%`, // Adjust based on temperature
    right: "10px", // Adjust as needed
    width: "20px",
    height: "20px",

    background: "rgba(222,222,222,1)",
    borderRadius: "50%",
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

    overflow: "hidden", // Prevent overflow
    position: "relative", // Position relative for absolute children
  };
  return (
    <div style={containerStyle} className=" rpgui-content">
      {isModalOpen && (
        <Modal closeModal={closeModal}>
          <label>
            <div>Send ETH to cauldron</div>

            <div className="rpgui-slider-container slidecontainer">
              <input
                type="range"
                min="0"
                max="90"
                step="1"
                value={ethValue}
                onChange={(e) => setEthValue(e.target.value)}
                className="slider"
                style={{
                  position: "absolute",
                  height: "20px",
                  left: "0",
                  right: " 0",
                  backgroundImage: `url("dist/img/slider-track.png")`,
                  backgroundRepeat: "repeat-x",
                  backgroundSize: "24px 100%",
                }}
              />{" "}
              <div
                className="rpgui-slider-left-edge"
                style={{ position: "absolute", height: "25px", top: "2px" }}
              />
              <div
                className="rpgui-slider-right-edge"
                style={{ position: "absolute", height: "25px", top: "2px" }}
              />
            </div>
            <div style={{ textAlign: "center", marginTop: "10px" }}>
              {Math.round(((ethValue * walletBalance) / 100) * 1000) / 1000}E
            </div>
          </label>
          <button className="rpgui-button" onClick={brewMana}>
            Create Cauldron
          </button>
        </Modal>
      )}
      {isModalRemoveOpen && (
        <Modal closeModal={closeModalRemove}>
          <label>
            <div className="slide-container">
              Remove Liquidity from cauldron
            </div>
            <div className="rpgui-slider-container slidecontainer">
              <input
                type="range"
                min="0"
                max="100"
                step="1"
                value={ethValue}
                onChange={(e) => setEthValue(e.target.value)}
                className="slider"
                style={{
                  height: "20px",
                  position: "absolute",
                  width: "100%",
                  right: " 0",
                  backgroundImage: `url("dist/img/slider-track.png")`,
                  backgroundRepeat: "repeat-x",
                  backgroundSize: "24px 100%",
                }}
              />
              <div
                className="rpgui-slider-left-edge"
                style={{ position: "absolute", height: "25px", top: "2px" }}
              />
              <div
                className="rpgui-slider-right-edge"
                style={{ position: "absolute", height: "25px", top: "2px" }}
              />
            </div>
            <div style={{ textAlign: "center", marginTop: "10px" }}>
              {(ethValue * 100) / 100}%
            </div>
          </label>
          <button className="rpgui-button" onClick={decreaseCauldron}>
            remove Cauldron
          </button>
        </Modal>
      )}

      <div className="rpgui-container framed" style={containerStyle}>
        <div className="stake-header ">
          Brew miMana
          <div
            className="stake-header"
            style={{ display: "flex", flexDirection: "row" }}
          >
            <div style={inputGroupStyle}>
              <div>{Math.round(liquidity * 1000) / 1000}</div>
            </div>
            <div style={inputGroupStyle}>
              <div>{Math.round(pendingRewards * 1000) / 1000} </div>
              <button style={stakeButtonStyle} onClick={claimRewards}>
                Claim
              </button>
            </div>
          </div>
        </div>

        <Image
          src={cauldron}
          alt="My SVG"
          width={220}
          height={220}
          className=""
        />
        <div className="rpgui-slider-container">
          <div className="rpgui-slider-left-edge" style={{ zIndex: 100 }} />
          <div className="rpgui-slider-right-edge" style={{ zIndex: 100 }} />
          <div className="rpgui-slider-track" />
          <div
            className="rpgui-slider-thumb"
            style={{
              position: "absolute",
              left: `${temperature}%`,
              zIndex: 200,
            }}
          ></div>
        </div>
        <div
          style={{
            display: "flex",
            flexDirection: "row",
            justifyContent: "space-around",
          }}
        >
          {hasCauldron && (
            <button
              style={{ marginRight: "10px" }}
              className="rpgui-button"
              onClick={openModal}
            >
              Add
            </button>
          )}
          {!hasCauldron && (
            <button className="rpgui-button" onClick={openModal}>
              Create UniV3 Cauldron"
            </button>
          )}
          {hasCauldron && (
            <div>
              <button className="rpgui-button" onClick={openModalRemove}>
                Remove
              </button>
            </div>
          )}
        </div>
        {hasCauldron && !isCauldronSafe && (
          <button className="rpgui-button" onClick={rebalanceCauldron}>
            Rebalance Position
          </button>
        )}
      </div>
    </div>
  );
};

export default Cauldron;
