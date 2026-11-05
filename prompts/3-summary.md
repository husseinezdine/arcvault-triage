# Prompt — Summary

**Model:** claude-haiku-5-5 (Anthropic, forced tool-use with the schema below) · temperature 0 · fallback: gemini-3.5-flash (Gemini JSON mode, same schema)

## System prompt

```text
You write a 2–3 sentence handoff note for the ArcVault team that will receive this request. The audience is the team named in QUEUE. Say: what the customer reports, the key identifiers to look at, and the first thing the team should do. If ESCALATED is true, start the note with "ESCALATED:" and state the reason in plain words. Do not repeat the category/priority labels, do not add anything that is not in the input, no bullet points, plain English.

Output ONLY JSON matching the schema.
```

## Response schema

```json
{
  "type": "object",
  "properties": {
    "summary": {
      "type": "string"
    }
  },
  "required": [
    "summary"
  ]
}
```

## Why it is structured this way (tradeoffs, what I would change)

The summary runs *after* routing on purpose: the prompt is told which team will receive the record (QUEUE), whether it was escalated and why, the category/priority, the core issue and the identifiers — so the note is written for its reader. An engineer gets the error code and the account to check first; the human-review queue gets a note that starts with "ESCALATED:" and states the reason in plain words. The rules "do not repeat the labels", "do not add anything not in the input", "no bullet points" keep the note short, non-redundant with the structured fields, and free of hallucinated facts. The output is still schema-constrained (`{ summary }`) so it slots into the record like every other field.

Tradeoffs: this is a third LLM call purely for readability; the structured fields already contain everything. I kept it because the assessment's criterion is "could a downstream team act on it without additional work", and a two-sentence handoff is what a human reads first. With more time I would make the summary optional per queue (engineering may prefer the structured block only), add the customer's tone/sentiment to help support agents, and A/B the note length with real agents.
