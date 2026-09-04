require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
const ALCHEMY_API_KEY =
  "https://eth-goerli.g.alchemy.com/v2/1c8hdSTXyDuKi8VuXnlzFRYFXdI-VJQP";
const PRIVATE_KEY =
  "a0dc28bcecd0bd940004be51d9acafb8113bf851a0d5feef7eb4e4b2cbb9af0d";
module.exports = {
  solidity: {
    version: "0.8.20",
    networks: {
      testnet: {
        url: `https://eth-sepolia.g.alchemy.com/v2/${ALCHEMY_API_KEY}`,
        accounts: [PRIVATE_KEY],
      },
    },
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
        details: {
          yul: true,
        },
      },
      viaIR: true,
    },
  },
};
