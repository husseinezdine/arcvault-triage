# Prompt — Enrichment

**Model:** claude-haiku-5-5 (Anthropic, forced tool-use with the schema below) · temperature 0 · fallback: gemini-3.5-flash (Gemini JSON mode, same schema)

## System prompt

```text
You extract structured facts from ONE inbound customer message for ArcVault support. Do NOT classify and do NOT invent facts: extract only what is explicitly in the message.

FIELDS:
- core_issue: the problem or request in ONE neutral sentence, max 25 words.
- identifiers: every concrete identifier mentioned — account IDs or usernames, URLs, invoice numbers, error codes (e.g. "HTTP 403"), money amounts, dates/times, product features, third-party integrations (e.g. "Okta"). Empty array if none.
- disputed_amount_usd: if the message disputes a charge, the amount IN DISPUTE in USD. Example: charged 1240 but expected 980 -> 260. "Charged twice, $2,100 extra" -> 2100. Use 0 when there is no billing dispute.
- affected_scope: "single_user", "multiple_users", or "unknown" — based only on what the message says.
- urgency_signal: none / low / medium / high, judged from the message content (words like "asap", "urgent", "multiple users", "stopped", "since this morning", deadlines) — NOT from the type of request.
- urgency_evidence: the exact words that justify urgency_signal, or an empty string.

Output ONLY JSON matching the schema.
```

## Response schema

```json
{
  "type": "object",
  "properties": {
    "core_issue": {
      "type": "string"
    },
    "identifiers": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "type": {
            "type": "string",
            "enum": [
              "account_id",
              "url",
              "invoice_number",
              "error_code",
              "amount",
              "datetime",
              "product_feature",
              "integration",
              "other"
            ]
          },
          "value": {
            "type": "string"
          }
        },
        "required": [
          "type",
          "value"
        ]
      }
    },
    "disputed_amount_usd": {
      "type": "number"
    },
    "affected_scope": {
      "type": "string",
      "enum": [
        "single_user",
        "multiple_users",
        "unknown"
      ]
    },
    "urgency_signal": {
      "type": "string",
      "enum": [
        "none",
        "low",
        "medium",
        "high"
      ]
    },
    "urgency_evidence": {
      "type": "string"
    }
  },
  "required": [
    "core_issue",
    "identifiers",
    "disputed_amount_usd",
    "affected_scope",
    "urgency_signal",
    "urgency_evidence"
  ]
}
```

## Why it is structured this way (tradeoffs, what I would change)

Enrichment is a separate call with a separate prompt because it is a different job: the classifier *judges*, the extractor *copies*. The prompt therefore says "do not classify, do not invent facts, extract only what is explicitly in the message", and every field has a concrete definition and examples of what counts as an identifier (account IDs, invoice numbers, HTTP error codes, amounts, dates, integrations). Two fields were added beyond the assessment's list so that the escalation rules can work on structured data instead of keyword guessing: `disputed_amount_usd` turns "billing error > $500" into a number comparison (REQ-0003: 1,240 − 980 = 260 → not escalated; REQ-0007: 2,100 → escalated), and `affected_scope` gives the outage rules a normalized signal for "multiple users" however the customer phrases it. `urgency_evidence` asks for the exact words behind the urgency score, which makes the model's judgment checkable by the human reviewer.

Tradeoffs: a second call costs roughly one extra second and a few hundred tokens per message. I kept it separate because the two prompts can be evaluated and tuned independently and the outputs stay clean; at high volume I would test merging classification and enrichment into one structured call and compare accuracy, or run the two calls in parallel since neither depends on the other. I would also add a small normalizer after extraction (strip "#", parse "$1,240" to 1240) so identifiers are machine-ready, not just human-readable.
