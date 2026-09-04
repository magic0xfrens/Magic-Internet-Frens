// @ts-nocheck
import React, { useEffect, useState } from "react";
import { usePrivy } from "@privy-io/react-auth";
import logo from "./assets/Logo.svg";
import fren from "./assets/PlebFren.svg";
import Image from "next/image";
import Web3 from "web3";
import contractABI from "./Referal.json";
import potion from "./assets/Potion.svg";
const Activity = () => {
  const { login, logout, user } = usePrivy();
  const contractAddress = "0xB51FDf9b6969a81e0CbB502171A99083672bb3b7";
  const web3 = new Web3(
    "https://base-goerli.g.alchemy.com/v2/1yliLscaWkkjEqMa7uyIuboAe8pJDG-v"
  );
  const contract = new web3.eth.Contract(contractABI, contractAddress);
  const [activities, setActivities] = useState([]);
  async function getLatestActivities() {
    try {
      const events = await contract.getPastEvents("allEvents", {
        fromBlock: 0, // Use a sensible block number to limit the query
        toBlock: "latest",
      });
      // Process and return events
      console.log("events", events);
      return events.map((event) => ({
        id: event.id,
        description: `Event of type ${event.event} generated: ${event.returnValues[1]}by ${event.returnValues[0]}`,
        // Add more details as needed
      }));
    } catch (error) {
      console.error("Error fetching events:", error);
      return [];
    }
  }
  useEffect(() => {
    const interval = setInterval(() => {
      getLatestActivities().then(setActivities);
    }, 10000); // Poll every 10 seconds

    return () => clearInterval(interval);
  }, []);

  const players = [
    { id: 1, name: "Player1", points: 100 },
    { id: 2, name: "Player2", points: 300 },
    { id: 3, name: "Player4", points: 200 },
    // Add more players here
  ];

  // Styles
  // ... Your existing styles ...
  const buttonContainerStyle = {
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
    borderRadius: "15px", // rounded corners
    padding: "10px 20px", // reduce padding
    fontSize: "1rem",
    cursor: "pointer",
    outline: "none",
    boxShadow: "0 2px 4px rgba(0, 0, 0, 0.2)", // softer shadow
    width: "61%", // make buttons wider
    margin: "0 5px", // space around buttons, adjust as needed to fit your layout
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
    alignItems: "center",
    width: "100%",
    maxHeight: "60vh", // Adjust this value as needed
    overflowY: "auto", // Enable vertical scrolling
    overflowX: "hidden", // Enable vertical scrolling
    margin: "0 auto", // Center the container if needed
    marginTop: "30%", // Center the container if needed
  };

  const playerItemStyle = {
    display: "flex",
    justifyContent: "space-between",
    alignItems: "center",
    width: "90%",
    margin: "5px 0",
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

    overflow: "hidden", // Prevent overflow
    position: "relative", // Position relative for absolute children
  };

  const headerStyle = {
    position: "fixed",
    display: "flex",
    alignItems: "left", // align items vertically
    justifyContent: "center", // center items horizontally
    width: "100%", // take up full container width
    marginTop: "3vh", // push down from the top
    marginBottom: "3vh", // push down from the top
    backdropFilter: "blur(10px)",
  };

  const logoStyle = {
    width: "75px", // Adjust logo size
    marginRight: "1rem", // Space to the right of the logo
  };
  const frenStyle = {
    width: "40px", // Adjust logo size
    marginLeft: "1rem", // Space to the right of the logo
  };

  const textStyle = {
    fontSize: "48px",

    textAlign: "left", // align text to the left
  };

  // Component
  return (
    <div style={containerStyle} className="containerstyle rpgui-content">
      <div
        className="stake-container rpgui-container framed"
        style={{ position: "relative", bottom: "-100px" }}
      >
        <div>
          <Image
            src={potion}
            alt="My SVG"
            width={50}
            height={50}
            className="potion"
          />
          <div className="stake-header">Fren Heal Potion</div>
          <button className="stake-button">Drink it</button>
        </div>
        <div>
          <Image
            src={potion}
            alt="My SVG"
            width={50}
            height={50}
            className="potion"
          />
          <div className="stake-header">Fren Protec Potion</div>
          <button className="stake-button">Drink it</button>
        </div>
      </div>
    </div>
  );
};

export default Activity;
