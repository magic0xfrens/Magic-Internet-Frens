// ─────────────────────────────────────────────────────────────────────────────
//  LAUNCH POKE KEEPER
// ─────────────────────────────────────────────────────────────────────────────
//
//  Calls CauldronSeeder.poke() across the launch window so the liquidity stream
//  and the tranched prime buy advance without waiting on an outside buyer.
//
//  WHY THIS EXISTS. The seeder streams on `poke()` or on the hook's in-swap
//  `pokeInSwap()`. The in-swap path only fires when somebody trades — so a launch
//  with no trades never streams. Round 35 proved it the hard way: the 900s window
//  closed with `placedWad` still equal to `seedFloorWad` (no poke had EVER run)
//  and 76.5% of the launch liquidity still sitting in the seeder.
//
//  The hybrid green candle now guarantees a trade at ignition, which starts the
//  flywheel — this keeper is the belt-and-braces that guarantees it FINISHES even
//  if the pool goes quiet mid-window.
//
//  SAFE BY CONSTRUCTION. `poke()` is permissionless and its target is a pure
//  function of elapsed time (SeedLib.deployedTargetWad), so it cannot be
//  accelerated, over-deployed or front-run into doing something different. The
//  worst a broken keeper can do is waste its own gas: an early poke is a no-op
//  (`_pendingStep` returns 0 below `minStepWad`), and a late one simply catches up.
//
//  It runs INSIDE the indexer service rather than as its own Railway service, so
//  it ships with the deploy that is already wired. It is INERT unless
//  SEED_KEEPER_PK is set, so nothing changes for a deployment that does not want
//  a hot key present.
//
//  Env:
//    SEED_KEEPER_PK        hot key for poking (omit -> keeper disabled)
//    PONDER_RPC_URL        reused; first entry is used for sending
//    SEED_KEEPER_INTERVAL  seconds between polls (default 20)

import { readFileSync } from "node:fs";
import { createPublicClient, createWalletClient, http, formatEther } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { defineChain } from "viem";

