import { useState, useRef, useEffect, useCallback } from "react";
import { IS_MAINNET, NETWORK_LABEL, EXPLORER_BASE } from "@/config/chains";
import { CAULDRON } from "@/config/cauldron";

// Network-aware caveat so the guide's copy follows VITE_NETWORK.
const NET_NOTE = IS_MAINNET
  ? `live on ${NETWORK_LABEL} — this is mainnet, real ETH.`
  : `on ${NETWORK_LABEL} — you'll need testnet ETH, which has no real value.`;
const short = (a: string) => (a && a.length > 12 ? `${a.slice(0, 8)}…${a.slice(-6)}` : a);

/**
 * FrenHelper — a cute magic-fren assistant (Clippy for wizards). It answers
 * questions about MiFrens & The Cauldron from a self-contained local knowledge
 * base derived from the docs, so it works with zero backend/API dependency.
 *
 * Matching: tokenize the question, score each knowledge entry by keyword hits
 * (weighted) + fuzzy contains, return the best answer with a couple of related
 * follow-up chips. Deterministic, instant, offline.
 */

interface Knowledge {
  id: string;
  /** keywords that route a question here (lowercase). */
  keys: string[];
  /** short question label used for suggestion chips. */
  q: string;
  /** the fren's answer (supports \n paragraphs). */
  a: string;
}

