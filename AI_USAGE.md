# AI usage log

The assessment encourages using AI assistants and says the interview will ask "what the AI got wrong that you had to fix". This is that record. I used **Claude** (claude.ai with a linked folder) as a pair programmer for the whole build: planning, generating the workflow JSON and the Code-node JavaScript, the prompts, the scripts, and the first drafts of these documents. Every decision below was mine; most first drafts were the AI's.

## What I used it for

| Phase | What I asked for | What I kept / changed |
|---|---|---|
| Plan | Read the assessment and propose a plan, stack and timeline | Kept the stack (n8n self-hosted + webhook.site + JSON file). Chose the per-step design and the "rules, not LLM, for routing" principle together. |
| Setup | docker-compose for n8n, folder skeleton, sample-sender scripts | Kept; the compose file changed twice (see mistakes 5–6). |
| Prompts | Three prompts + JSON schemas derived from the assessment's steps 2, 3, 5 | Reviewed each line against the assessment; kept the disambiguation rules and the "do not inflate confidence" instruction; the $500 "amount in dispute" interpretation is my call. |
| Workflow | A generator script that writes the 14-node n8n workflow JSON | Imported it, then **rebuilt the whole workflow by hand in the n8n editor** on day 2 to make sure I understood every node and setting; the submitted export is that rebuild. |
| Docs | First drafts of the prompt rationales, this file and the README | Edited for accuracy and for what I would actually say in an interview. |

## What the AI got wrong, and the fix

1. **n8n HTTP node body.** The generated HTTP Request nodes built the JSON body as a JavaScript object inside an n8n expression. n8n's JSON Body field needs a JSON *string*, so every call failed with "The value in the JSON Body field is not valid JSON". Fix: build the request object in the preceding Code node and send `{{ JSON.stringify($json.request) }}` — which also moved all prompt handling into readable code.
2. **Broken string escaping in generated code.** A patch to the generator turned `'\n'` into a real line break inside a JavaScript string literal → `SyntaxError: Invalid or unexpected token` in the Prompt Library node. Fix: corrected the escaping and added a `node --check` syntax check on every Code node's code before importing.
3. **Retired model name.** The AI defaulted to `gemini-2.5-flash`; the API answered "no longer available to new users". Fix: listed the models my key could access via the `/models` endpoint and picked from that list. Lesson kept in the design: the model name lives in one config value.
4. **Deprecated parameter.** The Anthropic request included `temperature: 0`; current Claude models reject it ("`temperature` is deprecated for this model"). Fix: removed it; determinism comes from the forced tool schema.
5. **SQLite on a Windows bind mount.** The first compose file mounted n8n's data directory from the Windows folder; n8n froze repeatedly. Fix: a Docker named volume for n8n's own data, keeping only `./data` (the records) as a bind mount.
6. **No backup plan.** After a container restart n8n came up empty once (owner account, credential and workflow gone). Fix: fixed `N8N_ENCRYPTION_KEY` in `.env` and `n8n export/import` backup/restore scripts — a 30-second recovery instead of a rebuild.
7. **Free-tier limits not anticipated.** The plan assumed Gemini's free tier would be enough; three LLM calls per message × retries hit a 503 and then the daily cap in one afternoon. Fix: switched to the Anthropic API (paid, fast), kept Gemini as a config-level fallback, and wrote retries/backoff and provider failover into the production section.
8. **PowerShell argument parsing.** A helper script took a list of ids; called with `-File`, PowerShell passed them as one string. Fix: split on commas inside the script. Small, but it is in the repo.

## What I checked myself

- Every record in `output/records.json` against the assessment's steps 2–6 (category, priority, confidence, entities, queue, escalation flag, summary).
- That the exported workflow contains **no API keys** (credentials are stored in n8n, not in the file) before adding it to the repo.
- The two extra test messages (REQ-0006, REQ-0007) exist because the five samples never trigger the low-confidence fallback or the >$500 rule on their own; without them those two paths would be untested code.
