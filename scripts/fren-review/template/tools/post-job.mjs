#!/usr/bin/env node
/**
 * Post one Fren Review deep review to IMD as a paid `job.open` (imd.fun/docs, "Paid requests"):
 * six steps for one price — four hunters, a report, a verifier (jobs/deep-review.json).
 *
 *   node tools/post-job.mjs --commit <sha> --slot 0 --dry
 *   node tools/post-job.mjs --commit <sha> --foci perp-book,rotation,vault,value-flow --prior <jobId>,<jobId> --quote
 *   node tools/post-job.mjs --fuzz --commit <sha> --runs 100000 --quote      # a fuzz campaign (jobs/fuzz.json)
 *
 * --slot N   picks foci N*4 .. N*4+3 of the rotation below, so consecutive jobs cover every focus
 *            every three jobs; --foci names four explicitly.
 * --fuzz     post jobs/fuzz.json instead: CPU-only seats fuzz test/CauldronFuzz.sol's prop_ functions,
 *            --runs times each (1,000–10,000,000; default 100,000). No agents, same price.
 * --prior    earlier jobs whose accepted report and findings files are attached as `inputs`, so the
 *            hunters build on them (they land in .imd/reads/artifacts/). Needs network.
 * --dry      fill and check against the documented limits, print the body; nothing is sent.
 * --quote    also ask IMD for a quote. Free: nothing is charged until the paid submit, and an
 *            invalid body comes back 422 with the problems. Prints the order and stops.
 * --pay      quote, then PAY (0.5 IMD) with the wallet in PRIVATE_KEY and wait for admission; the
 *            admitted job id is appended to ledger/jobs.txt. Needs `npm ci --prefix tools`.
 * (default)  quote, then fetch the 402 payment challenge and print it; nothing is signed.
 *
 *   node tools/post-job.mjs --approve [imd]   one-time ERC-20 approval letting Permit2 move up to
 *                                             <imd> IMD (default 5, ten jobs) from PRIVATE_KEY's wallet.
 *
 * IMD_PAID_TOKEN (64 hex, `openssl rand -hex 32`) names your orders; keep it to read them later.
 * ETH_RPC_URL (default a public Ethereum RPC) is read for balances and the approval. A quote lives
 * 600 s. The signing follows IMD's own explorer (explorer.imd.fun/request): an x402 v2 "exact"
 * Permit2 payment plus an EIP-712 QuoteApproval of that payment for this quote.
 */
import { readFileSync, appendFileSync } from "node:fs";
import { createHash, randomUUID } from "node:crypto";

const API = process.env.IMD_API ?? "https://api.imd.fun";
const ROOT = new URL("../", import.meta.url);
const argv = process.argv.slice(2);
const flag = (name) => argv.includes(`--${name}`);
const opt = (name) => {
  const i = argv.indexOf(`--${name}`);
  return i >= 0 && i + 1 < argv.length ? argv[i + 1] : undefined;
};
const die = (msg) => { console.error(msg); process.exit(1); };
const RPC = process.env.ETH_RPC_URL ?? "https://ethereum-rpc.publicnode.com";
const PERMIT2 = "0x000000000022D473030F116dDEE9F6B43aC78BA3";

//  IMD's canonical JSON and hash (sorted keys, integers only; sha256, hex without 0x). Checked
//  against a live challenge: it reproduces quoteHash, requesterScopeHash and inputHash exactly.
const canon = (v) => {
  if (v === null) return "null";
  switch (typeof v) {
    case "boolean": return v ? "true" : "false";
    case "number":
      if (!Number.isInteger(v)) throw new Error("cannot canonicalize a non-integer number");
      return JSON.stringify(v === 0 ? 0 : v);
    case "string": return JSON.stringify(v);
    case "object":
      if (Array.isArray(v)) return `[${v.map(canon).join(",")}]`;
      return `{${Object.keys(v).sort().map((k) => {
        if (v[k] === undefined) throw new Error(`cannot canonicalize undefined at ${k}`);
        return `${JSON.stringify(k)}:${canon(v[k])}`;
      }).join(",")}}`;
    default: throw new Error(`cannot canonicalize a ${typeof v}`);
  }
};
const hashOf = (v) => createHash("sha256").update(Buffer.from(canon(v), "utf8")).digest("hex");

