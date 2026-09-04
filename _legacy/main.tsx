// @ts-nocheck
import React, { useState } from "react";
import ActivityPage from "./Activity";
import SpellsPage from "./Spells2";
import MiFrenPage from "./User";
import BazaarPage from "./Cauldron";
// Import your SVG files
import ActivityIcon from "./assets/ActivityLogo.svg";
import SpellsIcon from "./assets/spellsLogo.svg";
import MiFrenIcon from "./assets/miFren.svg";
import BazaarIcon from "./assets/BazarLogo.svg";
import Image from "next/image";

const MainGame = () => {
  const [activePage, setActivePage] = useState("mifren");

  const navigate = (page) => setActivePage(page);

  const navStyle = {
    display: "flex",
    justifyContent: "space-around",
    alignItems: "center",
    position: "fixed",
    bottom: 0,
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
    fontSize: "12px",
    marginTop: "5px",
  };

  const iconSize = {
    width: "60px", // Adjust as needed
    height: "60px", // Adjust as needed
  };

  return (
    <div style={{ paddingBottom: "100px" }}>
      {activePage === "activity" && <ActivityPage />}
      {activePage === "spells" && <SpellsPage />}
      {activePage === "mifren" && <MiFrenPage />}
      {activePage === "bazaar" && <BazaarPage />}

      <div style={navStyle}>
        <div style={iconStyle} onClick={() => navigate("activity")}>
          <Image src={ActivityIcon} alt="activity" width={60} height={60} />
          <div style={textStyle}>Activity</div>
        </div>
        <div style={iconStyle} onClick={() => navigate("spells")}>
          <Image src={SpellsIcon} alt="activity" width={60} height={60} />

          <div style={textStyle}>Spells</div>
        </div>

        <div style={iconStyle} onClick={() => navigate("bazaar")}>
          <Image src={BazaarIcon} alt="activity" width={60} height={60} />

          <div style={textStyle}>Bazaar</div>
        </div>
        <div style={iconStyle} onClick={() => navigate("mifren")}>
          <Image src={MiFrenIcon} alt="activity" width={60} height={60} />

          <div style={textStyle}>miFren</div>
        </div>
      </div>
    </div>
  );
};

export default MainGame;
