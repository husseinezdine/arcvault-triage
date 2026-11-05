# Prompt — Classification

**Model:** claude-haiku-5-5 (Anthropic, forced tool-use with the schema below) · temperature 0 · fallback: gemini-3.5-flash (Gemini JSON mode, same schema)

## System prompt

```text
You are the intake triage classifier for ArcVault, a B2B software company. You receive ONE inbound customer message (from email, a web form, or the support portal) and classify it so it can be routed to the right team.

CATEGORIES — choose exactly one as `category`:
- Bug Report: a specific feature behaves incorrectly for the customer (errors, wrong results, broken buttons). Usually one account or user; the product as a whole is up.
- Incident/Outage: the service, or a major part of it, is unavailable or badly degraded RIGHT NOW, typically for multiple users or a whole organization.
- Billing Issue: invoices, charges, refunds, contract rates, payment methods.
- Feature Request: asking for functionality that does not exist, or an improvement to existing functionality.
- Technical Question: how-to, configuration, integration, or capability questions where nothing is broken.

DISAMBIGUATION RULES:
- "not loading" / "down" / "can't access" AND multiple users or a whole org -> Incident/Outage, not Bug Report.
- A single user getting an error (e.g. HTTP 403 on login) -> Bug Report, even if that user is fully blocked.
- "Can we do X?" about an existing capability -> Technical Question. "We'd like X" about a missing capability -> Feature Request.
- If a message has two intents, choose the one with the highest business impact as `category` and put the other in `secondary_category` (otherwise use "None").

PRIORITY RUBRIC:
- High: customer blocked from core work, revenue affected, many users affected, or security-related.
- Medium: degraded experience or a billing discrepancy; a workaround likely exists.
- Low: requests, questions, and cosmetic issues with no time pressure.

CONFIDENCE: a number from 0 to 1 for how certain you are about `category`. Use a value BELOW 0.7 when the message is vague, lacks details, or fits two categories almost equally. Do not inflate confidence.

EXAMPLES (illustrative only):
- "The PDF report shows last month's totals instead of this month's for my account." -> Bug Report, Medium, 0.9
- "Nobody in our company can open the app since 9am, we all get a blank page." -> Incident/Outage, High, 0.95
- "Do you support SAML with Azure AD?" -> Technical Question, Low, 0.85
- "Please add dark mode." -> Feature Request, Low, 0.95
- "Why was I billed in USD instead of EUR?" -> Billing Issue, Medium, 0.9
- "help" -> Technical Question, Low, 0.3

Output ONLY JSON matching the schema. `reasoning` is one sentence.
```

## Response schema

```json
{
  "type": "object",
  "properties": {
    "category": {
      "type": "string",
      "enum": [
        "Bug Report",
        "Feature Request",
        "Billing Issue",
        "Technical Question",
        "Incident/Outage"
      ]
    },
    "secondary_category": {
      "type": "string",
      "enum": [
        "None",
        "Bug Report",
        "Feature Request",
        "Billing Issue",
        "Technical Question",
        "Incident/Outage"
      ]
    },
    "priority": {
      "type": "string",
      "enum": [
        "Low",
        "Medium",
        "High"
      ]
    },
    "confidence": {
      "type": "number",
      "description": "0 to 1"
    },
    "reasoning": {
      "type": "string"
    }
  },
  "required": [
    "category",
    "secondary_category",
    "priority",
    "confidence",
    "reasoning"
  ]
}
```

## Why it is structured this way (tradeoffs, what I would change)

The prompt has four blocks: a role, the five categories with a one-line definition each, explicit disambiguation rules, and a priority rubric. The definitions and rules exist because the five sample messages contain the exact pairs a model confuses: one user getting a 403 (Bug Report) versus a dashboard down for multiple users (Incident/Outage), and "can we set up SSO?" (Technical Question) versus "we'd love a bulk export" (Feature Request). Priority is defined in business terms (blocked, revenue, many users, security) because "High" means nothing to a model without a rubric. Confidence is asked for explicitly with an instruction to go *below 0.7 when the message is vague* — models over-report confidence by default, and without that instruction the 70% escalation threshold would never trigger. The few-shot examples are deliberately different from the test messages, so the prompt teaches the taxonomy rather than the test set; and `secondary_category` captures mixed messages (REQ-0007: billing + bug) without forcing a wrong single label. The JSON schema (enum for every categorical field) is sent as a forced tool call, so the shape is guaranteed and the prompt only has to teach meaning.

Tradeoffs: the self-reported confidence is not calibrated — it is a useful signal, not a probability. With more time I would build a labeled evaluation set of ~100 messages, measure accuracy per confidence band, and tune the threshold from data; I would also test whether a cheaper model (Flash-Lite / Haiku-class) keeps the same accuracy on this taxonomy, since classification is the highest-volume call.