const KB: Knowledge[] = [
  {
    id: "what",
    keys: ["what", "is", "mifrens", "magic", "internet", "frens", "project", "about", "overview", "explain"],
    q: "What is Magic Internet Frens?",
    a: "gm fren! ✨ Magic Internet Frens (MiFrens) is a collection of 2222 fully on-chain pixel wizards — and the home of The Cauldron, an eternal, self-funding token machine on Uniswap v4.\n\nThe Cauldron brews one token at a time. People trade it, it collects fees, and when its 24h volume dies it's REBORN as the next iteration. The cycle never ends — and there's no team withdrawal path.",
  },
  {
    id: "genesis",
    keys: ["genesis", "og", "founder", "1111", "electorate", "voting", "vote", "class", "difference", "forged", "1112", "commons"],
    q: "Genesis vs forged frens?",
    a: "There are two tranches of frens 🧙:\n\n• Genesis frens — ids 1..1111, minted at launch. They're the OGs: they VOTE in governance and EARN fees forever.\n\n• Forged frens — ids 1112..2222, never sold. They're minted only by trading volume through the Crystal Cauldron gacha. They don't earn the dividend and don't vote.\n\nGenesis frens wear a gold/lime ◆ GENESIS badge.",
  },
  {
    id: "earn",
    keys: ["earn", "dividend", "fees", "cast", "spell", "enchant", "income", "yield", "passive", "how", "make", "money"],
    q: "How do genesis frens earn fees?",
    a: "Hold a genesis fren and call castSpell(tokenId) — 'cast the spell' to switch earning ON from that moment (no back-pay). ✦\n\nThe dividend divides fees only among frens that have cast the spell (active shares), so FEWER active casters = each earns MORE. Casting late never dilutes an existing caster.\n\n⚠️ Selling the fren breaks the bond — the new owner must re-cast.",
  },
  {
    id: "fees",
    keys: ["fee", "fees", "tax", "cost", "split", "swap", "trade", "percent", "3%", "how", "much", "charge", "proposer", "guild"],
    q: "What are the fees & how are they split?",
    a: "Every swap pays a hook fee in ETH on BOTH legs (default 3%, adjustable, capped at 10%). The Uniswap LP fee tier is 0. 💰\n\nThe split, from the top of each fee:\n1. 0.5% → the PROPOSER of the live iteration (claimable, never pushed)\n2. 15% guild share → the genesis dividend\n3. 40% of the rest → the legacy buyback (market-buys the token to back the live collection's floor)\n4. what remains → the collection floor share, then the relaunch reserve\n\nNew pools also add a decaying anti-sniper surtax (peaks ~96% at block 0, gone by ~block 30) — 100% to the genesis dividend. Snipers pay the OGs.",
  },
  {
    id: "cycle",
    keys: ["cycle", "eternal", "rebirth", "reborn", "relaunch", "die", "death", "dead", "summon", "iteration", "generation", "next"],
    q: "How does the eternal cycle work?",
    a: "The Cauldron runs one token forever, in a loop 🔮:\n\n1. SUMMON — governance picks the next creature; a fixed-supply token + Uniswap v4 pool are deployed and seeded.\n2. LIVE — people trade, fees flow.\n3. DIE — if rolling 24h volume drops below the death threshold, the token is marked dead.\n4. REBORN — anyone can trigger the rebirth: protocol-owned liquidity migrates, a new token is summoned, holders migrate 1:1.\n\nLiquidity is protocol-owned and recovered each relaunch, so nothing's stranded.",
  },
  {
    id: "token",
    keys: ["token", "mintable", "freezable", "supply", "fixed", "migrate", "migration", "burn", "claim", "vintage", "safe", "rug"],
    q: "Is the token safe / how does migration work?",
    a: "Each iteration token is deliberately boring & safe 🛡️:\n• Fixed supply, minted once — there is NO mint function.\n• Non-freezable — no pause, no blocklist. Only a registry burn that shrinks supply.\n\nMigration is OPTIONAL: keep trading your 'vintage' token, or burn it 1:1 for the new one (claimByBurn). If the pool is short the burn safely reverts — nothing stranded.\n\nAuto-migrate: free for any fren holder, else 0.069 ETH.",
  },
  {
    id: "gacha",
    keys: ["gacha", "crystal", "crystals", "spin", "loot", "reveal", "open", "sealed", "odds", "pity", "lottery", "win", "miss"],
    q: "How does the Crystal Cauldron gacha work?",
    a: "Trading volume forges NFTs! ✨ The loop:\n\n1. Trade — volume banks credit. Buys are weighted 1.5×, sells 0.5×.\n2. Commit — spend credit along a rising curve to enqueue crystals. Nothing mints yet.\n3. Resolve — each crystal rolls from its COMMIT BLOCK's hash (a value that didn't exist when you played, so it can't be foreseen or grinded). A win mints the NFT; a miss builds your pity counter.\n4. Reveal — the NFT arrives UNREVEALED with a placeholder. reveal(tokenId) rolls its rarity and flips the art.\n\n⚠️ Note: a 'crystal' is a TICKET inside the hook, not a tradeable token. What's tradeable is the unrevealed NFT you get on a win.\n\nOdds scale with your ETH play size up to 90% at 0.5 ETH; pity forces a win after 8 misses. Rarity on reveal: 79% Common / 15% Rare / 5% Epic / 1% Ultra.",
  },
  {
    id: "perps",
    keys: ["perp", "perps", "leverage", "long", "short", "liquidation", "liquidate", "margin", "trade", "position", "heatmap", "oracle"],
    q: "How do the perps work?",
    a: "Hook-native leveraged longs & shorts on the live token, with REAL price impact — every open/close/liq is an actual v4 swap. No external oracle. 📈\n\n• Leverage 2×–5× auto-capped by pool depth (governance ceiling 3×).\n• Open fee 6.9% of COLLATERAL (halved for genesis holders); liq penalty 6.9%.\n• Maintenance margin 15%; per-position notional ≤5% of depth; per-side OI ≤30%.\n• Marks use the engine's own on-chain TWAP (5-min window by default) — a flash move can't liquidate you. Spot is used only for execution.\n• Shorts are reflexive: closing buys back exactly the borrowed size, so a close is a real squeeze.\n• Max 64 open positions protocol-wide, so ONE relaunch can always clear the whole book.\n\nThe chart shows a live liquidation heatmap — red long walls below, lime short walls above.",
  },
  {
    id: "floor",
    keys: ["floor", "redemption", "redeem", "recycle", "ratchet", "backing", "backed", "worth", "value", "treasury", "resell", "buyback", "list", "listing", "sell"],
    q: "What is the genesis redemption floor?",
    a: "Every genesis fren has a live floor in WHATEVER token is running now 💎\n\nfloorPerFren() = the genesis reserve ÷ 1111. redeemOgFren(tokenId) pays you that many live tokens from the out-of-range reserve. Your NFT is NOT burned — it moves to the treasury to be resold, so the collection stays 1111 forever.\n\nWhy it ratchets UP:\n• Recycle takes −F from the reserve\n• The resale at 2× floor puts +2F back\n• The paid re-enchant fee adds more\nNet per cycle the reserve GROWS, so the floor only rises.\n\n⚠️ ONLY LIST YOUR FREN WELL ABOVE THE FLOOR. The floor is a hard on-chain bid — list at or below it and an arb bot buys, recycles, and sells for instant profit. Check it first (shown as 'Genesis Floor · X /fren').",
  },
  {
    id: "ceiling",
    keys: ["ceiling", "reverted", "revert", "failed", "cant", "cannot", "stuck", "stranded", "69x", "pump", "moon", "broken", "claimable", "why"],
    q: "Why did my migration or redemption revert?",
    a: "Most likely the token traded ABOVE its reserve ceiling 📈\n\nThe reserve is a single-sided token band parked ~69× below the launch price. It only pays out pure tokens while the pool trades ABOVE it. If the token appreciates THROUGH that ceiling, the band goes in-range and stops delivering — so 1:1 migration, the OG floor and the collection floors all revert rather than pay you short.\n\nCheck registry.floorClaimableNow() — the app surfaces it too.\n\n✅ IMPORTANT: nothing is lost. You keep every token and every fren. It's the EXIT that's paused, and it reopens at the next iteration (the ceiling is chosen fresh at each summon). It's a real known limitation — it's in the docs under 'The reserve ceiling'.",
  },
  {
    id: "collectionfloor",
    keys: ["collection", "legacy", "ledger", "creature", "creatures", "entitlement", "forever", "old", "past", "previous"],
    q: "Do old iteration NFTs keep any value?",
    a: "Yes — every iteration's collection keeps a token-denominated floor FOREVER 🏛️\n\nFees and royalties from a collection's own volume market-buy the live token and credit that collection's entitlement. You can recycle an NFT for its floor share at ANY time (recycleCollectionNFT) — not just at death — and it's resellable at 2× floor, which ratchets that floor up just like the genesis loop.\n\nWhen a brew dies nothing has to migrate: the value lives in the shared reserve, and an entitlement is a pure NUMBER meaning 'X of whatever token is live now'. Every rebirth sizes the new reserve to cover migration + the genesis floor + EVERY collection's entitlement.",
  },
  {
    id: "chain",
    keys: ["chain", "robinhood", "l2", "arbitrum", "orbit", "network", "mainnet", "testnet", "sepolia", "gas", "where"],
    q: "What chain is this on?",
    a: `Built and battle-tested on Sepolia; the deployment target is Robinhood Chain — an Arbitrum Nitro/Orbit L2 with ETH as the native gas token. Right now the app is pointed at ${NETWORK_LABEL}${IS_MAINNET ? " 🚀" : " 🧪"}.\n\nThe L2 differences actually matter and the code is written against them:\n• block.number there is the PARENT chain's number, so the death clock is denominated in wall-clock SECONDS, not blocks.\n• prevrandao is the constant 1 on Orbit — the protocol uses zero of it.\n• The sequencer is first-come-first-served, so ordering is arrival time, not fee bidding.`,
  },
  {
    id: "launch",
    keys: ["launch", "seed", "seeding", "snipe", "sniper", "candle", "green", "progressive", "stream", "fair", "bot", "bots"],
    q: "How is a new launch protected from snipers?",
    a: "Two seeding paths, both anti-snipe 🛡️\n\nATOMIC (green candle) — the reserve is bought into existence with a REAL first-block market buy inside the launch tx, so nothing can front-run it. Plus a surtax that peaks ~96% at block 0 and decays over ~30 blocks, routed 100% to the genesis dividend. The jitter mixes in the pool's LIVE TICK, which moves with the very trade being priced — so there's no predictable cheap block.\n\nPROGRESSIVE (streamed) — the active liquidity streams in over a launch window instead of landing at once. A block-0 whale eats a thin book and pays enormous impact; a later buyer trades into real depth. It's keeperless (every swap nudges it) and the schedule is a pure function of TIME, so nobody can accelerate or block it.",
  },
  {
    id: "governance",
    keys: ["governance", "govern", "dao", "timelock", "vote", "proposal", "control", "owner", "admin", "who", "decides"],
    q: "Who controls it / governance?",
    a: "The 1111 genesis frens are the electorate (ERC721Votes) — they vote on which creature is summoned next. 🗳️\n\nAn audited OpenZeppelin Timelock owns the hook & perp engine and is the registry's IMMUTABLE emergency admin. Every parameter/fee/policy change is schedule → wait → execute. On mainnet the roles move to a multisig with a longer delay.\n\n⚠️ Straight answer on the break-glass: there IS an emergency path (emergencyWithdrawLP / emergencySweep) that can move protocol-owned liquidity to that admin. Anyone telling you this protocol has 'no withdrawal path' hasn't read the code. What bounds it: the admin is immutable (can't be re-pointed later), actions are announced + delayed, the guardian can VETO, and arming one FORCES the redemption exit open so holders can leave at floor first.\n\nWhat it can NEVER do: mint, freeze, pause transfers, or touch a token or NFT in your wallet.\n\nVerify it yourself — read emergencyAdmin(), emergencyDelay() and guardian() on the registry. Ask me 'what are the risks' for more.",
  },
  {
    id: "badges",
    keys: ["badge", "badges", "relic", "relics", "liquidatoor", "trophy", "reward", "nft"],
    q: "What are relics & badges?",
    a: "Relics you can collect 🏅:\n• Unrevealed NFTs — the tradeable placeholder state of a freshly forged creature, before you reveal it.\n• Liquidatoor Badges — when ANY swap tips an underwater perp over, the engine mints a trophy NFT to the swapper who unknowingly did the liquidating. It auto-mints in-swap when there's gas headroom, otherwise it's claimable via claimLiquidatorBadges — a liquidation never fails because of the trophy.\n• Genesis Founder trait — the ◆ GENESIS relic on frens 1..1111.\n\nBadges mint into a separate id range starting at 1,000,000, so they never eat into art supply.",
  },
  {
    id: "addresses",
    keys: ["address", "addresses", "contract", "contracts", "deploy", "deployed", "sepolia", "chain", "verify", "verified", "etherscan", "round"],
    q: "Where's it deployed / contract addresses?",
    a: `Deployed on ${NETWORK_LABEL}${IS_MAINNET ? " 🚀" : " 🧪"}. Core addresses (live from the app config):\n\n• Registry ${short(CAULDRON.registry)}\n• Hook ${short(CAULDRON.hook)}\n• Genesis frens ${short(CAULDRON.mifrens)}\n• Dividend ${short(CAULDRON.dividend)}\n• Timelock ${short(CAULDRON.timelock)}\n\nEach iteration's token/collection/pool rotate every rebirth — read them live from the registry. Verify any address on the explorer: ${EXPLORER_BASE}`,
  },
  {
    id: "risk",
    keys: ["risk", "risks", "danger", "safe", "warning", "lose", "careful", "audit", "audited", "bug", "scam"],
    q: "What are the risks?",
    a: "Read before you ape ⚠️:\n• Experimental DeFi. Audited, invariant-tested and fork-tested against live Uniswap v4 (339 tests) — but bugs can exist. Don't risk what you can't lose.\n• Testnet parameters are NOT production parameters — thin liquidity, short death windows.\n• Token death is a FEATURE — hold without migrating and your vintage token may go illiquid.\n• THE RESERVE CEILING — a big enough pump (~69×) closes migration and the floors until the next iteration. Nothing is lost, but the exit pauses. Ask me 'why did my migration revert'.\n• Leverage can be liquidated; thin pools move hard.\n• Gacha is a lottery — crystals miss.\n• Timelocked governance powers exist (fees, risk params) — but governance CANNOT mint, freeze, or take your tokens or NFTs.\n• Don't list a fren below its floor — arb bots eat it.",
  },
  {
    id: "buy",
    keys: ["buy", "join", "mint", "presale", "get", "acquire", "purchase", "where", "how", "participate"],
    q: "How do I join / get a fren?",
    a: `Hit the JOIN GENESIS button in the header to enter the genesis sale for one of the 1111 OG frens 🧙‍♂️. Then head to The Cauldron to trade the live iteration, spin the Crystal Cauldron, or open a perp.\n\n(Heads up: it's ${NET_NOTE})`,
  },
];

