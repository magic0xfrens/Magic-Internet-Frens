# Arming the indexer monitor

`freshness-probe.mjs` is the alarm for the read layer. Before it existed there
was no alerting anywhere in this repo — no pager, no webhook, no external check.
`/freshness` was polled only by a browser (`src/hooks/useIndexerHealth.ts`), so a
stalled or diverged indexer was visible only to someone already looking at the
site.

**The code is committed. It is not armed.** Arming it takes one secret, pasted by
hand. Until that is done, the workflow runs and fails loudly in the Actions tab,
but nothing reaches a phone.

---

## What the owner must do by hand

**1. Create an incoming webhook** (5 minutes, free, pick one):

- *Slack* — https://api.slack.com/messaging/webhooks → "Create your Slack app" →
  Incoming Webhooks → on → "Add New Webhook to Workspace" → pick a channel.
  Copy the `https://hooks.slack.com/services/...` URL.
- *Discord* — Server Settings → Integrations → Webhooks → New Webhook → pick a
  channel → Copy Webhook URL.

The probe detects which one from the hostname and sends the field that host
expects (`content` for Discord, `text` for Slack). No other configuration.

**2. Paste it as a repository secret:**

> GitHub → `magic0xfrens/Magic-Internet-Frens` → Settings → Secrets and
> variables → **Actions** → New repository secret
> - Name: `ALERT_WEBHOOK_URL`
> - Secret: *the webhook URL from step 1*

That name is not arbitrary — `.github/workflows/indexer-monitor.yml` reads
exactly `secrets.ALERT_WEBHOOK_URL`. The URL is a credential: anyone holding it
can post to the channel. It is never logged, echoed, or written to a file by the
probe, which reports only the webhook's *hostname* and the HTTP status.

**3. Prove it works before you need it:**

> GitHub → Actions → `indexer-monitor` → Run workflow → set
> **expect_chain_id** to `1` → Run

That deliberately mismatches the manifest's chain, so the probe must report
`CRIT ... the indexer is on the WRONG CHAIN`, fail the job, and post to your
channel. If no message arrives, the secret is wrong or missing. Re-run with the
field blank to confirm it returns to green.

**4. Add a second channel.** See *Why one channel is not enough* below.

---

## Two things this monitor cannot do for you

**It will page immediately, and correctly, until the indexer is redeployed.**
Measured 2026-09-16: the live service answers `/freshness` with a body that has
no `chainHeight`, `finalityLagBlocks` or `reorgToleranceOk`. Those fields landed
in commit `286056b`; the deployed build predates it. So the reorg-tolerance alarm
is **not running in production** — it exists only in the source tree. The probe
treats that as a `CRIT` on purpose, because the alternative is a monitor that
reports all-clear because it is blind. Redeploying the indexer clears it.

**Why one channel is not enough.** GitHub documents three limits on scheduled
workflows, and two of them are silent:

1. "The shortest interval you can run scheduled workflows is once every 5
   minutes." Detection latency is therefore the threshold *plus* up to ~5 min.
2. "If the load is sufficiently high enough, some queued jobs may be dropped."
   A dropped run looks exactly like a healthy one.
3. "In a public repository, scheduled workflows are automatically disabled when
   no repository activity has occurred in 60 days." A protocol that is live and
   quiet is precisely the case that trips this.

(2) and (3) mean this transport cannot tell you it has stopped watching. Pair it
with a **dead-man's switch** — a service that alerts on the *absence* of a
heartbeat. Healthchecks.io and Better Stack both have a free tier that covers
this. Create a check with a ~15-minute period, then add one line to the workflow
after the probe step so a *successful* run pings it:

```yaml
      - name: Heartbeat (only on success)
        run: curl -fsS --max-time 10 "$HEARTBEAT_URL"
        env:
          HEARTBEAT_URL: ${{ secrets.HEARTBEAT_URL }}
```

Now silence itself is an alert. This is the only configuration that catches
"Railway stopped restarting after its tenth attempt and the service stayed
down" *together with* "GitHub quietly stopped running the check".

---

## Cost

| Piece | Cost |
|---|---|
| GitHub Actions at `*/5` | **$0** — this repo is public (`gh repo view` → `PUBLIC`) and Actions minutes are free for public repositories |
| Slack / Discord webhook | **$0** |
| Dead-man's switch (Healthchecks.io / Better Stack free tier) | **$0** at this volume |

If the repo is ever made **private**, `*/5` becomes ~8,640 billable minutes a
month against a 2,000-minute free allowance. At that point widen the interval or
move the probe to an external monitor.

---

## Running it by hand

```sh
node indexer/monitor/freshness-probe.mjs                 # uses round.json
INDEXER_URL=https://… node indexer/monitor/freshness-probe.mjs
EXPECT_CHAIN_ID=4663 node indexer/monitor/freshness-probe.mjs   # cutover drill
```

Exit `0` = OK or WARN, exit `1` = CRIT. Zero dependencies (node's built-in
`fetch`), deliberately: the alarm must not be able to fail because a package
registry is having a bad day.

Both the target URL and the expected chain id default to
`indexer/deployments/round.json`, so the Robinhood cutover — which *replaces*
that file — re-points this monitor with no separate edit. A monitor pinned to its
own copy of the chain id is a monitor that keeps watching the old chain.

---

## Thresholds, and where the numbers come from

Every threshold is derived from a measurement, and each is overridable by env var
for a drill. Full arithmetic is in the header comments of
`freshness-probe.mjs`; the short version:

| Signal | Warn | Page | Derivation |
|---|---|---|---|
| Indexer staleness (`/status`) | 120 s | **600 s** | Steady state is ~1-2 s (Ponder polls 4663 every 1,000 ms, blocks are ~100 ms). One legitimate Railway restart can take up to 300 s (`healthcheckTimeout`). The chain's measured finality distance is 830 s. `300 < 600 < 830` — above the largest benign event, below the dangerous one. |
| Finality lag vs patched tolerance | 85 % | endpoint 503s at 100 % | Tolerance is 12,000 blocks. Two independent measurements of 4663's finality distance exist: 8,274 (69 %) and ~9,650 (80 %). A warn must sit above both or it fires on normal variation; 85 % = 10,200 blocks still leaves ~180 s before the endpoint 503s. |
| Wrong chain, pool mismatch, missed launch, HTTP failure | — | immediate | Divergence never self-heals by waiting. |

**Staleness is read from `/status`, not from `/freshness`'s `lagSeconds`.** That
field is `latestBlock.timestamp - newestIndexedSwap.timestamp`
(`indexer/src/api/index.ts:1514-1520`) — the age of the last *swap*, not of the
last indexed *block*. On a quiet market it grows without bound while the indexer
is perfectly healthy, and with no swaps at all it is `null`. Paging on it would
page on a quiet night. `/status` is Ponder's own sync height and has no coupling
to trade volume. `lagSeconds` is still printed, labelled as context.
