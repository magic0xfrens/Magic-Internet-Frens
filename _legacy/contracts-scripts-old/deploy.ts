/**
 * deploy.ts — Deploys the Magic Internet Frens protocol on OP_NET (Bitcoin L1).
 *
 * Deployment order:
 *   1. Oracle       — BTC/USD price feed
 *   2. MIF Token    — stablecoin (OP_20)
 *   3. FREN Token   — governance/staking token (OP_20)
 *   4. MiFrens NFT   — tiered membership NFT
 *   5. Cauldron     — CDP lending engine
 *
 * Post-deploy wiring:
 *   - MIF.addMinter(Cauldron)
 *   - FREN.addRewardDistributor(Cauldron)
 *   - NFT.addCauldron(Cauldron)
 *   - Oracle.setPrice(initialPrice)
 *
 * Usage:
 *   npx tsx contracts/scripts/deploy.ts
 *   npx tsx contracts/scripts/deploy.ts --network testnet
 *   npx tsx contracts/scripts/deploy.ts --network regtest
 */

import { TransactionFactory } from "@btc-vision/transaction";
import { JSONRpcProvider, getContract } from "opnet";
import { networks, Network } from "@btc-vision/bitcoin";
import * as fs from "fs";
import * as path from "path";

// ---------------------------------------------------------------------------
// Network presets
// ---------------------------------------------------------------------------

interface NetworkPreset {
  name: string;
  rpcUrl: string;
  network: Network;
}

const NETWORK_PRESETS: Record<string, NetworkPreset> = {
  regtest: {
    name: "Regtest",
    rpcUrl: "http://localhost:9001",
    network: networks.regtest,
  },
  testnet: {
    name: "OPNet Testnet",
    rpcUrl: "https://testnet.opnet.org",
    network: networks.testnet,
  },
  mainnet: {
    name: "Mainnet",
    rpcUrl: "https://mainnet.opnet.org",
    network: networks.bitcoin,
  },
};

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface DeployedContract {
  name: string;
  address: string;
  txHash: string;
}

// ---------------------------------------------------------------------------
// CLI argument parsing
// ---------------------------------------------------------------------------

function parseArgs(): { networkName: string } {
  const args = process.argv.slice(2);
  let networkName = "regtest";

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--network" && args[i + 1]) {
      networkName = args[i + 1];
      i++;
    }
  }

  if (!NETWORK_PRESETS[networkName]) {
    console.error(
      `Unknown network "${networkName}". Available: ${Object.keys(NETWORK_PRESETS).join(", ")}`,
    );
    process.exit(1);
  }

  return { networkName };
}

// ---------------------------------------------------------------------------
// Deploy helpers
// ---------------------------------------------------------------------------

async function deployContract(
  name: string,
  wasmPath: string,
  provider: JSONRpcProvider,
  network: Network,
  wallet: { keypair: unknown; mldsaKeypair: unknown; address: string },
): Promise<DeployedContract> {
  console.log(`  Deploying ${name}...`);

  const wasmBytes = fs.readFileSync(wasmPath);

  // Use TransactionFactory for deployment (the ONLY correct way)
  // Backend: signer and mldsaSigner MUST be provided
  const factory = new TransactionFactory();
  const deployTx = await factory.signDeployment({
    bytecode: wasmBytes,
    signer: wallet.keypair,
    mldsaSigner: wallet.mldsaKeypair,
    network,
    feeRate: 10,
    priorityFee: 1000n,
    from: wallet.address,
  });

  // Broadcast the signed transaction
  const receipt = await provider.sendRawTransaction(
    deployTx.serialize(),
  );

  const address = receipt?.contractAddress ?? `pending_${name}`;
  const txHash = receipt?.transactionId ?? "pending";

  console.log(`  ${name} deployed at: ${address}`);
  console.log(`  tx: ${txHash}`);

  return { name, address, txHash };
}

async function configureContract(
  contractName: string,
  address: string,
  method: string,
  args: unknown[],
  provider: JSONRpcProvider,
  network: Network,
  wallet: { keypair: unknown; mldsaKeypair: unknown; address: string },
): Promise<void> {
  console.log(`  ${contractName}.${method}()...`);

  const contract = getContract(address, provider, wallet.address);

  // Simulate first
  const contractAny = contract as Record<string, (...a: unknown[]) => Promise<unknown>>;
  const sim = await contractAny[method](...args);

  if (sim && typeof sim === "object" && "error" in sim) {
    throw new Error(`${contractName}.${method}() simulation failed: ${(sim as { error: string }).error}`);
  }

  // Send transaction — backend: MUST provide signer and mldsaSigner
  const sendable = sim as {
    sendTransaction: (params: Record<string, unknown>) => Promise<unknown>;
  };

  await sendable.sendTransaction({
    signer: wallet.keypair, // Backend: MUST provide
    mldsaSigner: wallet.mldsaKeypair, // Backend: MUST provide
    refundTo: wallet.address,
    maximumAllowedSatToSpend: 50_000n,
    feeRate: 10,
    priorityFee: 1000n,
    network,
  });

  console.log(`  done.`);
}