const GREETING =
  "gm gm fren 🔮 your Cauldron guide + certified hype wizard 🧙 ask me ANYTHING about MiFrens — genesis fees, the eternal machine, crystal gacha, perps, wen moon… few understand this magic. LFG 🚀";

interface Msg {
  role: "fren" | "you";
  text: string;
  chips?: string[];
  /** for fren replies: the question that produced this answer (for teaching). */
  q?: string;
  /** true once this answer came from the LLM (not the offline KB). */
  live?: boolean;
}

const ADMIN_KEY = "frenAdmin"; // localStorage slot for the teach secret

function tokenize(s: string): string[] {
  return s.toLowerCase().replace(/[^\w\s]/g, " ").split(/\s+/).filter((w) => w.length > 1);
}

/** Score every KB entry against the question, return the best (or null). */
function answer(question: string): Knowledge | null {
  const tokens = tokenize(question);
  if (!tokens.length) return null;
  let best: Knowledge | null = null;
  let bestScore = 0;
  for (const entry of KB) {
    let score = 0;
    for (const t of tokens) {
      if (entry.keys.includes(t)) score += 3;
      else if (entry.keys.some((k) => k.includes(t) || t.includes(k))) score += 1;
    }
    // small boost if a token appears in the answer text
    const lowerA = entry.a.toLowerCase();
    for (const t of tokens) if (lowerA.includes(t)) score += 0.25;
    if (score > bestScore) {
      bestScore = score;
      best = entry;
    }
  }
  return bestScore >= 1.5 ? best : null;
}