async function wallet() {
  const pk = process.env.PRIVATE_KEY ?? "";
  if (!/^(0x)?[0-9a-fA-F]{64}$/.test(pk)) die("set PRIVATE_KEY to the paying wallet's key (it is never printed)");
  let viem, accounts, chains;
  try {
    viem = await import("viem");
    accounts = await import("viem/accounts");
    chains = await import("viem/chains");
  } catch { die("paying needs the tool dependencies: npm ci --prefix tools"); }
  const account = accounts.privateKeyToAccount(pk.startsWith("0x") ? pk : `0x${pk}`);
  const pub = viem.createPublicClient({ chain: chains.mainnet, transport: viem.http(RPC) });
  const walletClient = viem.createWalletClient({ account, chain: chains.mainnet, transport: viem.http(RPC) });
  return { viem, account, pub, walletClient };
}

const ERC20 = [
  { type: "function", name: "balanceOf", stateMutability: "view", inputs: [{ type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "allowance", stateMutability: "view", inputs: [{ type: "address" }, { type: "address" }], outputs: [{ type: "uint256" }] },
  { type: "function", name: "approve", stateMutability: "nonpayable", inputs: [{ type: "address" }, { type: "uint256" }], outputs: [{ type: "bool" }] },
];

if (flag("approve")) {
  const imd = Number(argv[argv.indexOf("--approve") + 1] ?? 5);
  const amountImd = Number.isFinite(imd) && imd > 0 ? imd : 5;
  const caps = await (await fetch(`${API}/requests/capabilities`)).json();
  const asset = caps.actions.find((a) => a.action === "job.open").payment.asset;
  const { viem, account, pub, walletClient } = await wallet();
  const amount = viem.parseUnits(String(amountImd), 18);
  const [eth, bal, allowance] = await Promise.all([
    pub.getBalance({ address: account.address }),
    pub.readContract({ address: asset, abi: ERC20, functionName: "balanceOf", args: [account.address] }),
    pub.readContract({ address: asset, abi: ERC20, functionName: "allowance", args: [account.address, PERMIT2] }),
  ]);
  console.error(`wallet ${account.address}: ${viem.formatEther(eth)} ETH, ${viem.formatUnits(bal, 18)} IMD, Permit2 allowance ${viem.formatUnits(allowance, 18)} IMD`);
  if (allowance >= amount) { console.error("allowance already covers it; nothing sent"); process.exit(0); }
  if (eth === 0n) die("the wallet has no ETH on Ethereum mainnet for the approval's gas");
  const hash = await walletClient.writeContract({ address: asset, abi: ERC20, functionName: "approve", args: [PERMIT2, amount] });
  console.error(`approve(Permit2, ${amountImd} IMD) sent: ${hash}`);
  const receipt = await pub.waitForTransactionReceipt({ hash });
  console.error(`mined in block ${receipt.blockNumber}, status ${receipt.status}`);
  process.exit(receipt.status === "success" ? 0 : 1);
}

//  Ordered so that any four consecutive entries spread across the machine.
const FOCI = ["perp-book", "value-flow", "hook-deltas", "rotation", "lifecycle", "genesis-nft",
              "perp-requote", "vault", "registry-facet", "randomness", "governance", "seed-deploy"];

const commit = opt("commit") ?? "";
if (!/^[0-9a-f]{40}$/.test(commit)) die("--commit must be the review repository's round commit, 40 lowercase hex");
const fuzz = flag("fuzz");
const fill = (vars) => function f(value) {
  if (typeof value === "string") {
    const whole = Object.keys(vars).find((k) => value === k);
    if (whole && typeof vars[whole] === "number") return vars[whole];
    return Object.entries(vars).reduce((s, [k, v]) => s.split(k).join(String(v)), value);
  }
  if (Array.isArray(value)) return value.map(f);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).filter(([k]) => !k.startsWith("_")).map(([k, v]) => [k, f(v)]));
  }
  return value;
};
const template = (name) => JSON.parse(readFileSync(new URL(`jobs/${name}.json`, ROOT), "utf8"));

