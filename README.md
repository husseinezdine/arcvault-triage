# ArcVault — AI intake & triage pipeline

Take-home assessment for the AI Engineer role (Valsoft / Aspire Software). An n8n workflow that ingests unstructured customer requests, classifies and enriches them with an LLM, routes them with deterministic rules, and flags anything a human should see first.

| Deliverable | Where |
|---|---|
| 4.1 Working workflow | `workflow/arcvault-triage.json` (n8n export) + `screenshots/` (canvas, executions, every node's output for REQ-0005, queue endpoint, records folder) |
| 4.2 Structured output | `output/records.json` (7 records) · `output/records_summary.md` (one-table overview) |
| 4.3 Prompts | `prompts/1-classification.md`, `2-enrichment.md`, `3-summary.md` — prompt, schema, reasoning |
| 4.4 Architecture write-up | sections 1–6 below |
| AI usage | `AI_USAGE.md` — how I used AI tools, what they got wrong, what I fixed |

**Run locally:** `docker compose up -d` → n8n at `localhost:5678` → add a *Header Auth* credential (`x-api-key` = Anthropic key) → import `workflow/arcvault-triage.json`, select the credential on the three `(LLM)` nodes, activate → `.\scripts\send_samples.ps1` (or `.sh`). Records land in `data/records/<id>.json`, are returned to the caller, and are POSTed to `https://webhook.site/<token>/<queue>`.

## 1. System design

```
POST /webhook/intake {id, source, message}
  → Webhook → Normalize → Prompt Library → Classify (LLM) → Parse Classification
  → Enrich (LLM) → Parse Enrichment → Route & Escalate → Summarize (LLM) → Build Record
      ├→ Respond to Webhook          (record returned to the caller)
      ├→ Convert to JSON → Write file (data/records/<id>.json — persistent output)
      └→ Dispatch to Queue           (POST to <queue_base>/<final_queue>)
```

**Triggers and flow.** A webhook is the trigger, so any source (email connector, web form, support portal) only has to POST `{source, message}`; the run starts immediately and is linear. Each LLM step is two nodes — an HTTP call and a parse/validate Code node — so raw model output never reaches business logic. Routing and escalation are one Code node of plain rules. Build Record assembles the final JSON and fans out to three destinations.

**State.** One message = one n8n item that flows through the chain; each node adds a block (`classification`, `enrichment`, `routing`, `escalation`, `summary`). Configuration (provider, model, prompt version, queue URL) lives in the Normalize node and is stamped on every record as `pipeline.*`, so each record says which model and prompt version produced it. Persistent state is the record itself (one file per request, plus the queue POST); n8n keeps the per-node execution trace.

**Model.** All three steps run on **Claude Haiku (`claude-haiku-5-5`)** with *forced tool use*: the model must call a tool whose `input_schema` is our JSON schema, so output is schema-valid by construction (enums enforced, no prose). I started on Gemini Flash (free tier, JSON mode) and switched after hitting a retired model name, a 503 "high demand", and the daily request cap in one afternoon. The provider is a config switch (`provider: 'gemini'` + the matching credential runs the same workflow on Gemini); the parser accepts both response shapes. ~4 s per message.

**Why n8n.** First tool on the recommended list; every step inspectable with its data; the export is a reviewable artifact; self-hosting is a Docker one-liner. All prompts sit in one node (`Prompt Library`) so they can be reviewed in one place.

## 2. Routing logic

| Category | Standard queue | Why |
|---|---|---|
| Bug Report | `engineering` | needs a code-level look |
| Incident/Outage | `engineering`, **always escalated** | engineering owns the fix, but a human must see an outage within minutes |
| Billing Issue | `billing` | invoices, rates, refunds |
| Feature Request | `product` | roadmap |
| Technical Question | `it-security` | SSO / integration / config questions |
| `Unknown` | `escalation` | no table match → human |

The table gives the *standard* queue; the escalation rules decide whether the record goes there or to the separate `escalation` queue. The record keeps both (`standard_queue`, `final_queue`) so the escalation team knows who to hand it to; `fallback_used` marks low confidence or no table match. The LLM never chooses the queue: rules are deterministic, auditable (every record carries its `reasons`), testable without an API key, and a support manager can change a threshold without touching a prompt.

## 3. Escalation logic

Flagged `human_review_required` and routed to `escalation` if **any** rule matches:

| Rule | Reason on the record | Example |
|---|---|---|
| confidence < 0.70 (required) | `low_confidence:0.20<0.7` | REQ-0006 |
| category = Incident/Outage | `category:incident_outage` | REQ-0005 |
| keyword: outage, down for all, all users, multiple users, everyone, data loss, breach, security incident, hacked (required) | `keyword:multiple users` | REQ-0005 |
| disputed amount > $500 (required) | `billing_dispute_usd:2100>500` | REQ-0007 |
| multiple users affected on a bug/outage | `scope:multiple_users` | REQ-0005 |
| category = Unknown | `category:unknown` | — |

**Assumption on the $500 rule.** "Billing error > $500" is read as the *amount in dispute* (extracted by the enrichment step), not the invoice total: REQ-0003 is a $1,240 invoice against a $980 contract, a $260 error → billing, not escalated. If the business means invoice total, it is a one-line change. The confidence comparison is strict (`< 0.70`), matching "below 70%".

**Confidence caveat.** The score is self-reported by the model and not calibrated — a ranking signal, not a probability. The prompt asks for values below 0.7 on vague input (models over-report by default) and the run shows it works (0.20 for "stuff is not working, please help asap"), but in production the threshold should come from a labeled evaluation set.

## 4. Results

Five assessment samples plus two added edge cases: REQ-0006 (vague message → low-confidence fallback) and REQ-0007 ($2,100 duplicate charge + broken export → billing escalation with a secondary category). Three full runs produced identical decisions. Table in `output/records_summary.md`, full records in `output/records.json`.

## 5. At production scale

- **Reliability**: a queue (Pub/Sub / SQS) between sources and the workflow; idempotency key per message so retries never duplicate tickets; dead-letter queue; retries with backoff (already on the LLM nodes — they absorbed real 503s); automatic provider failover on 429/503; timeouts and a circuit breaker.
- **Cost / latency**: run classification and enrichment in parallel or merge them after measuring accuracy; smallest model that holds accuracy, larger model only for low-confidence cases; cache identical messages.
- **Quality**: labeled evaluation set and a regression test on every prompt change; prompt versioning (already on each record); monitor confidence and escalation-reason distributions as drift signals.
- **Governance**: trace id per message, token usage per record (captured), PII redaction before the LLM and in logs, regional endpoints for data residency, audit log of routing decisions.
- **Deployment on GCP**: n8n on Cloud Run/GKE with Postgres, secrets in Secret Manager, records in Firestore/BigQuery, Pub/Sub topics per team feeding Jira/Zendesk/Slack; at high volume the rule logic moves into a small Python service with unit tests, n8n stays as orchestration.

## 6. Phase 2 (one more week)

1. **Feedback loop** — reviewers correct category/queue in the escalation UI; corrections become the evaluation set and, with volume, training data for a small classifier that handles the easy 80%.
2. **Retrieval** — similar past tickets and the knowledge base before routing; a Technical Question with a known answer (Okta SSO docs) gets an auto-drafted reply for an agent to approve.
3. **Customer context** — account tier, contract rate and open incidents from CRM/billing, so the $500 rule becomes "disputed vs. contract" and outage reports match the status page.
4. **Operations** — SLA timers per queue, a volume/accuracy/latency/cost dashboard, multi-language, a Solutions queue for pre-sales questions.