/** Two related suggestions (by shared keywords) to keep the convo going. */
function relatedChips(current: Knowledge): string[] {
  return KB.filter((k) => k.id !== current.id)
    .map((k) => ({ k, overlap: k.keys.filter((x) => current.keys.includes(x)).length }))
    .sort((a, b) => b.overlap - a.overlap)
    .slice(0, 2)
    .map((x) => x.k.q);
}

const STARTER_CHIPS = [
  "What is Magic Internet Frens?",
  "How do genesis frens earn fees?",
  "What is the genesis redemption floor?",
  "How does the eternal cycle work?",
  "How does the gacha work?",
  "What are the risks?",
];

export function FrenHelper() {
  const [open, setOpen] = useState(false);
  const [nudge, setNudge] = useState(true);
  const [input, setInput] = useState("");
  const [msgs, setMsgs] = useState<Msg[]>([
    { role: "fren", text: GREETING, chips: STARTER_CHIPS },
  ]);
  const [typing, setTyping] = useState(false);
  const scrollRef = useRef<HTMLDivElement>(null);

  // Owner "teach mode": the admin secret, loaded from localStorage. When set,
  // teach affordances appear and corrections POST to /api/fren-teach.
  const [admin, setAdmin] = useState<string | null>(null);
  const [teachIdx, setTeachIdx] = useState<number | null>(null);
  const [teachText, setTeachText] = useState("");
  const [teachBusy, setTeachBusy] = useState(false);

  useEffect(() => {
    try {
      setAdmin(localStorage.getItem(ADMIN_KEY));
    } catch {
      /* ignore */
    }
  }, []);

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: "smooth" });
  }, [msgs, typing]);

  // Auto-dismiss the little nudge bubble after a while.
  useEffect(() => {
    const t = setTimeout(() => setNudge(false), 9000);
    return () => clearTimeout(t);
  }, []);

  /** Offline knowledge-base answer (instant, no network). */
  const localReply = useCallback((q: string): Msg => {
    const hit = answer(q);
    return hit
      ? { role: "fren", text: hit.a, chips: relatedChips(hit), q }
      : {
          role: "fren",
          q,
          text:
            "serr my crystal ball's a lil foggy rn 🔮 — smash the /docs grimoire (or grab magicfrens-llm.md) for the full alpha. or hit me with: genesis fees, the eternal machine, crystals, perps, or risks 🧙 wagmi",
          chips: STARTER_CHIPS,
        };
  }, []);

  const send = useCallback(
    async (text: string) => {
      const q = text.trim();
      if (!q) return;
      // capture recent turns for context BEFORE we mutate state
      const history = msgs.slice(-6).map((m) => ({ role: m.role, text: m.text }));
      setMsgs((m) => [...m, { role: "you", text: q }]);
      setInput("");
      setTyping(true);

      // Try the grounded LLM (Gemini via /api/fren-ask). If it's unavailable
      // (no key, offline dev, error) we fall back to the built-in KB so the
      // fren always answers something.
      try {
        const res = await fetch("/api/fren-ask", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ question: q, history }),
        });
        if (res.ok) {
          const data = (await res.json()) as { answer: string | null; source: string };
          if (data.answer) {
            setTyping(false);
            setMsgs((m) => [...m, { role: "fren", text: data.answer as string, q, live: true }]);
            return;
          }
        }
      } catch {
        /* fall through to offline */
      }
      // Offline fallback — tiny delay so the fren feels alive.
      setTimeout(() => {
        setTyping(false);
        setMsgs((m) => [...m, localReply(q)]);
      }, 250);
    },
    [msgs, localReply],
  );

  /** Prompt for the admin secret and store it → unlocks teach mode. */
  const unlockAdmin = useCallback(() => {
    if (admin) {
      // already unlocked → allow logout
      if (confirm("Turn OFF teach mode?")) {
        localStorage.removeItem(ADMIN_KEY);
        setAdmin(null);
      }
      return;
    }
    const secret = prompt("Enter the fren admin secret to enable teach mode:");
    if (secret && secret.trim()) {
      localStorage.setItem(ADMIN_KEY, secret.trim());
      setAdmin(secret.trim());
    }
  }, [admin]);

  /** Save a corrected answer to memory (owner only). */
  const teach = useCallback(
    async (question: string) => {
      if (!admin || !teachText.trim()) return;
      setTeachBusy(true);
      try {
        const res = await fetch("/api/fren-teach", {
          method: "POST",
          headers: { "content-type": "application/json", "x-fren-admin": admin },
          body: JSON.stringify({ question, answer: teachText.trim() }),
        });
        if (res.ok) {
          setMsgs((m) => [
            ...m,
            {
              role: "fren",
              text: "✅ Learned it, fren. I'll answer that better from now on.",
            },
          ]);
          setTeachIdx(null);
          setTeachText("");
        } else if (res.status === 401) {
          alert("Wrong admin secret — teach mode disabled.");
          localStorage.removeItem(ADMIN_KEY);
          setAdmin(null);
        } else {
          const d = await res.json().catch(() => ({}));
          alert(`Couldn't save: ${(d as { error?: string }).error || res.status}`);
        }
      } catch {
        alert("Network error saving correction.");
      } finally {
        setTeachBusy(false);
      }
    },
    [admin, teachText],
  );

  return (
    <>
      {/* Floating launcher */}
      {!open && (
        <button
          className="fh__launcher"
          onClick={() => {
            setOpen(true);
            setNudge(false);
          }}
          aria-label="Ask the magic fren"
        >
          {nudge && (
            <span className="fh__nudge">gm fren — need help? ✦</span>
          )}
          <span className="fh__orb">
            <img
              src="/mifrens-icon.png"
              alt=""
              onError={(e) => {
                (e.currentTarget as HTMLImageElement).style.display = "none";
              }}
            />
            <span className="fh__orb-emoji">🧙</span>
          </span>
        </button>
      )}

      {/* Chat panel */}
      {open && (
        <div className="fh__panel" role="dialog" aria-label="Magic fren helper">
          <div className="fh__head">
            <div className="fh__head-id">
              <span className="fh__avatar">
                <img
                  src="/mifrens-icon.png"
                  alt=""
                  onError={(e) => {
                    (e.currentTarget as HTMLImageElement).style.display = "none";
                  }}
                />
                <span className="fh__avatar-emoji">🧙</span>
              </span>
              <div>
                <div className="fh__name">Cauldron Guide</div>
                <div className="fh__status">
                  <span className="fh__dot" /> online · {admin ? "teach mode ✎" : "asks the grimoire"}
                </div>
              </div>
            </div>
            <div className="fh__head-actions">
              <button
                className={`fh__lock${admin ? " fh__lock--on" : ""}`}
                onClick={unlockAdmin}
                aria-label="Teach mode"
                title={admin ? "Teach mode ON — click to disable" : "Unlock teach mode (owner)"}
              >
                {admin ? "✎" : "🔒"}
              </button>
              <button className="fh__close" onClick={() => setOpen(false)} aria-label="Close">
                ✕
              </button>
            </div>
          </div>

          <div className="fh__scroll" ref={scrollRef}>
            {msgs.map((m, i) => (
              <div key={i} className={`fh__row fh__row--${m.role}`}>
                <div className={`fh__bubble fh__bubble--${m.role}`}>
                  {m.text.split("\n").map((line, j) => (
                    <p key={j}>{line}</p>
                  ))}
                  {m.live && <span className="fh__badge">✦ live</span>}
                </div>

                {/* Owner-only: teach a better answer for this question. */}
                {admin && m.role === "fren" && m.q && teachIdx !== i && (
                  <button
                    className="fh__teach-btn"
                    onClick={() => {
                      setTeachIdx(i);
                      setTeachText(m.text);
                    }}
                  >
                    ✎ teach a better answer
                  </button>
                )}
                {admin && m.role === "fren" && m.q && teachIdx === i && (
                  <div className="fh__teach">
                    <div className="fh__teach-q">Q: {m.q}</div>
                    <textarea
                      value={teachText}
                      onChange={(e) => setTeachText(e.target.value)}
                      placeholder="The correct answer the fren should give…"
                      rows={4}
                    />
                    <div className="fh__teach-actions">
                      <button
                        className="fh__teach-save"
                        disabled={teachBusy || !teachText.trim()}
                        onClick={() => m.q && teach(m.q)}
                      >
                        {teachBusy ? "Saving…" : "Save to memory"}
                      </button>
                      <button
                        className="fh__teach-cancel"
                        onClick={() => {
                          setTeachIdx(null);
                          setTeachText("");
                        }}
                      >
                        Cancel
                      </button>
                    </div>
                  </div>
                )}

                {m.chips && m.role === "fren" && (
                  <div className="fh__chips">
                    {m.chips.map((c) => (
                      <button key={c} className="fh__chip" onClick={() => send(c)}>
                        {c}
                      </button>
                    ))}
                  </div>
                )}
              </div>
            ))}
            {typing && (
              <div className="fh__row fh__row--fren">
                <div className="fh__bubble fh__bubble--fren fh__typing">
                  <span /><span /><span />
                </div>
              </div>
            )}
          </div>

          <form
            className="fh__input"
            onSubmit={(e) => {
              e.preventDefault();
              send(input);
            }}
          >
            <input
              value={input}
              onChange={(e) => setInput(e.target.value)}
              placeholder="Ask the fren anything…"
              aria-label="Ask a question"
            />
            <button type="submit" aria-label="Send" disabled={!input.trim()}>
              ➤
            </button>
          </form>
        </div>
      )}

      <style>{helperStyles}</style>
    </>
  );
}