let foci = [];
let input;
if (fuzz) {
  const runs = Number(opt("runs") ?? 100_000);
  if (!Number.isInteger(runs) || runs < 1_000 || runs > 10_000_000) die("--runs must be 1,000–10,000,000");
  input = fill({ "<COMMIT>": commit, "<RUNS>": runs })(template("fuzz"));
} else {
  if (opt("foci")) {
    foci = opt("foci").split(",").map((f) => f.trim());
    if (foci.length !== 4 || new Set(foci).size !== 4 || foci.some((f) => !FOCI.includes(f))) {
      die(`--foci takes four different foci from: ${FOCI.join(", ")}`);
    }
  } else {
    const slot = Number(opt("slot") ?? NaN);
    if (!Number.isInteger(slot) || slot < 0) die("give --slot <n> (n = 0, 1, 2, …) or --foci a,b,c,d");
    foci = [0, 1, 2, 3].map((i) => FOCI[(slot * 4 + i) % FOCI.length]);
  }
  input = fill({ "<COMMIT>": commit, "<FOCUS_A>": foci[0], "<FOCUS_B>": foci[1], "<FOCUS_C>": foci[2], "<FOCUS_D>": foci[3] })(template("deep-review"));
}

// ── earlier reports as inputs ───────────────────────────────────────────────
const prior = fuzz ? [] : (opt("prior") ?? "").split(",").map((s) => s.trim()).filter(Boolean);
if (prior.length) {
  input.inputs = [];
  for (const [n, jobId] of prior.entries()) {
    const res = await fetch(`${API}/jobs/${jobId}/result`, { signal: AbortSignal.timeout(20_000) });
    if (!res.ok) die(`job ${jobId}: result HTTP ${res.status}`);
    const result = await res.json();
    for (const f of result.files ?? []) {
      if (!["report", "findings"].includes(f.name)) continue;
      input.inputs.push({ name: `prior${n + 1}_${f.name}`, path: f.path, hash: f.hash, mediaType: f.mediaType,
                          bytes: f.bytes, submissionHash: f.submissionHash });
    }
  }
  if (!input.inputs.length) die("none of the --prior jobs has an accepted report or findings file yet");
}

// ── the documented limits (imd.fun/docs, "Job body") ─────────────────────────
const problems = [];
const leftover = JSON.stringify(input).match(/<[A-Z_]+>/g);
if (leftover) problems.push(`unfilled placeholders: ${[...new Set(leftover)].join(", ")}`);
if (!input.objective || input.objective.length > 8000) problems.push("objective must be 1–8,000 characters");
if ((input.references ?? []).length > 8) problems.push("at most 8 references");
if (fuzz) {
  if (input.template !== "fuzz") problems.push("jobs/fuzz.json must use the fuzz template");
  if (!Array.isArray(input.contracts) || input.contracts.length !== 1) problems.push("a fuzz job names exactly one harness in contracts");
  if (!Number.isInteger(input.runs) || input.runs < 1_000 || input.runs > 10_000_000) problems.push("runs must be 1,000–10,000,000");
} else {
  if (!Array.isArray(input.steps) || input.steps.length < 1 || input.steps.length > 6) problems.push("steps must hold 1–6 entries");
  const keys = new Set((input.steps ?? []).map((s) => s.key));
  for (const [i, s] of (input.steps ?? []).entries()) {
    if (!s.skill) problems.push(`steps[${i}].skill is required`);
    if (!/^[a-z][a-z0-9_]{0,31}$/.test(s.key ?? "")) problems.push(`steps[${i}].key is required in a dag`);
    if (!Array.isArray(s.dependsOn) || s.dependsOn.length > 6 || s.dependsOn.some((d) => !keys.has(d))) problems.push(`steps[${i}].dependsOn must name up to 6 step keys`);
    if ((s.objective ?? "").length > 3000) problems.push(`steps[${i}].objective: at most 3,000 characters`);
    const ac = s.acceptanceCriteria ?? [];
    if (ac.length > 8 || ac.some((c) => !c || c.length > 500)) problems.push(`steps[${i}].acceptanceCriteria: 1–8 strings of 1–500 characters`);
    if ((s.paths ?? []).length > 16 || (s.paths ?? []).some((p) => p.startsWith("/") || p.includes(".."))) problems.push(`steps[${i}].paths: at most 16, repository-relative`);
    if ((s.outputs ?? []).some((o) => !o.path.startsWith("artifacts/"))) problems.push(`steps[${i}].outputs must live under artifacts/`);
  }
  const finals = [...keys].filter((k) => !(input.steps ?? []).some((s) => (s.dependsOn ?? []).includes(k)));
  if (finals.length !== 1) problems.push(`every branch must join into one final step (found: ${finals.join(", ")})`);
}
if ((input.inputs ?? []).length > 32) problems.push("at most 32 inputs");
const body = { requestKey: opt("request-key") ?? randomUUID(), action: "job.open", input };
const bytes = Buffer.byteLength(JSON.stringify(body));
if (bytes > 16 * 1024) problems.push(`quote body is ${bytes} bytes; the limit is 16 KiB`);

