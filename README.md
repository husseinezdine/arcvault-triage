# ArcVault — AI intake & triage pipeline

Take-home assessment for the AI Engineer role (Valsoft / Aspire Software). An n8n workflow that ingests unstructured customer requests, classifies and enriches them with an LLM, routes them to the right team with deterministic rules, and flags anything a human should look at first.

**Deliverables**

| # | What | Where |
|---|---|---|
| 4.1 | Working workflow | `workflow/arcvault-triage.json` (n8n export) + `screenshots/` (canvas, executions, every node's output for REQ-0005, the queue endpoint, the records folder) |
| 4.2 | Structured output | `output/records.json` (7 records, all fields) · `output/records_summary.md` (one-table overview) |
| 4.3 | Prompts | `prompts/1-classification.md`, `2-enrichment.md`, `3-summary.md` — prompt, schema, and the reasoning behind each |
| 4.4 | Architecture write-up | this file, sections 2–7 |
| — | How I used AI tools, and what they got wrong | `AI_USAGE.md` |

## 1. Run it locally

```powershell
cp .env.example .env            # set N8N_ENCRYPTION_KEY to any long random string
docker compose up -d            # n8n at http://localhost:5678
# in n8n: create the owner account; Credentials -> Header Auth: name "x-api-key", value = your Anthropic API key (any credential name)
# Workflows -> import workflow/arcvault-triage.json -> select the credential on the 3 "(LLM)" nodes -> Save -> Active
.\scripts\send_samples.ps1      # fires the 5 assessment samples + 2 edge cases (bash: scripts/send_samples.sh)
```
Records appear in `data/records/<id>.json`, are returned to the caller, and are POSTed to the queue endpoint (`https://webhook.site/<token>/<queue>`). `scripts/n8n_backup.ps1` / `n8n_restore.ps1` export and re-import the workflow and credentials.

## 2. System design

```
POST /webhook/intake {id, source, message}
   │
   ▼
[1] Webhook (intake) ─► [2] Normalize ─► [3] Prompt Library ─► [4] Classify (LLM) ─► [5] Parse Classification
                                                                                             │
   ┌─────────────────────────────────────────────────────────────────────────────────────────┘
   ▼
[6] Enrich (LLM) ─► [7] Parse Enrichment ─► [8] Route & Escalate ─► [9] Summarize (LLM) ─► [10] Build Record
                                                                                                 │
                                        ┌──────────────────────┬─────────────────────────────────┤
                                        ▼                      ▼                                 ▼
                             [11] Respond to Webhook   [12] Convert to JSON file        [14] Dispatch to Queue
                             (record back to caller)   [13] Write /data/records/<id>.json   POST <queue_base>/<final_queue>
```

**What triggers what.** A webhook is the trigger: any source (email connector, web form, support portal) only has to POST `{source, message}`; the run starts immediately and the rest is linear. Each LLM step is two nodes — an HTTP call and a parse/validate Code node — so raw model output is never passed to business logic. Routing and escalation are one Code node of plain rules. Build Record assembles the final JSON, which fans out to three destinations in parallel.

**Where state is held.** There is no external state during a run: one message = one n8n item that flows through the chain, and each node adds a block to it (`classification`, `enrichment`, `routing`, `escalation`, `summary`). Because an HTTP node replaces the item with the API response, the parse nodes fetch the record back by node name (`$('Normalize').first().json`). Configuration (provider, model, prompt version, queue URL) lives in one place — the Normalize node — and is stamped onto every record as `pipeline.*`. Persistent state is the record itself: a JSON file per request (`data/records/`) and the POST to the downstream queue; n8n also keeps the full execution trace per node.

**Model choice.** Classification, enrichment and summary run on **Claude Haiku (`claude-haiku-5-5`, Anthropic API)** using *forced tool use*: the model must call a tool whose `input_schema` is our JSON schema, so output is schema-valid JSON by construction — no prose, no markdown fences, enums enforced. I started on Gemini Flash (free tier, JSON mode with `responseSchema`) and switched after hitting, in one afternoon, a retired model name (`gemini-2.5-flash` "no longer available to new users"), a 503 "high demand" on the newest Flash model, and then the free tier's daily request cap. Haiku is fast (~4 s for the three calls), cheap, and not rate-limited at this volume. The provider is a config switch: `provider: 'gemini'` plus the matching credential runs the same workflow on Gemini, and the parser accepts both response shapes. Same schemas for both.

**Why n8n.** It is the first tool the assessment recommends; every step is inspectable with its data in the execution view; the exported JSON is a reviewable artifact; and self-hosting is a Docker one-liner. The prompts live in a single Code node so they can be reviewed in one place.

## 3. Routing logic

| Category | Standard queue | Why |
|---|---|---|
| Bug Report | `engineering` | needs a code-level look |
| Incident/Outage | `engineering` — **and always escalated** | engineering owns the fix, but a human must see an outage within minutes regardless of model confidence |
| Billing Issue | `billing` | invoices, rates, refunds |
| Feature Request | `product` | roadmap decisions |
| Technical Question | `it-security` | SSO/integration/config questions; pre-sales questions could also go to Solutions — see Phase 2 |
| anything else / `Unknown` | `escalation` | no table match → human |

The table maps the category to a *standard* queue; the escalation rules below decide whether the record actually goes there or to the separate `escalation` queue. The record keeps both (`standard_queue`, `final_queue`) so the escalation team knows which team to hand it to. `fallback_used` is true when confidence was below the threshold or the category had no entry. The LLM never chooses the queue: rules are deterministic, auditable (every record carries its `reasons`), testable without an API key, and a support manager can change a threshold without touching a prompt.

## 4. Escalation logic

A record is flagged `human_review_required` and routed to `escalation` if **any** of these hold:

| Rule | Reason string | Source |
|---|---|---|
| `confidence < 0.70` | `low_confidence:0.20<0.7` | required by the assessment; REQ-0006 |
| category = Incident/Outage | `category:incident_outage` | outages are time-critical; REQ-0005 |
| keyword in message: outage, down for all, all users, multiple users, everyone, data loss, breach, security incident, hacked | `keyword:multiple users` | required ("outage", "down for all users"); REQ-0005 |
| `disputed_amount_usd > 500` | `billing_dispute_usd:2100>500` | required ("billing error > $500"); REQ-0007 |
| `affected_scope = multiple_users` on a bug/outage | `scope:multiple_users` | structured backup for the keyword rule |
| category = Unknown | `category:unknown` | defense in depth; the enum makes it unreachable in practice |

**Assumption on the $500 rule.** The assessment says "billing error > $500" without defining it. I interpret it as the *amount in dispute*, extracted by the enrichment step, not the invoice total: REQ-0003 is a $1,240 invoice against a $980 contract, i.e. a $260 error → routed to billing, not escalated. If the business meant invoice total, it is a one-line change in the rule. The comparison is strict (`<` 0.70), matching "below 70%".

**Confidence caveat.** The confidence score is self-reported by the model and not calibrated — it is a ranking signal, not a probability. The prompt explicitly asks for values below 0.7 on vague input (models over-report by default), and the run shows it works (0.20 for "stuff is not working, please help asap"), but in production the threshold should be set from a labeled evaluation set, not chosen by hand.

## 5. Results

All five assessment samples plus two added edge cases (REQ-0006: vague message → low-confidence fallback; REQ-0007: $2,100 duplicate charge + broken export → billing escalation with a secondary category). Summary table in `output/records_summary.md`; full records in `output/records.json`. ~4 s and ~3 LLM calls per message.

## 6. At production scale

- **Ingestion**: put a queue between the sources and the workflow (Pub/Sub or SQS); idempotency key per message (source + message hash) so retries never create duplicate tickets; dead-letter queue for anything that fails all retries.
- **Reliability**: retries with backoff are already on the LLM nodes (5 × 5 s — they absorbed real 503s during the build); add a second provider as automatic failover (the provider switch exists; it would move from config to a runtime fallback on 429/503), a circuit breaker, and timeouts per call.
- **Cost / latency**: run classification and enrichment in parallel (they are independent) or merge them into one call after measuring accuracy; use the smallest model that holds accuracy for classification and reserve a larger model for low-confidence cases only (tiered inference); cache identical messages; disable model "thinking" for classification.
- **Quality**: a labeled evaluation set and a regression test that runs on every prompt change; prompt versioning (already stamped on every record as `pipeline.prompt_version`) so results can be traced to the prompt that produced them; monitor the distribution of confidence and of escalation reasons as drift signals.
- **Observability & governance**: trace id per message through all three calls, token usage per record (already captured), PII redaction before the LLM call and in logs, data-residency choice of provider (e.g. Vertex AI with regional endpoints), audit log of routing decisions.
- **Deployment (GCP)**: n8n on Cloud Run or GKE with Postgres instead of SQLite, secrets in Secret Manager, records in Firestore/BigQuery instead of files, queues as Pub/Sub topics per team feeding Jira/Zendesk/Slack. For very high volume the Code-node logic would move into a small Python service with unit tests, and n8n would stay as the orchestration layer.

## 7. Phase 2 (one more week)

1. **Human feedback loop**: reviewers correct category/queue in the escalation UI; corrections become the evaluation set and, with enough volume, training data for a small fine-tuned classifier that replaces the LLM for the easy 80%.
2. **Retrieval**: look up similar past tickets and the knowledge base before routing — a Technical Question with a known answer (e.g. Okta SSO docs) gets an auto-drafted reply for an agent to approve.
3. **Customer context**: enrich with account tier, contract rate and open incidents from the CRM/billing system — the $500 rule becomes "disputed amount vs. contract", and outage reports can be matched to the status page automatically.
4. **Operations**: SLA timers per queue, a dashboard of volume/accuracy/latency/cost, multi-language support, and a "Solutions" queue for pre-sales technical questions.

## 8. Repo layout

```
docker-compose.yml        n8n self-hosted (named volume for n8n data, ./data mounted for records)
workflow/                 exported n8n workflow
prompts/                  the three prompts + schemas + rationale
output/                   records.json + summary table
screenshots/              workflow and per-node outputs
scripts/                  send_samples (ps1/sh), resend, n8n_backup / n8n_restore
data/records/             one JSON per processed message (runtime output)
AI_USAGE.md               how AI assistants were used, what they got wrong
```
