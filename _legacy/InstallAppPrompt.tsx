// @ts-nocheck
import { FaBookOpen, FaTelegramPlane } from "react-icons/fa"; // ensure you've installed react-icons
import { isAndroid, isMobile } from "react-device-detect";
import { useState, useEffect } from "react";
import logo from "./assets/Logo.svg";
import mobileLogo from "./assets/MobileFren.svg";

import Image from "next/image";
const InstallAppPrompt = () => {
  const [isInstalled, setIsInstalled] = useState(false);
  const [installationPrompt, setInstallationPrompt] = useState<any>();
  const [deferredPrompt, setDeferredPrompt] = useState<any>();

  const containerStyle = {
    position: "absolute",
    width: "100%",
    height: "100%",
    display: "flex",
    flexDirection: "column",
    zIndex: "1000",
    overflow: "hidden",
    alignItems: "center",
    justifyContent: "center",
    backgroundColor: "white", // Set your background color
    color: "#212145", // Set text color
    textAlign: "center", // Center text
    fontFamily: "'Arial', sans-serif", // Set a common font
    padding: "20px", // Add some padding
  };
  const modalStyle = {
    position: "absolute",
    borderRadius: "10px",
    width: "80vw",

    display: "flex",
    flexDirection: "column",
    boxShadow: "0 4px 8px rgba(0, 0, 0, 0.1)",
    alignItems: "center",
    justifyContent: "center",
    backgroundColor: "white", // Set your background color
    color: "#212145", // Set text color
    textAlign: "center", // Center text
    fontFamily: "'Arial', sans-serif", // Set a common font
    padding: "20px", // Add some padding
  };
  const containerStylePWA = {
    position: "absolute",
    width: "105vw",
    height: "105vh",
    left: "-10px",
    top: "-10px",
    display: "flex",
    zIndex: 1000,
    flexDirection: "column",
    overflow: "hidden",
    alignItems: "center",
    justifyContent: "center",
    backgroundColor: "rgba(18,18,18,0.5)", // Set your background color
    color: "#212145", // Set text color
    textAlign: "center", // Center text
    fontFamily: "'Arial', sans-serif", // Set a common font
  };
  // Add new styles for the logo text
  const logoTextStyle = {
    display: "flex", // Use flex to align text with the logo
    alignItems: "center", // Center align the text with the logo image
    fontWeight: "normal", // Normal font weight for the "mi" part
    color: "#212145", // Text color
    fontSize: "2rem", // Larger font size to match your logo image
    fontFamily: "'Arial', sans-serif", // Your font choice
  };
  const modalContentStyle = {
    display: "flex", // Use flexbox for layout
    alignItems: "center", // Align items vertically
    justifyContent: "center", // Center items horizontally
    gap: "20px", // Add space between the logo and the text
  };

  const logoTextBoldStyle = {
    fontWeight: "bold", // Bold font weight for the "Frens" part
  };
  const logoStyle = {
    marginBottom: "2rem", // Space below logo
    marginRight: "1rem", // Space below logo
  };
  const logoStyleADD = {
    width: "75px", // Adjust logo size
    marginBottom: "2rem", // Space below logo
    marginRight: "1rem", // Space below logo
  };

  const textStyle = {
    marginBottom: "1rem", // Space between text elements
    fontSize: "1rem", // Adjust font size
  };
  const addToHomeScreenTextStyle = {
    background: "#212145",
    borderRadius: "10px",
    color: "white",
    fontWeight: "bold", // Make the text bold
    fontSize: "20px", // Larger font size for the instruction text
    flex: "1", // Allow the text to fill the available space
    textAlign: "center", // Align the text to the left
    margin: "0", // Reset margin
  };

  const linkStyle = {
    textDecoration: "none", // No underline for links
    color: "#212145", // Set link color
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
    gap: "10px", // Space between icon and text
    fontSize: "1.2rem", // Larger font size for links
    marginBottom: "0.5rem", // Space between links
  };
  const mqStandAlone = "(display-mode: standalone)";
  useEffect(() => {
    window.addEventListener("beforeinstallprompt", (e) => {
      setIsInstalled(false);
      e.preventDefault();
      setDeferredPrompt(e);
    });
    if (
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      (navigator as any).standalone ||
      window.matchMedia(mqStandAlone).matches
    ) {
      setIsInstalled(true);
      console.log("isintsllled", isInstalled);
    }
  }, []);

  async function addToHomeScreen() {
    if (!deferredPrompt) return;
    deferredPrompt.prompt();
    deferredPrompt.userChoice.then((choiceResult) => {
      if (choiceResult.outcome === "accepted") {
        setIsInstalled(true);
      } else {
        console.log("User dismissed the A2HS prompt");
      }
      setDeferredPrompt(null);
    });
  }

  if (!deferredPrompt) return null;

  return (
    <div>
      {!isMobile ? (
        <div style={containerStyle}>
          <div style={logoTextStyle}>
            <div style={logoStyle}>
              <Image src={logo} alt="My SVG" width={100} height={100} />
            </div>
            mi<span style={logoTextBoldStyle}>Frens</span>{" "}
            {/* Render the text next to the logo */}
          </div>

          <div style={textStyle}>
            <span style={logoTextBoldStyle}>
              📱 Visit mifrens.tech on mobile to install the app
            </span>
          </div>

          <div style={textStyle}>
            <div style={textStyle}>
              {" "}
              Frens and Magic Combined for Legendary Fun!
            </div>
            <a href="Https://www.docs.mifrens.tech" style={linkStyle}>
              <FaBookOpen />
              Read the miFrens Docs
            </a>
            <a href="https://t.me/magicinternetfrens" style={linkStyle}>
              <FaTelegramPlane />
              Join the Telegram
            </a>
          </div>
        </div>
      ) : (
        <div style={containerStylePWA}>
          <div style={modalStyle}>
            <div style={modalContentStyle}>
              <div style={logoStyleADD}>
                <Image src={mobileLogo} alt="My SVG" width={75} height={75} />
              </div>

              <div style={addToHomeScreenTextStyle} onClick={addToHomeScreen}>
                ADD TO HOME SCREEN
              </div>
            </div>
            <div style={textStyle}>
              To install the app, you need to add this website to your home
              screen.
            </div>
            <div style={textStyle}>
              In your Chrome browser menu, tap the More button and choose{" "}
              <span style={logoTextBoldStyle}>Install App</span> in the options
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default InstallAppPrompt;