// ---------------------------------------------------------------------------
// Full deploy orchestration
// ---------------------------------------------------------------------------

async function deployAll(preset: NetworkPreset) {
  const { network, rpcUrl } = preset;
  const provider = new JSONRpcProvider(rpcUrl, network);

  // Load wallet from environment
  const privateKey = process.env.DEPLOYER_PRIVATE_KEY;
  if (!privateKey) {
    console.error("ERROR: Set DEPLOYER_PRIVATE_KEY environment variable");
    process.exit(1);
  }

  // TODO: Initialize wallet keypair from privateKey
  // const wallet = Wallet.fromPrivateKey(privateKey, network);
  const wallet = {
    keypair: null as unknown, // placeholder — replace with real keypair
    mldsaKeypair: null as unknown, // placeholder — replace with real MLDSA keypair
    address: "", // placeholder
  };

  console.log(`\nDeploying Magic Internet Frens on "${preset.name}"...\n`);

  const buildDir = path.resolve(__dirname, "../build");
  const deployed: Record<string, DeployedContract> = {};

  // 1. Oracle
  console.log("[1/5] Oracle");
  deployed.Oracle = await deployContract(
    "Oracle",
    path.join(buildDir, "oracle.wasm"),
    provider,
    network,
    wallet,
  );

  // 2. MIF Token
  console.log("[2/5] MIF Token");
  deployed.MIF = await deployContract(
    "MIFToken",
    path.join(buildDir, "mif.wasm"),
    provider,
    network,
    wallet,
  );

  // 3. FREN Token
  console.log("[3/5] FREN Token");
  deployed.FREN = await deployContract(
    "FRENToken",
    path.join(buildDir, "fren.wasm"),
    provider,
    network,
    wallet,
  );

  // 4. MiFrens NFT
  console.log("[4/5] MiFrens NFT");
  deployed.NFT = await deployContract(
    "MiFrens",
    path.join(buildDir, "nft.wasm"),
    provider,
    network,
    wallet,
  );

  // 5. Cauldron
  console.log("[5/5] Cauldron");
  deployed.Cauldron = await deployContract(
    "Cauldron",
    path.join(buildDir, "cauldron.wasm"),
    provider,
    network,
    wallet,
  );

  // --- Post-deploy wiring ---
  console.log("\nConfiguring permissions...\n");

  // MIF: whitelist Cauldron as minter
  await configureContract(
    "MIF",
    deployed.MIF.address,
    "addMinter",
    [deployed.Cauldron.address],
    provider,
    network,
    wallet,
  );

  // FREN: whitelist Cauldron as reward distributor
  await configureContract(
    "FREN",
    deployed.FREN.address,
    "addRewardDistributor",
    [deployed.Cauldron.address],
    provider,
    network,
    wallet,
  );

  // NFT: whitelist Cauldron to lock/unlock NFTs
  await configureContract(
    "MiFrens",
    deployed.NFT.address,
    "addCauldron",
    [deployed.Cauldron.address],
    provider,
    network,
    wallet,
  );

  // Oracle: set initial BTC price ($60,000 with 18 decimals)
  const initialPrice = 60_000n * 10n ** 18n;
  await configureContract(
    "Oracle",
    deployed.Oracle.address,
    "setPrice",
    [initialPrice],
    provider,
    network,
    wallet,
  );

  // --- Summary ---
  console.log("\n========================================");
  console.log("  Deployment Summary");
  console.log("========================================");
  for (const [key, info] of Object.entries(deployed)) {
    console.log(`  ${key.padEnd(12)} => ${info.address}`);
  }
  console.log("========================================\n");

  // Persist deployed addresses
  const deploymentsDir = path.resolve(__dirname, "../deployments");
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir, { recursive: true });
  }
  fs.writeFileSync(
    path.join(deploymentsDir, `${preset.name.toLowerCase().replace(/\s+/g, "-")}.json`),
    JSON.stringify(deployed, null, 2),
  );
  console.log("Addresses saved to deployments/");

  return deployed;
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

async function main() {
  const { networkName } = parseArgs();
  const preset = NETWORK_PRESETS[networkName];
  await deployAll(preset);
}

main().catch((err) => {
  console.error("Deployment failed:", err);
  process.exit(1);
});