const helperStyles = `
  .fh__launcher {
    position: fixed; right: 24px; bottom: 24px; z-index: 200;
    border: none; background: none; cursor: pointer;
    display: flex; align-items: center; gap: 10px;
  }
  .fh__nudge {
    background: #FBF7F0; color: #2A1F54;
    font-family: "DM Sans", sans-serif; font-size: 13px; font-weight: 500;
    padding: 9px 14px; border-radius: var(--r-md) var(--r-md) 4px var(--r-md);
    box-shadow: 0 8px 24px rgba(42,31,84,0.28);
    white-space: nowrap; animation: fhPop .4s ease;
  }
  .fh__orb {
    position: relative; width: 62px; height: 62px; border-radius: 50%;
    display: grid; place-items: center; overflow: hidden;
    background: radial-gradient(circle at 35% 30%, #8f6bff, #4b2fb0);
    box-shadow: 0 8px 28px rgba(124,92,252,0.55), 0 0 0 3px rgba(213,253,81,0.5);
    animation: fhFloat 3.2s ease-in-out infinite;
  }
  .fh__orb img { width: 100%; height: 100%; object-fit: cover; }
  .fh__orb-emoji, .fh__avatar-emoji {
    position: absolute; inset: 0; display: grid; place-items: center;
    font-size: 30px; z-index: -1;
  }
  .fh__launcher:hover .fh__orb { transform: scale(1.06); }

  .fh__panel {
    position: fixed; right: 24px; bottom: 24px; z-index: 200;
    width: min(380px, calc(100vw - 32px)); height: min(560px, calc(100vh - 80px));
    display: flex; flex-direction: column; overflow: hidden;
    background: #14101F; border: 1px solid rgba(213,253,81,0.16);
    border-radius: var(--r-md); box-shadow: 0 24px 60px rgba(0,0,0,0.5);
    animation: fhRise .28s cubic-bezier(.2,.8,.2,1);
    font-family: "DM Sans", sans-serif;
  }

  .fh__head {
    display: flex; align-items: center; justify-content: space-between;
    padding: 14px 16px; border-bottom: 1px solid rgba(124,92,252,0.18);
    background: linear-gradient(120deg, rgba(124,92,252,0.22), rgba(20,16,31,0.4));
  }
  .fh__head-id { display: flex; align-items: center; gap: 11px; }
  .fh__avatar {
    position: relative; width: 40px; height: 40px; border-radius: 50%;
    overflow: hidden; display: grid; place-items: center;
    background: radial-gradient(circle at 35% 30%, #8f6bff, #4b2fb0);
    box-shadow: 0 0 0 2px rgba(213,253,81,0.5);
  }
  .fh__avatar img { width: 100%; height: 100%; object-fit: cover; }
  .fh__avatar-emoji { font-size: 20px; }
  .fh__name { font-family: "Cinzel", serif; font-size: 15px; color: #fff; font-weight: 600; }
  .fh__status { font-size: 11px; color: rgba(231,225,245,0.6); display: flex; align-items: center; gap: 5px; }
  .fh__dot { width: 7px; height: 7px; border-radius: 50%; background: #d5fd51; box-shadow: 0 0 8px #d5fd51; }
  .fh__head-actions { display: flex; align-items: center; gap: 4px; }
  .fh__close, .fh__lock {
    background: transparent; border: none; color: rgba(231,225,245,0.6);
    font-size: 14px; cursor: pointer; padding: 6px; border-radius: var(--r-sm); line-height: 1;
  }
  .fh__close:hover, .fh__lock:hover { color: #fff; background: rgba(255,255,255,0.08); }
  .fh__lock--on { color: #d5fd51; }

  .fh__badge {
    display: inline-block; margin-top: 6px; font-size: 10px; letter-spacing: 0.06em;
    color: #d5fd51; opacity: 0.7; font-family: "Fredoka", sans-serif;
  }

  .fh__teach-btn {
    align-self: flex-start; margin-top: 2px;
    background: transparent; border: 1px dashed rgba(213,253,81,0.4);
    color: #d5fd51; border-radius: var(--r-sm); padding: 4px 10px; font-size: 11px;
    cursor: pointer; font-family: "DM Sans", sans-serif;
  }
  .fh__teach-btn:hover { background: rgba(213,253,81,0.1); }
  .fh__teach {
    align-self: stretch; background: rgba(213,253,81,0.06);
    border: 1px solid rgba(213,253,81,0.28); border-radius: var(--r-sm); padding: 10px;
  }
  .fh__teach-q {
    font-size: 11px; color: rgba(231,225,245,0.6); margin-bottom: 6px;
    overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
  }
  .fh__teach textarea {
    width: 100%; background: #14101F; border: 1px solid rgba(124,92,252,0.3);
    border-radius: var(--r-sm); color: #E7E1F5; font-family: "DM Sans", sans-serif;
    font-size: 13px; padding: 8px 10px; resize: vertical; outline: none;
  }
  .fh__teach textarea:focus { border-color: rgba(213,253,81,0.5); }
  .fh__teach-actions { display: flex; gap: 8px; margin-top: 8px; }
  .fh__teach-save {
    background: #d5fd51; color: #14101F; border: none; border-radius: var(--r-sm);
    padding: 6px 14px; font-size: 12px; font-weight: 600; cursor: pointer;
    font-family: "Fredoka", sans-serif;
  }
  .fh__teach-save:disabled { opacity: 0.4; cursor: default; }
  .fh__teach-cancel {
    background: transparent; color: rgba(231,225,245,0.6);
    border: 1px solid rgba(124,92,252,0.3); border-radius: var(--r-sm);
    padding: 6px 14px; font-size: 12px; cursor: pointer; font-family: "DM Sans", sans-serif;
  }

  .fh__scroll { flex: 1; overflow-y: auto; padding: 16px; display: flex; flex-direction: column; gap: 14px; }
  .fh__row { display: flex; flex-direction: column; gap: 8px; }
  .fh__row--you { align-items: flex-end; }
  .fh__row--fren { align-items: flex-start; }

  .fh__bubble {
    max-width: 88%; padding: 11px 14px; border-radius: var(--r-md); font-size: 13.5px; line-height: 1.55;
  }
  .fh__bubble p { margin: 0; }
  .fh__bubble p + p { margin-top: 8px; }
  .fh__bubble--fren {
    background: #221a35; color: #E7E1F5; border-radius: var(--r-md) var(--r-md) var(--r-md) 4px;
    border: 1px solid rgba(124,92,252,0.2);
  }
  .fh__bubble--you {
    background: #d5fd51; color: #14101F; border-radius: var(--r-md) var(--r-md) 4px var(--r-md); font-weight: 500;
  }

  .fh__chips { display: flex; flex-wrap: wrap; gap: 7px; }
  .fh__chip {
    background: rgba(213,253,81,0.08); color: #d5fd51;
    border: 1px solid rgba(213,253,81,0.28); border-radius: var(--r-sm);
    padding: 7px 11px; font-size: 12px; font-family: "DM Sans", sans-serif;
    cursor: pointer; text-align: left; transition: background .15s ease;
  }
  .fh__chip:hover { background: rgba(213,253,81,0.18); }

  .fh__typing { display: flex; gap: 4px; align-items: center; }
  .fh__typing span {
    width: 7px; height: 7px; border-radius: 50%; background: #7C5CFC;
    animation: fhBlink 1.2s infinite ease-in-out;
  }
  .fh__typing span:nth-child(2) { animation-delay: .2s; }
  .fh__typing span:nth-child(3) { animation-delay: .4s; }

  .fh__input {
    display: flex; gap: 8px; padding: 12px; border-top: 1px solid rgba(124,92,252,0.18);
    background: rgba(20,16,31,0.6);
  }
  .fh__input input {
    flex: 1; background: #1c1630; border: 1px solid rgba(124,92,252,0.25);
    border-radius: var(--r-md); padding: 10px 16px; color: #E7E1F5;
    font-family: "DM Sans", sans-serif; font-size: 13.5px; outline: none;
  }
  .fh__input input:focus { border-color: rgba(213,253,81,0.5); }
  .fh__input input::placeholder { color: rgba(231,225,245,0.4); }
  .fh__input button {
    width: 40px; height: 40px; border-radius: 50%; border: none; flex-shrink: 0;
    background: #d5fd51; color: #14101F; font-size: 15px; cursor: pointer;
    transition: transform .15s ease, opacity .15s ease;
  }
  .fh__input button:hover:not(:disabled) { transform: scale(1.08); }
  .fh__input button:disabled { opacity: 0.4; cursor: default; }

  @keyframes fhFloat { 0%,100% { transform: translateY(0); } 50% { transform: translateY(-6px); } }
  @keyframes fhRise { from { opacity: 0; transform: translateY(20px) scale(.96); } to { opacity: 1; transform: none; } }
  @keyframes fhPop { from { opacity: 0; transform: translateX(10px); } to { opacity: 1; transform: none; } }
  @keyframes fhBlink { 0%,80%,100% { opacity: .3; transform: scale(.8); } 40% { opacity: 1; transform: scale(1); } }

  @media (max-width: 480px) {
    .fh__nudge { display: none; }
  }
`;