const ABI = [
  { type: "function", name: "poke", inputs: [], outputs: [], stateMutability: "nonpayable" },
  { type: "function", name: "seeding", inputs: [], outputs: [{ type: "bool" }], stateMutability: "view" },
  { type: "function", name: "complete", inputs: [], outputs: [{ type: "bool" }], stateMutability: "view" },
  { type: "function", name: "placedWad", inputs: [], outputs: [{ type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "primePending", inputs: [], outputs: [{ type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "primeSpent", inputs: [], outputs: [{ type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "primeBudget", inputs: [], outputs: [{ type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "startTs", inputs: [], outputs: [{ type: "uint64" }], stateMutability: "view" },
  { type: "function", name: "window", inputs: [], outputs: [{ type: "uint64" }], stateMutability: "view" },
  { type: "function", name: "seedFloorWad", inputs: [], outputs: [{ type: "uint256" }], stateMutability: "view" },
  { type: "function", name: "minStepWad", inputs: [], outputs: [{ type: "uint256" }], stateMutability: "view" },
];

const WAD = 10n ** 18n;

/// Mirror of SeedLib.deployedTargetWad. Computed client-side so the keeper only
/// pays gas when a poke would actually DO something — `poke()` is a no-op when
/// the step is below `minStepWad`, and a no-op still costs a transaction.
function deployedTargetWad(startTs, window, nowTs, seedFloorWad) {
  if (seedFloorWad > WAD) seedFloorWad = WAD;
  if (window === 0n || nowTs >= startTs + window) return WAD;
  if (nowTs <= startTs) return seedFloorWad;
  return seedFloorWad + ((WAD - seedFloorWad) * (nowTs - startTs)) / window;
}

export async function startSeedKeeper() {
  const pk = process.env.SEED_KEEPER_PK;
  if (!pk) {
    console.log("[keeper] SEED_KEEPER_PK unset - launch poke keeper disabled");
    return;
  }

  const manifest = JSON.parse(
    readFileSync(new URL("./deployments/round.json", import.meta.url), "utf8"),
  );
  const seeder = manifest.contracts?.seeder;
  if (!seeder) {
    console.log("[keeper] no `seeder` in round.json - nothing to poke");
    return;
  }

  //  ── THE KEEPER MUST SIGN FOR THE CHAIN THE MANIFEST PINS ─────────────────
  //  This used to be `chain: sepolia`, hardcoded, so on any other chain every
  //  transaction was signed with chainId 11155111 and rejected by the node —
  //  and the rejection was swallowed by the catch below as "poke skipped", once
  //  every 20 seconds, forever. The launch-liquidity stream simply never
  //  advanced, with nothing in the logs saying why. Same class as the frontend
  //  Critical: a hardcoded chain identity that fails quietly.
  const CHAIN_RPCS = {
    11155111: "https://ethereum-sepolia-rpc.publicnode.com",
    5042002: "https://rpc.testnet.arc.network",
    4663: "https://rpc.mainnet.chain.robinhood.com",
    46630: "https://rpc.testnet.chain.robinhood.com",
  };
  const chainId = Number(manifest.chainId);
  const rpc = (process.env.PONDER_RPC_URL ?? CHAIN_RPCS[chainId] ?? "")
    .split(",")[0]
    .trim();
  if (!rpc) {
    console.error(`[keeper] NO RPC for chain ${chainId} — set PONDER_RPC_URL. Keeper not started.`);
    return;
  }
  const intervalMs = Number(process.env.SEED_KEEPER_INTERVAL ?? 20) * 1000;

  const account = privateKeyToAccount(pk.startsWith("0x") ? pk : `0x${pk}`);
  //  Minimal chain object: viem needs an id to sign with and an RPC to talk to.
  //  Nothing else here is used by `writeContract`.
  const chain = defineChain({
    id: chainId,
    name: `chain-${chainId}`,
    nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
    rpcUrls: { default: { http: [rpc] }, public: { http: [rpc] } },
  });
  const pub = createPublicClient({ chain, transport: http(rpc) });
  const wallet = createWalletClient({ account, chain, transport: http(rpc) });

  //  Prove the identity before signing anything. A keeper pointed at the wrong
  //  chain can never succeed, so retrying it every 20 s is noise, not recovery —
  //  refuse LOUDLY instead of skipping quietly.
  try {
    const live = await pub.getChainId();
    if (live !== chainId) {
      console.error(
        `[keeper] CHAIN MISMATCH — round.json pins chain ${chainId} but ${rpc} answers ${live}. ` +
          `Every poke would be signed for the wrong chain and rejected. Keeper not started.`,
      );
      return;
    }
  } catch (e) {
    console.error(`[keeper] cannot reach ${rpc}: ${String(e?.shortMessage ?? e?.message ?? e)}. Keeper not started.`);
    return;
  }

  console.log(`[keeper] poking ${seeder} every ${intervalMs / 1000}s as ${account.address}`);

  let stop = false;
  // Never let two pokes overlap: a second tx from the same account with the same
  // nonce is a guaranteed "replacement transaction underpriced", and on a slow RPC
  // the interval can fire again before the previous receipt lands.
  let inFlight = false;

  const tick = async () => {
    if (stop || inFlight) return;
    inFlight = true;
    try {
      const read = (functionName) => pub.readContract({ address: seeder, abi: ABI, functionName });
      const [seeding, complete, placed, primeDue, startTs, window, floor, minStep] =
        await Promise.all([
          read("seeding"), read("complete"), read("placedWad"), read("primePending"),
          read("startTs"), read("window"), read("seedFloorWad"), read("minStepWad"),
        ]);

      if (!seeding) return;                     // no campaign yet (pre-ignition)
      if (complete && primeDue === 0n) return;  // liquidity done, budget closed out

      // Only send when the chain would actually move. `poke()` deploys
      // `target - placed`, and skips anything below `minStepWad` unless it is the
      // final step — so replicate that test here instead of paying for a no-op.
      const now = BigInt(Math.floor(Date.now() / 1000));
      const target = deployedTargetWad(startTs, window, now, floor);
      const step = target > placed ? target - placed : 0n;
      const stepWorthIt = step > 0n && (step >= minStep || target >= WAD);
      if (!stepWorthIt && primeDue === 0n) return;

      const { request } = await pub.simulateContract({
        address: seeder, abi: ABI, functionName: "poke", account,
      });
      const hash = await wallet.writeContract(request);
      const rcpt = await pub.waitForTransactionReceipt({ hash, timeout: 120_000 });
      const after = await read("placedWad");
      console.log(
        `[keeper] poke ${rcpt.status} ${hash} placed=${(Number(after) / 1e16).toFixed(1)}%` +
          (primeDue > 0n ? ` prime=${formatEther(primeDue)}Ξ` : ""),
      );
    } catch (e) {
      // A revert here is not fatal and usually is not even a fault: the step can
      // become 0 between simulate and send, and public RPCs rate-limit. Log and
      // retry on the next tick rather than taking the indexer down with us.
      const msg = String(e?.shortMessage ?? e?.message ?? e);
      //  A chain-id rejection is NOT the benign "step became 0" case this catch
      //  was written for: it can never succeed, so it must not look like routine
      //  noise in the logs.
      const identity = /chain|chainId|EIP-155|invalid sender/i.test(msg);
      (identity ? console.error : console.log)(
        `[keeper] poke ${identity ? "REJECTED (chain identity?)" : "skipped"}: ${msg.slice(0, 160)}`,
      );
    } finally {
      inFlight = false;
    }
  };

  const timer = setInterval(tick, intervalMs);
  tick();
  const shutdown = () => { stop = true; clearInterval(timer); };
  process.on("SIGTERM", shutdown);
  process.on("SIGINT", shutdown);
}