console.log(JSON.stringify(body, null, 2));
console.error(`\n${fuzz ? `fuzz campaign, ${input.runs} runs` : `deep review, foci ${foci.join(", ")}`}${prior.length ? `, ${input.inputs.length} prior file(s)` : ""}: ` +
  `${bytes} bytes, ${problems.length ? "PROBLEMS:\n  - " + problems.join("\n  - ") : "within the documented limits"}`);
if (problems.length) process.exit(1);
if (flag("dry")) process.exit(0);

// ── quote (free) ─────────────────────────────────────────────────────────────
const token = process.env.IMD_PAID_TOKEN ?? "";
if (!/^[0-9a-f]{64}$/.test(token)) die("set IMD_PAID_TOKEN to 64 lowercase hex (openssl rand -hex 32) and keep it");
const auth = { Authorization: `Bearer ${token}` };
const q = await fetch(`${API}/requests/quote`, {
  method: "POST", headers: { ...auth, "Content-Type": "application/json" }, body: JSON.stringify(body),
});
const quoted = await q.json().catch(() => ({}));
if (!q.ok) die(`quote refused: HTTP ${q.status}\n${JSON.stringify(quoted, null, 2)}`);
const order = quoted.order;
const pay = order.quote?.payment ?? order.quote ?? {};
console.error(`\nquoted: order ${order.id}, ${pay.amount} atomic units of ${pay.asset} to ${pay.payTo}, ` +
  `expires ${new Date(order.quote?.expiresAt * 1000).toISOString()} (requestKey ${body.requestKey})`);
if (flag("quote")) process.exit(0);

// ── the payment challenge ───────────────────────────────────────────────────
//  Submitting with no body returns 402: the x402 v2 requirements in the PAYMENT-REQUIRED header,
//  repeated in the JSON with the quote. The wallet then signs the Permit2 payment and an EIP-712
//  approval of that payment for this quote, and both go back to the same route.
const c = await fetch(`${API}/requests/${order.id}/submit`, { method: "POST", headers: auth });
const challenge = await c.json().catch(() => ({}));
if (!flag("pay")) {
  console.log(JSON.stringify({ status: c.status, paymentRequired: c.headers.get("payment-required"), challenge }, null, 2));
  console.error(`\nNothing was signed. Re-run with --pay (and PRIVATE_KEY) to pay 0.5 IMD and post it.`);
  process.exit(0);
}
if (c.status !== 402) die(`expected the 402 payment challenge, got HTTP ${c.status}: ${JSON.stringify(challenge).slice(0, 400)}`);

//  Check the challenge before signing anything, as IMD's own explorer does: it must be this order,
//  this work, this credential, and exactly the advertised price.
const offer = challenge.accepts?.[0];
const qp = challenge.quote?.payment ?? {};
const { quoteHash, ...quoteRest } = challenge.quote ?? {};
const refuse = (what) => die(`payment details changed (${what}); nothing was signed`);
if (canon(challenge.quote) !== canon(order.quote)) refuse("quote");
if (quoteHash !== hashOf({ domain: "identitymd.paid-action-quote", ...quoteRest })) refuse("quote hash");
if (hashOf(challenge.input) !== challenge.quote.inputHash) refuse("work");
const scope = hashOf({ domain: "identitymd.paid-requester", scope: `paid-client:${hashOf({ domain: "identitymd.paid-http-client", token })}` });
if (challenge.requesterScopeHash !== scope) refuse("credential");
if (challenge.x402Version !== 2 || challenge.accepts?.length !== 1 || !offer) refuse("version");
if (offer.scheme !== "exact" || offer.network !== qp.network || offer.asset.toLowerCase() !== qp.asset.toLowerCase()
    || offer.payTo.toLowerCase() !== qp.payTo.toLowerCase() || offer.amount !== qp.amount) refuse("advertised price");
if (offer.amount !== "500000000000000000" && !flag("any-price")) refuse(`price ${offer.amount} is not 0.5 IMD (pass --any-price to accept)`);

const now = () => Math.floor(Date.now() / 1000);
const left = challenge.quote.expiresAt - now() - 2;
if (left < 15) die("this quote is too close to expiry; nothing was signed. Run again for a new quote.");

