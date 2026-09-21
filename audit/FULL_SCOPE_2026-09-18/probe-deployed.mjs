// Read-only, pinned-block evidence. No signer, transaction submission, or env
// loading. Public Sepolia endpoint only; bounded request count and timeout.
import { readFileSync } from "node:fs";
import { keccak256, toFunctionSelector } from "viem";

const round = JSON.parse(readFileSync(new URL("../../indexer/deployments/round.json", import.meta.url)));
const routerOnly = process.argv.includes("--router-only");
if (round.chainId !== 11155111) throw new Error("This evidence probe is Sepolia-only");
const endpoint = "https://sepolia.gateway.tenderly.co";
async function rpc(method, params) {
  const response = await fetch(endpoint, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
    signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) throw new Error(`RPC HTTP ${response.status}`);
  return response.json();
}
const chain = await rpc("eth_chainId", []);
if (Number(chain.result) !== round.chainId) throw new Error("Endpoint chain mismatch");
const tip = await rpc("eth_blockNumber", []);
if (!/^0x[0-9a-f]+$/i.test(tip.result ?? "")) throw new Error("Missing block number");
const block = await rpc("eth_getBlockByNumber", [tip.result, false]);
console.log(JSON.stringify({ chainId: round.chainId, block: tip.result, hash: block.result?.hash, observedAt: new Date().toISOString() }));
if (process.argv.includes("--fork-prereqs")) {
  for (const key of ["poolManager", "positionManager"]) {
    const address = round.contracts[key];
    if (!/^0x[0-9a-f]{40}$/i.test(address ?? "")) throw new Error(`Missing ${key}`);
    const response = await rpc("eth_getCode", [address, tip.result]);
    if (!/^0x[0-9a-f]+$/i.test(response.result ?? "")) throw new Error(`Missing code for ${key}`);
    console.log(JSON.stringify({ key, address, codeHash: keccak256(response.result), bytes: (response.result.length - 2) / 2 }));
  }
  // This checks current manager code only, not full historical fork availability.
  process.exit(0);
}
for (const [key, artifact] of Object.entries({
  gachaRouter: "CauldronGachaRouter", registry: "CauldronRegistry", hook: "CauldronHook",
  perpEngine: "PerpEngine", perpVault: "PerpVault",
})) {
  if (routerOnly && key !== "gachaRouter") continue;
  const address = round.contracts[key];
  if (!/^0x[0-9a-f]{40}$/i.test(address ?? "")) throw new Error(`Missing ${key}`);
  const response = await rpc("eth_getCode", [address, tip.result]);
  const code = response.result;
  if (!/^0x[0-9a-f]+$/i.test(code ?? "")) throw new Error(`Missing code for ${key}`);
  const local = JSON.parse(readFileSync(new URL(`../../contracts/solidity/out/${artifact}.sol/${artifact}.json`, import.meta.url)));
  console.log(JSON.stringify({ key, address, codeHash: keccak256(code), deployedBytes: (code.length - 2) / 2,
    localArtifactBytes: (local.deployedBytecode.object.length - 2) / 2,
    caveat: "Length/hash inventory only; immutable and linked-library normalization is not attested" }));
  if (key === "gachaRouter") {
    for (const signature of [
      "playChurn(uint256,uint256,uint256,uint256)", "playChurn(uint256,uint256,uint256)",
      "play(uint256,uint256,uint256,uint256,uint256)",
      "playLiq(uint256,uint256,uint256,uint256,uint256,uint256[])", "openReady(uint256)",
    ]) console.log(JSON.stringify({ signature, selector: toFunctionSelector(signature),
      literalPresent: code.toLowerCase().includes(toFunctionSelector(signature).slice(2).toLowerCase()) }));
  }
}
const selector = toFunctionSelector("playChurn(uint256,uint256,uint256,uint256)");
const result = await rpc("eth_call", [{ to: round.contracts.gachaRouter,
  from: "0x0000000000000000000000000000000000000001", data: selector + "0".repeat(4 * 64) }, tip.result]);
// Emit only diagnostic code and EVM revert bytes, never provider diagnostics.
console.log(JSON.stringify({ call: "playChurn(0,0,0,0)", errorCode: result.error?.code,
  revertData: result.error?.data ?? null, result: result.result ?? null }));
