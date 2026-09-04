// @ts-nocheck
import React, { useState, useEffect } from "react";
import {
  usePrivy,
  useWallets,
  UnsignedTransactionRequest,
} from "@privy-io/react-auth";
import logo from "./assets/Logo.svg";
import eth from "./assets/ETH.svg";
import arb from "./assets/ARB.svg";
import avax from "./assets/AVAX.svg";
import base from "./assets/BASE.svg";
import wallet from "./assets/wallet.png";
import fren from "./assets/frens.svg";
import cauldron from "./assets/cauldron.webp";
import Image from "next/image";
import { ethers, Contract } from "ethers";
import referalAbi from "./Referal.json";
import contractAddresses from "./Contracts.json";
import { useContractRead } from "./hooks/usecontractread";
import { useContractWrite } from "./hooks/usecontractwrite";
import Modal from "./KeyModal";
import * as dotenv from "dotenv";
const ReferralPage = ({ chainID }) => {
  const [code, setCode] = useState("");
  const { logout, user, sendTransaction } = usePrivy();
  dotenv.config();
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

  const inputContainerStyle = {
    display: "flex",
    alignItems: "center",
    marginBottom: "1rem",
  };

  const headerStyle = {
    fontFamily: "sans-serif",
    position: "relative",
    display: "flex",
    alignItems: "left", // align items vertically
    justifyContent: "center", // center items horizontally
    width: "80%", // take up full container width
    marginTop: "3vh",
    left: "10%", // push down from the top
    marginBottom: "3vh", // push down from the top
  };

  const logoStyle = {
    width: "75px", // Adjust logo size
    marginRight: "1rem", // Space to the right of the logo
  };
  const ETHlogoStyle = {
    width: "25px", // Adjust logo size
    marginRight: "3rem", // Space to the right of the logo
    marginLeft: "0.2rem", // Space to the right of the logo
  };
  const walletstyle = {
    width: "55px", // Adjust logo size
    marginRight: "3rem", // Space to the right of the logo
    marginLeft: "0.2rem", // Space to the right of the logo
  };
  const cauldronstyle = {
    marginTop: "10%",
    width: "208px", // Adjust logo size
  };
  const frenronstyle = {
    marginTop: "10%",
    width: "90px", // Adjust logo size
  };
  const ETHlogoStylesm = {
    width: "15px", // Adjust logo size
    marginRight: "0rem", // Space to the right of the logo
    marginLeft: "0rem", // Space to the right of the logo
  };
  const textStyle = {
    fontSize: "39px",

    textAlign: "left", // align text to the left
  };
  const inputGroupStyle = {
    display: "flex",
    alignItems: "center",
    justifyContent: "space-around",
    position: "relative",
    padding: "1px",
    // border: "1px solid #ddd",
    borderRadius: "4px",
    width: "100%", // full width of the parent container
    maxWidth: "300px", // maximum width of the input group
    margin: "20px 0", // margin around the input group for spacing
  };

  const inputStyle = {
    border: "none",
    outline: "none",
    fontSize: "16px",
    background: "rgba(255,255,255,0.1)",
    width: "100%", // take up remaining space
  };

  const buttonStyle = {
    padding: "10px 20px",
    fontSize: "16px",
    fontWeight: "bold",
    color: "black",
    cursor: "pointer",
    outline: "none",
    border: "1px solid #ddd",
    marginTop: "10px",
    borderRadius: "4px",
    backgroundColor: "white", // match the input field color
  };
  const mintbuttonStyle = {
    backgroundColor: "#212145",
    border: "none",
    borderRadius: "10px",
    padding: "15px 40px", // larger button
    fontSize: "18px",
    width: "95vw",
    color: "white",
    cursor: "pointer",
    outline: "none",

    maxWidth: "300px", // max width for button
    marginTop: "0px",
  };
  const labelStyle = {
    position: "absolute",
    zIndex: -1,
    marginTop: "-12%", // adjust this value as needed
    marginLeft: "-40%", // adjust this value as needed
    fontSize: "12px", // smaller font size for the label
    color: "#aaa", // lighter color for the placeholder text
  };

  const mintReferal = async () => {
    // Implement your code submission logic here
    console.log(code); // For now, just log the code to the console
    console.log(contract);

    const etherAmount = "0.015";
    const weiValue = ethers.utils.parseEther(etherAmount);
    const hexWeiValue = ethers.utils.hexlify(weiValue);
    const gasLimit = await contract.estimateGas.signUpReferral(code, {
      value: hexWeiValue,
    });
    console.log("gas", gasLimit);

    const txUnsigned = (await contract.populateTransaction.signUpReferral(
      code,
      { value: hexWeiValue }
    )) as UnsignedTransactionRequest;
    const txUiConfig = {
      header: "Mint Fren",
      description: "Send 0.01 ETH to mint your fren",
      buttonText: "Mint",
    };

    const res = await sendTransaction(
      {
        ...txUnsigned,
        chainId: parseInt(chainID, 16),
        gasLimit: gasLimit.toNumber(),
        value: hexWeiValue,
      },
      txUiConfig
    );
    console.log();
    setUp();
  };
  const mint = async () => {
    // Implement your code submission logic here
    console.log(code); // For now, just log the code to the console
    console.log(contract);

    const etherAmount = "0.069";
    const weiValue = ethers.utils.parseEther(etherAmount);
    const hexWeiValue = ethers.utils.hexlify(weiValue);
    const gasLimit = await contract.estimateGas.mint({
      value: hexWeiValue,
    });
    console.log("gas", gasLimit);

    const txUnsigned = (await contract.populateTransaction.mint({
      value: hexWeiValue,
    })) as UnsignedTransactionRequest;
    const txUiConfig = {
      header: "Mint Fren",
      description: "Send 0.069 ETH to mint your fren",
      buttonText: "Mint",
    };

    const res = await sendTransaction(
      {
        ...txUnsigned,
        chainId: parseInt(chainID, 16),
        gasLimit: gasLimit.toNumber(),
        value: hexWeiValue,
      },
      txUiConfig
    );
    console.log(res);
    setUp();
  };
  const { ready, authenticated, linkTwitter } = usePrivy();

  const { wallets } = useWallets();
  const [embeddedWallet, setEmbeddedWallet] = useState<any>();
  const [walletBalance, setWalletBalance] = useState<any>(0);
  const [contract, setContract] = useState<any>();
  const [ethBalance, setEthBalance] = useState(0);

  const [showModal, setShowModal] = useState(false); // State to control the modal visibility

  const addressStyle = {
    backgroundColor: "#212145",
    color: "white",
    padding: "10px",
    borderRadius: "10px",
    cursor: "pointer",
    marginRight: "10px",
  };

  const openModal = () => {
    setShowModal(true);
  };
  const copyToClipboard = async () => {
    if (user?.wallet?.address) {
      try {
        await navigator.clipboard.writeText(user?.wallet?.address);
        console.log("Address copied to clipboard:", user?.wallet?.address);
        // Optionally, you can show a message to the user indicating success
      } catch (error) {
        console.error("Failed to copy:", error);
        // Handle error (e.g., show an error message to the user)
      }
    }
  };
  const setBase = async () => {
    setchainID("0x2105");
    setUp();
    console.log(chainID);
  };
  const setArb = async () => {
    setchainID("0xa4b1");
    setUp();
    console.log(chainID);
  };
  const setAvax = async () => {
    setchainID("0xa86a");
    setUp();
    console.log(chainID);
  };
  const handleSelectionChange = (e) => {
    const selectedValue = e.target.value;

    switch (selectedValue) {
      case "Arb":
        setArb();
        break;
      case "Base":
        setBase();
        break;
      case "Avax":
        setAvax();
        break;
      default:
      // Handle default case or do nothing
    }
  };

  useEffect(() => {
    if (!ready) {
      return;
    } else {
      setUp();
    }
  }, [ready, wallets, chainID]);
  console.log("CHAIN", chainID);
  const address = contractAddresses[chainID].referralAddress;
  console.log("CHAIN", contractAddresses[chainID]);
  console.log("REFERAL", address);
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
      const ca = new Contract(
        address,
        referalAbi,
        ethProvider.getSigner() as any
      );

      setContract(ca);
    }
  }
  return (
    <div style={containerStyle} className="rpgui-content rpgui-draggable">
      {showModal && <Modal closeModal={() => setShowModal(false)} />}
      <div style={containerStyle} className="rpgui-container framed">
        <div style={{ width: "80vw" }}>
          Magic Internet Frens is still in Beta , fund your wallet in your
          favorite chain to mint your fren + gas
        </div>{" "}
        <div style={inputGroupStyle} className="rpgui-container framed">
          <input
            style={inputStyle}
            type="text"
            placeholder="referral code"
            value={code}
            onChange={(e) => setCode(e.target.value)}
          />

          {/*} <button onClick={mintReferal} style={buttonStyle}>
            Mint Ref
  </button>*/}
        </div>
        <button
          className="rpgui-button"
          onClick={mintReferal}
          style={mintbuttonStyle}
        >
          <div
            style={{
              textAlign: "center",
            }}
          >
            {" "}
            Mint{" "}
          </div>
        </button>
        <div style={{ display: "flex", flexDirection: "row" }}>
          <Image
            src={fren}
            alt="My SVG"
            width={72}
            height={72}
            style={cauldronstyle}
          />
        </div>
      </div>
    </div>
  );
};

export default ReferralPage;
