import { useState } from "react";
import { useAccount, useWriteContract, usePublicClient } from "wagmi";
import { parseUnits, type Address } from "viem";
import { CAULDRON } from "@/config/cauldron";
import { KNOWN_QUOTES, NATIVE_QUOTE, quoteMeta, isNativeQuote } from "@/config/quotes";
import { useAllowedQuotes, useCurrentQuote } from "@/hooks/useAllowedQuotes";

const REGISTRY_ROTATION_ABI = [
  {
    type: "function", name: "beginRotation", stateMutability: "nonpayable",
    inputs: [{ name: "bps", type: "uint16" }, { name: "rotator", type: "address" }],
    outputs: [{ type: "uint256" }],
  },
  {
    type: "function", name: "completeRotation", stateMutability: "nonpayable",
    inputs: [
      { name: "quote", type: "address" },
      { name: "quoteAmount", type: "uint256" },
      { name: "tokenAmount", type: "uint256" },
    ],
    outputs: [{ type: "uint256" }],
  },
] as const;

const ROTATOR_ABI = [
  {
    type: "function", name: "setPlan", stateMutability: "nonpayable",
    inputs: [
      { name: "from", type: "address" }, { name: "to", type: "address" },
      { name: "totalIn", type: "uint128" }, { name: "sliceIn", type: "uint128" },
      { name: "minRate", type: "uint256" }, { name: "interval", type: "uint32" },
    ],
    outputs: [],
  },
  { type: "function", name: "cancelPlan", stateMutability: "nonpayable", inputs: [], outputs: [] },
  { type: "function", name: "nextSliceSize", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
] as const;

/**
 * The guild acting as fund manager for its own liquidity.
 *
 * Three steps, deliberately separate rather than one button, because they happen
 * on different timescales: pulling liquidity is instant, converting runs in
 * slices over hours, and redeploying only makes sense once the conversion has
 * actually produced something. Collapsing them would mean guessing the amount
 * the middle step will yield.
 *
 * Every write here is owner-gated on-chain (the timelock), so this is an ADMIN
 * panel — it is shown to everyone for transparency but the buttons will revert
 * for anyone who is not governance.
 */
export function TreasuryRotation({ gen, col }: { gen: number; col: string }) {
    const { address } = useAccount();
    const pc = usePublicClient({ chainId: CAULDRON.chainId });
    const { writeContractAsync } = useWriteContract();
    const { quotes } = useAllowedQuotes();
    const liveQuote = useCurrentQuote(gen);
    const from = quoteMeta(liveQuote);

    const [target, setTarget] = useState<string>("");
    const [pullBps, setPullBps] = useState("3000");   // 30%
    const [sliceCount, setSliceCount] = useState("10");
    const [minRate, setMinRate] = useState("");
    const [busy, setBusy] = useState<string | null>(null);
    const [log, setLog] = useState<string[]>([]);

    const to = quoteMeta((target || NATIVE_QUOTE) as Address);
    const rotator = (CAULDRON as Record<string, unknown>).quoteRotator as Address | undefined;

    // Targets exclude whatever the pair is ALREADY denominated in — rotating an
    // asset into itself is not a thing.
    const targets = quotes.filter(
      (q) => q.address.toLowerCase() !== (liveQuote || NATIVE_QUOTE).toLowerCase(),
    );

    const say = (m: string) => setLog((l) => [m, ...l].slice(0, 6));

    async function begin() {
      if (!rotator) return say("No rotator in the manifest.");
      setBusy("begin");
      try {
        const h = await writeContractAsync({
          address: CAULDRON.registry, abi: REGISTRY_ROTATION_ABI,
          functionName: "beginRotation",
          args: [Number(pullBps), rotator],
        });
        say(`Pulled ${Number(pullBps) / 100}% of the LP → rotator (${h.slice(0, 10)}…)`);
      } catch (e) {
        say(`begin failed: ${(e as Error).message.slice(0, 90)}`);
      } finally { setBusy(null); }
    }

    async function plan() {
      if (!rotator || !pc) return;
      setBusy("plan");
      try {
        // Convert whatever actually landed on the rotator, rather than assuming
        // beginRotation's return value — the pull is bounded by real liquidity.
        const held = isNativeQuote(liveQuote)
          ? await pc.getBalance({ address: rotator })
          : (await pc.readContract({
              address: liveQuote as Address,
              abi: [{ type: "function", name: "balanceOf", stateMutability: "view",
                      inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] }] as const,
              functionName: "balanceOf", args: [rotator],
            })) as bigint;

        if (held === 0n) return say("Rotator holds nothing yet — run step 1 first.");

        const slices = BigInt(Math.max(1, Number(sliceCount)));
        // minRate is "how much `to` per 1 whole unit of `from`", scaled 1e18.
        // Set from the market at vote time: reading it from a pool at execution
        // is exactly the manipulation the floor exists to prevent.
        const rate = parseUnits(minRate || "0", 18);
        if (rate === 0n) return say("Set a minimum rate — a zero floor accepts any fill.");

        const h = await writeContractAsync({
          address: rotator, abi: ROTATOR_ABI, functionName: "setPlan",
          args: [
            (liveQuote || NATIVE_QUOTE) as Address,
            target as Address,
            held,
            held / slices,
            rate,
            3600, // one slice per hour
          ],
        });
        say(`Plan set: ${slices} slices, floor ${minRate} ${to.symbol}/${from.symbol} (${h.slice(0, 10)}…)`);
      } catch (e) {
        say(`plan failed: ${(e as Error).message.slice(0, 90)}`);
      } finally { setBusy(null); }
    }

    async function complete() {
      if (!pc) return;
      setBusy("complete");
      try {
        const bal = (await pc.readContract({
          address: target as Address,
          abi: [{ type: "function", name: "balanceOf", stateMutability: "view",
                  inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] }] as const,
          functionName: "balanceOf", args: [CAULDRON.registry],
        })) as bigint;

        if (bal === 0n) return say(`Registry holds no ${to.symbol} yet — withdraw from the rotator first.`);

        const h = await writeContractAsync({
          address: CAULDRON.registry, abi: REGISTRY_ROTATION_ABI,
          functionName: "completeRotation",
          args: [target as Address, bal, 0n],
        });
        say(`Seeded the ${to.symbol} pair and linked its volume (${h.slice(0, 10)}…)`);
      } catch (e) {
        say(`complete failed: ${(e as Error).message.slice(0, 90)}`);
      } finally { setBusy(null); }
    }

    if (!rotator) return null;

    return (
      <div className="tc-rot">
        <div className="tc-rot__head">
          <div>
            <div className="tc-card__eyebrow" style={{ color: col }}>
              Treasury · the guild manages what the LP is denominated in
            </div>
            <h3 className="tc-rot__title">
              Rotate {from.symbol} → {target ? to.symbol : "…"}
            </h3>
          </div>
          <span className="tc-mono tc-dim">gen {gen}</span>
        </div>

        <p className="tc-rot__lead">
          The LP is currently denominated in <b>{from.symbol}</b>. Convert part of it
          into another approved asset — sell into a stable near a top, hold an
          equity, rotate back later. Conversion runs in slices so it is not one
          large, front-runnable print.
        </p>

        <div className="tc-rot__targets">
          {targets.map((q) => (
            <button
              key={q.address}
              type="button"
              className={target.toLowerCase() === q.address.toLowerCase() ? "on" : ""}
              onClick={() => setTarget(q.address)}
              title={q.blurb}
            >
              {from.symbol} → {q.symbol}
            </button>
          ))}
          {targets.length === 0 && (
            <span className="tc-mono tc-dim">no other approved quote yet</span>
          )}
        </div>

        <div className="tc-rot__grid">
          <label>
            <span className="tc-mono tc-dim">Pull from LP (bps, max 5000)</span>
            <input value={pullBps} onChange={(e) => setPullBps(e.target.value.replace(/[^0-9]/g, ""))} />
          </label>
          <label>
            <span className="tc-mono tc-dim">Slices</span>
            <input value={sliceCount} onChange={(e) => setSliceCount(e.target.value.replace(/[^0-9]/g, ""))} />
          </label>
          <label>
            <span className="tc-mono tc-dim">Min {to.symbol} per {from.symbol}</span>
            <input
              value={minRate}
              onChange={(e) => setMinRate(e.target.value.replace(/[^0-9.]/g, ""))}
              placeholder="e.g. 3000"
            />
          </label>
        </div>

        <div className="tc-rot__steps">
          <button disabled={!target || !!busy} onClick={begin} className="tc-btn">
            1 · Pull {Number(pullBps) / 100}% of the LP
          </button>
          <button disabled={!target || !!busy} onClick={plan} className="tc-btn">
            2 · Schedule the conversion
          </button>
          <button disabled={!target || !!busy} onClick={complete} className="tc-btn">
            3 · Seed the {target ? to.symbol : "new"} pair
          </button>
        </div>

        <p className="tc-rot__note">
          Steps are separate on purpose: the pull is instant, the conversion runs
          over hours in slices, and seeding only makes sense once the conversion
          has actually produced something. All three are governance-gated on-chain.
        </p>

        {log.length > 0 && (
          <ul className="tc-rot__log">
            {log.map((l, i) => <li key={i} className="tc-mono">{l}</li>)}
          </ul>
        )}
      </div>
    );
}
