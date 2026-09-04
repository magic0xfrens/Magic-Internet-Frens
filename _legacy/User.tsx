// @ts-nocheck
import React, { useState, useEffect } from "react";
import {
  usePrivy,
  useWallets,
  UnsignedTransactionRequest,
} from "@privy-io/react-auth";

import { ethers, Contract } from "ethers";
import referalAbi from "./Referal.json";
import Modal from "./KeyModal";
import logo from "./assets/Logo.svg";
import eth from "./assets/EthLogo.svg";
import fren from "./assets/wizard.svg";
import Image from "next/image";
import { useContractRead } from "./hooks/usecontractread";
import { useContractWrite } from "./hooks/usecontractwrite";
import { ether } from "@lens-protocol/react-web";
import * as dotenv from "dotenv";
import contractAddresses from "./Contracts.json";
const User = () => {
  dotenv.config();
  const [code, setCode] = useState("");
  const { logout, user, sendTransaction } = usePrivy();

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
    display: "flex",
    alignItems: "left", // align items vertically
    justifyContent: "center", // center items horizontally
    width: "100%", // take up full container width
    marginTop: "3vh", // push down from the top
    marginBottom: "1vh", // push down from the top
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
  const textStyle = {
    fontSize: "48px",

    textAlign: "left", // align text to the left
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

  const inputStyle = {
    border: "none",
    outline: "none",
    fontSize: "16px",
    width: "100%", // take up remaining space
  };

  const buttonStyle = {
    padding: "10px 20px",
    fontSize: "16px",
    fontWeight: "bold",
    cursor: "pointer",
    outline: "none",
    border: "1px solid #ddd",
    borderRadius: "4px",
    backgroundColor: "white", // match the input field color
  };
  const ethBalanceStyle = {
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    fontSize: "24px",
    marginBottom: "20px",
  };

  const labelStyle = {
    position: "absolute",
    marginTop: "-12%", // adjust this value as needed
    marginLeft: "-40%", // adjust this value as needed
    fontSize: "12px", // smaller font size for the label
    color: "#aaa", // lighter color for the placeholder text
  };
  const [userStats, setUserStats] = useState({
    xp: 1400,
    level: 9,
    nextLevelXP: 2000,
  });

  const profilePictureStyle = {
    width: "200px", // Set the size of the picture

    borderRadius: "10%", // Make it round
    objectFit: "cover", // Ensure the image covers the area

    marginTop: "20px", // Adjust spacing as needed
  };

  const xpBarContainerStyle = {
    marginTop: "2%",
    width: "40%", // XP bar width
    backgroundColor: "#e0e0e0", // Background color for the XP bar
    borderRadius: "10px", // Rounded corners for the XP bar
    overflow: "hidden", // Hide the overflow to maintain rounded corners
  };

  const xpBarFillStyle = {
    height: "20px", // Height of the XP bar
    backgroundColor: "#212145", // Color of the XP fill
    width: `${(userStats.xp / userStats.nextLevelXP) * 100}%`, // Calculate width based on XP
  };

  const handleUseCode = async () => {
    // Implement your code submission logic here
    console.log(code); // For now, just log the code to the console
    console.log(contract);
    const gasLimit = await contract.estimateGas.signUpReferral(code);
    console.log("gas", gasLimit);
    const txUnsigned = (await contract.populateTransaction.signUpReferral(
      code
    )) as UnsignedTransactionRequest;
    const res = await sendTransaction({
      ...txUnsigned,
      chainId: parseInt("0x5", 16),
      gasLimit: gasLimit.toNumber(),
    });
    console.log();
  };
  const [ethBalance, setEthBalance] = useState(0);

  const { ready, authenticated, linkTwitter } = usePrivy();

  const { wallets } = useWallets();
  const [embeddedWallet, setEmbeddedWallet] = useState<any>();
  const [frenBalance, setFrenBalance] = useState<any>(0);
  const [walletBalance, setWalletBalance] = useState<any>(0);
  const [contract, setContract] = useState<any>();

  useEffect(() => {
    if (!ready) {
      return;
    } else {
      setUp();
    }
    const Referaladdress = process.env.REFERRAL_ADDRESS;
    const miFrenNFTaddress = process.env.MI_FRENS_ADDRESS;
    const miManaAddress = process.env.MI_MANA_ADDRESS;

    async function setUp() {
      const embeddedWallet = wallets.find(
        (wallet) => wallet.walletClientType === "privy"
      );
      if (embeddedWallet) {
        const provider = await embeddedWallet.getEthereumProvider();
        await provider.request({
          method: "wallet_switchEthereumChain",
          params: [{ chainId: `0x5` }],
        });
        const ethProvider = new ethers.providers.Web3Provider(provider);
        const walletBalance = await ethProvider.getBalance(
          embeddedWallet.address
        );
        const ethStringAmount = Number(ethers.utils.formatEther(walletBalance));
        setEmbeddedWallet(embeddedWallet);
        setWalletBalance(Math.round(ethStringAmount * 10000) / 1000);
        const miFren = new Contract(
          Referaladdress,
          referalAbi,
          ethProvider.getSigner() as any
        );

        const minft = new Contract(Referaladdress, referalAbi, provider as any);
        setContract(minft);

        const balance = await miFren.balanceOf(user?.wallet?.address);
        setFrenBalance(balance);
      }
    }
  }, [ready, wallets]);

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

  const mintFren = async () => {
    const Referaladdress = "0xb36683F227F0E1Ca1683FBe39be5618484DFbac2";
    const provider = await embeddedWallet.getEthereumProvider();
    await provider.request({
      method: "wallet_switchEthereumChain",
      params: [{ chainId: `0x5` }],
    });

    const minft = new Contract(Referaladdress, referalAbi, provider as any);
    // Implement your code submission logic here
    console.log(code); // For now, just log the code to the console
    console.log(contract);
    const gasLimit = await contract.estimateGas.generateReferralCode();
    console.log("gas", gasLimit);
    const txUnsigned =
      (await contract.populateTransaction.generateReferralCode()) as UnsignedTransactionRequest;
    const res = await sendTransaction({
      ...txUnsigned,
      chainId: parseInt("0x5", 16),
      gasLimit: gasLimit,
    });
    console.log("code", res);
  };

  return (
    <div style={containerStyle} className="rpgui-content">
      <div style={containerStyle} className="rpgui-container framed">
        {/* Profile Picture */}
        <p>{"Username"}</p> {/* Replace with actual username */}
        <Image
          src={fren}
          alt="My SVG"
          width={200}
          height={300}
          style={profilePictureStyle}
        />
        {/* User Stats */}
        <label>HP:</label>
        <div style={{ width: "60%" }}>
          <div className="rpgui-progress" style={{ height: "40px" }}>
            <div className="rpgui-progress-track " style={{ height: "40px" }} />
            <div
              className="rpgui-progress-fill green "
              style={{ width: "50%" }}
            />
            <div
              className="rpgui-progress-left-edge "
              style={{ height: "40px" }}
            />

            <div
              className="rpgui-progress-right-edge "
              style={{ height: "40px" }}
            />
          </div>
        </div>
      </div>
    </div>
  );
};
export default User;
