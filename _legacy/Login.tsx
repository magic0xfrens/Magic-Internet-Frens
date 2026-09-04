// @ts-nocheck
import { usePrivy } from "@privy-io/react-auth";
import logo from "./assets/Logo.svg";
import Image from "next/image";
const Login = () => {
  const { login, logout, user } = usePrivy();

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

  const textStyle = {
    fontSize: "39px",

    textAlign: "left", // align text to the left
  };

  const buttonStyle = {
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
    marginTop: "20px",
  };

  const containerStyle = {
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    justifyContent: "flex-start",
    height: "70vh",
    textAlign: "center",
    fontFamily: "sans-serif",
  };

  return (
    <div style={containerStyle} className="rpgui-content rpgui-draggable">
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
      <div
        style={{ width: "90%", position: "relative" }}
        className="rpgui-container framed"
      >
        <p style={{ margin: "20px 0" }}>
          Frens and Magic Combined for Legendary Fun! Sign up with your email,
          we'll create a wallet for you with Privy.
        </p>
        <button onClick={login} style={buttonStyle}>
          Log In
        </button>
      </div>
    </div>
  );
};

export default Login;
