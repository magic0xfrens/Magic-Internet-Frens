// @ts-nocheck
import React, { useState, useEffect } from "react";
import ActivityPage from "./Activity";
import SpellsPage from "./Spells2";
import MiFrenPage from "./User";
import BazaarPage from "./Cauldron";
import Referal from "./Referal";
// Import your SVG files
import ActivityIcon from "./assets/ActivityLogo.svg";
import SpellsIcon from "./assets/spellsLogo.svg";
import MiFrenIcon from "./assets/miFren.svg";
import BazaarIcon from "./assets/BazarLogo.svg";
import Image from "next/image";
import ReferralPage from "./Referal";
import logo from "./assets/Logo.svg";
import eth from "./assets/ETH.svg";
import arb from "./assets/ARB.svg";
import avax from "./assets/AVAX.svg";
import base from "./assets/BASE.svg";
import wallet from "./assets/wallet.svg";
import fren from "./assets/frens.svg";
import Modal from "./KeyModal";
import { ethers, Contract } from "ethers";
import InstallAppPrompt from "./InstallAppPrompt";
import referalAbi from "./Referal.json";
import miFrensAbi from "./miFren.json";
import * as dotenv from "dotenv";
import contractAddresses from "./Contracts.json";
import { useLogin, usePrivy, useWallets } from "@privy-io/react-auth";
const logoStyle = {
  width: "75px", // Adjust logo size
  marginRight: "1rem", // Space to the right of the logo
};