const { viem, account, pub } = await wallet();
const allowance = await pub.readContract({ address: offer.asset, abi: ERC20, functionName: "allowance", args: [account.address, PERMIT2] });
if (allowance < BigInt(offer.amount)) die(`Permit2 may move only ${viem.formatUnits(allowance, 18)} IMD from ${account.address}: run --approve first`);
const { x402Client } = await import("@x402/core/client");
const { ExactEvmScheme } = await import("@x402/evm/exact/client");
const { toClientEvmSigner } = await import("@x402/evm");
const signer = toClientEvmSigner(account, pub);
const client = x402Client.fromConfig({
  schemes: [{ network: offer.network, client: new ExactEvmScheme(signer) }],
  spendControls: { allowedAssets: [{ network: offer.network, asset: offer.asset, maxAmountPerPayment: offer.amount }] },
});
console.error("signature 1 of 2: the Permit2 payment");
const created = await client.createPaymentPayload({
  x402Version: 2, resource: challenge.resource,
  accepts: [{ ...offer, maxTimeoutSeconds: Math.min(offer.maxTimeoutSeconds, left) }],
});
const payment = JSON.parse(JSON.stringify({ ...created, accepted: offer }));
console.error("signature 2 of 2: the quote approval");
const cq = challenge.quote;
const quoteSignature = await account.signTypedData({
  domain: { name: "IdentityMD Paid Action", version: "1", chainId: Number(cq.payment.network.slice(7)) },
  primaryType: "QuoteApproval",
  types: { QuoteApproval: [
    { name: "resource", type: "string" }, { name: "requesterScopeHash", type: "bytes32" },
    { name: "quoteId", type: "string" }, { name: "quoteHash", type: "bytes32" },
    { name: "paymentHash", type: "bytes32" }, { name: "action", type: "string" },
    { name: "asset", type: "address" }, { name: "amount", type: "uint256" },
    { name: "payTo", type: "address" }, { name: "expiresAt", type: "uint256" },
  ] },
  message: {
    resource: challenge.resourceUrl, requesterScopeHash: `0x${challenge.requesterScopeHash}`, quoteId: cq.id,
    quoteHash: `0x${cq.quoteHash}`, paymentHash: `0x${hashOf(payment)}`, action: cq.action,
    asset: cq.payment.asset, amount: BigInt(cq.payment.amount), payTo: cq.payment.payTo, expiresAt: BigInt(cq.expiresAt),
  },
});
if (challenge.quote.expiresAt - now() < 8) die("the quote expired while signing; nothing was submitted. Run again.");

const paid = await fetch(`${API}/requests/${order.id}/submit`, {
  method: "POST",
  headers: { ...auth, "Content-Type": "application/json",
             "payment-signature": Buffer.from(JSON.stringify(payment), "utf8").toString("base64") },
  body: JSON.stringify({ quoteSignature }),
});
const paidBody = await paid.json().catch(() => ({}));
if (paid.status !== 200 && paid.status !== 202) die(`payment refused: HTTP ${paid.status} ${JSON.stringify(paidBody).slice(0, 600)}`);
console.error(`submitted (HTTP ${paid.status}); waiting for settlement and admission…`);

for (let i = 0; i < 120; i++) {
  const st = await (await fetch(`${API}/requests/${order.id}`, { headers: auth })).json().catch(() => ({}));
  if (st.status === "admitted") {
    const r = st.admission?.result ?? {};
    console.log(JSON.stringify({ order: order.id, payment: st.payment, admission: st.admission }, null, 2));
    if (r.kind === "refused") die(`paid but refused: ${JSON.stringify(r.problems)}`);
    const note = fuzz ? `fuzz ${input.runs} runs` : `deep review, foci ${foci.join(" ")}`;
    appendFileSync(new URL("ledger/jobs.txt", ROOT), `${r.jobId}  # ${new Date().toISOString().slice(0, 10)} ${note}; order ${order.id}\n`);
    console.error(`\nADMITTED: job ${r.jobId}  https://explorer.imd.fun/jobs/${r.jobId}\n(added to ledger/jobs.txt)`);
    process.exit(0);
  }
  if (["payment_failed", "expired"].includes(st.status)) die(`order ${order.id} ended ${st.status}: ${JSON.stringify(st.payment ?? {}).slice(0, 400)}`);
  await new Promise((res) => setTimeout(res, 5000));
}
die(`order ${order.id} still pending after 10 minutes; check GET /requests/${order.id} with the same token`);