const inputGroupStyle = {
  display: "flex",
  alignItems: "center",
  justifyContent: "space-around",
  position: "relative",

  // border: "1px solid #ddd",
  borderRadius: "4px",
  width: "100%", // full width of the parent container
  maxWidth: "300px", // maximum width of the input group
  margin: "0px 0",
  marginBottom: "10px",
  // margin around the input group for spacing
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

  bottom: "5px",
  position: "relative",
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
const MainGame = () => {
  const [activePage, setActivePage] = useState("mifren");

  const navigate = (page) => setActivePage(page);
  const [chainID, setchainID] = useState("0xa4b1");
  const [showModal, setShowModal] = useState(false); // State to control the modal visibility

  const addressStyle = {
    backgroundColor: "#212145",
    color: "white",
    padding: "10px",
    borderRadius: "10px",
    cursor: "pointer",
    marginRight: "10px",
  };
  const containerStyle = {
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    justifyContent: "flex-start",
    height: "10vh", // Adjust height to 'auto' if content should dictate the container size
    textAlign: "center",
    fontFamily: "sans-serif",
    width: "90%", // Full width
    maxWidth: "480px", // Max-width for mobile screens
    margin: "0 auto", // Center the container
    backgroundColor: "#f4f4f9", // Light grey background for the stake container
    borderRadius: "10px",
    boxShadow: "0 2px 4px rgba(0, 0, 0, 0.2)", // Softer shadow
    overflow: "hidden", // Prevent overflow
    position: "relative", // Position relative for absolute children
  };
  const openModal = () => {
    setShowModal(true);
  };
  const navStyle = {
    display: "flex",
    justifyContent: "space-around",
    alignItems: "center",
    position: "fixed",
    bottom: 0,
    height: "10%",
    left: 0,
    right: 0,
    backgroundColor: "#212145",
    borderTop: "1px solid #ccc",
    padding: "20px 0",
    zIndex: 1000,
    fontFamily: "'Arial', sans-serif", // Set a common font
  };

  const iconStyle = {
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    cursor: "pointer",
  };

  const textStyle = {
    fontSize: "39px",
    marginTop: "5px",
  };
  const [isAvax, setIsAvax] = useState(false);
  const iconSize = {
    width: "60px", // Adjust as needed
    height: "60px", // Adjust as needed
  };
  const setBase = async () => {
    setchainID("0x2105");
    setIsAvax(false);

    setUp();
  };
  const setArb = async () => {
    setchainID("0x5");
    setIsAvax(false);
    setUp();
  };

  const setAvax = async () => {
    setchainID("0xa86a");
    setIsAvax(true);
    setUp();
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
  const ReferalAddress = contractAddresses[chainID]?.referralAddress;
  const miFrensAddress = contractAddresses[chainID]?.miFrensAddress;
  const [isFren, setisFren] = useState(false);
  const [frenBalance, setfrenBalance] = useState(0);
  const [isinstalled, setisInstalled] = useState(false);
  const [embeddedWallet, setEmbeddedWallet] = useState<any>();

  const [walletBalance, setWalletBalance] = useState<any>(0);
  const { ready, authenticated, user, logout } = usePrivy();
  const { wallets } = useWallets();
  const userTwitter = user?.twitter?.name;

  const isLoggedIn = ready && authenticated;

  useEffect(() => {
    if (!isLoggedIn) {
      return;
    } else {
      setUp();
    }
  }, [ready, wallets, chainID]);
  async function setUp() {
    console.log("settingUp", chainID);
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
      const _walletBalance = await ethProvider.getBalance(
        embeddedWallet.address
      );

      const ethStringAmount = Number(ethers.utils.formatEther(_walletBalance));
      setEmbeddedWallet(embeddedWallet);
      console.log("walletBalance", _walletBalance);
      setWalletBalance(Math.round(ethStringAmount * 10000) / 10000);
      console.log("walletBalance", walletBalance);
    }
  }
  return (
    <div
      style={{ paddingBottom: "100px" }}
      className="rpgui-content rpgui-draggable"
    >
      <div style={headerStyle}>
        <Image
          src={logo}
          alt="My SVG"
          width={100}
          height={100}
          style={logoStyle}
        />
        <div style={textStyle}>
          mi<span style={{ fontWeight: "bold" }}>Frens</span>
        </div>
      </div>
      {showModal && <Modal closeModal={() => setShowModal(false)} />}
      <div style={containerStyle} className="rpgui-container framed">
        <div style={inputGroupStyle}>
          {walletBalance}
          <Image
            src={isAvax ? avax : eth}
            alt="My SVG"
            width={25}
            height={25}
            style={ETHlogoStyle}
          />
          <select
            className="rpgui-dropdown"
            onChange={(e) => handleSelectionChange(e)}
          >
            <option value="Arb" selected>
              Arb{" "}
            </option>
            <option className="rpgui-dropdown" value="Base">
              Base{" "}
            </option>
            <option
              style={{ display: "flex", flexDirection: "row" }}
              value="Avax"
            >
              Avax{" "}
            </option>
          </select>
          <div onClick={openModal}>
            <Image
              src={wallet}
              alt=""
              width={72}
              height={72}
              style={walletstyle}
            />
          </div>
        </div>
      </div>

      {!frenBalance ? (
        <Referal chainID={chainID} />
      ) : (
        // <Referal chainID={chainID} />
        <div>
          {activePage === "activity" && <ActivityPage chainID={chainID} />}
          {activePage === "spells" && <SpellsPage chainID={chainID} />}
          {activePage === "mifren" && <MiFrenPage chainID={chainID} />}
          {activePage === "bazaar" && <BazaarPage chainID={chainID} />}
        </div>
      )}
      <div style={navStyle}>
        <div style={iconStyle} onClick={() => navigate("activity")}>
          <Image src={ActivityIcon} alt="activity" width={30} height={30} />
        </div>
        <div style={iconStyle} onClick={() => navigate("spells")}>
          <Image src={SpellsIcon} alt="activity" width={30} height={30} />
        </div>

        <div style={iconStyle} onClick={() => navigate("bazaar")}>
          <Image src={BazaarIcon} alt="activity" width={30} height={30} />
        </div>
        <div style={iconStyle} onClick={() => navigate("mifren")}>
          <Image src={MiFrenIcon} alt="activity" width={30} height={30} />
        </div>
      </div>
    </div>
  );
};

export default MainGame;
