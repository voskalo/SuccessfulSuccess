# ADR 0006: Parse pasted agendas with Claude on Amazon Bedrock

- Status: Accepted
- Date: 2026-10-15

## Context

Agendas reach our users as emails, chat messages and notes, not as forms.
"Paste an agenda" lets a user paste that text into a meeting. An LLM turns it
into a structured agenda, and the app shows the normal agenda form, pre-filled,
for the user to check and save. The model suggests, and the person decides.

Constraints:

- **No NAT.** The API and the database live in private subnets with no NAT
  gateway and no interface endpoints, so the system costs ~$0 when idle (Lab 4).
- **Cost.** Every model call is billed per token, so an open endpoint is a
  wallet without a lock.
- **Text from outside.** Pasted text comes from emails and invites that anyone
  can write. It may contain instructions aimed at the model (prompt injection).

## Decision

- **Model:** Claude Haiku 4.5 on Amazon Bedrock, through the Converse API with the
  inference-profile ID `us.anthropic.claude-haiku-4-5-20251001-v1:0`. It is much
  cheaper than Claude Opus 5.5, and parsing a short agenda is a small extraction
  task. The model ID is configuration (`PARSER_MODEL`), so another model replaces
  it without a code change. Opus 5.5 is the lab's named model, but Bedrock did
  not enable it for this account (HTTP 403) when this was written.
- **Client: Converse API, not the Messages API on bedrock-mantle.** The lab asks
  for the Messages API on bedrock-mantle. On 2026-10-28, that endpoint returned
  HTTP 404 "does not exist" for Haiku 4.5, and the same model answered through
  Converse with the inference-profile ID. Part 1 of the lab lists older Claude
  models under Converse. The validation, retry and logging logic is unchanged.
  The IAM permission is `bedrock:InvokeModel`, not `bedrock-mantle:CreateInference`.
- **A schema, not free text.** The model must answer by calling one tool,
  `record_agenda`, whose input schema is the `ParsedAgenda` Pydantic model. The
  answer is validated. An invalid answer gets one retry with the validation
  error, and after that the parser returns 422. Nothing invalid leaves the parser.
- **The parser runs outside the VPC,** as its own Lambda function with a function
  URL (`infra/ai.yml`). It receives text and returns JSON, and it needs no
  database. Outside the VPC it reaches Bedrock and Cognito's JWKS over the
  internet with no NAT and no VPC endpoint, and it costs nothing while unused.
  It reuses the backend's container image with another handler.
- **The model never writes.** The parser has no database access and no write
  tools. Save goes through the existing meetings API with its usual validation
  and ownership checks. The API stores what the model suggested, the model and
  the prompt version in an `ai_suggestion` column next to the saved agenda.
- **Guard rails on the endpoint:** a valid Cognito access token (401 otherwise),
  at most 10,000 characters of text (413, checked before any model call), and a
  $5 monthly AWS Budgets alarm.

## Alternatives considered

- **Call Bedrock from the API through a VPC interface endpoint.** It lost because
  the endpoint costs ~$7.30 a month even when nobody parses anything, which breaks
  "$0 when idle". The parse also needs nothing that lives in the VPC.
- **The Claude API directly instead of Bedrock.** It lost because it needs an API
  key to store and rotate, and its bill sits outside the AWS account. Bedrock uses
  the function's IAM role, bills to the AWS account where the budget alarm
  watches it, and logs to CloudWatch and CloudTrail like everything else.
- **A plain regular-expression parser.** It lost because real agendas come in any
  language and any layout ("Пн 10:00, 45 хв", "next Tuesday after lunch"). A
  regex handles only the formats someone wrote rules for, and it cannot resolve
  relative dates. It would be free and deterministic, but it would fail on most
  of what users paste.

## Consequences

- **Cost per parse:** about 1,500–3,000 input tokens and a few hundred output
  tokens. At list prices that is about $0.003 with Haiku 4.5, against
  roughly $0.01–0.02 with Opus 5.5. The measured value is in the `agenda_parsed`
  log lines.
- **What is logged:** one JSON line per parse in CloudWatch, with the user's
  Cognito `sub`, the model, the prompt version, input and output tokens, latency
  and cost in dollars. The pasted text is not logged.
- **Quality signal:** the difference between `ai_suggestion` and the saved agenda
  shows every correction the user made, with no extra effort from the user.
- **When Bedrock is down or throttling,** the parser returns 429 or 502 and the
  screen says so. The user types the agenda by hand in the same form, and
  everything else in the app keeps working, because nothing else depends on the
  parser.
- **Prompt injection is limited, not solved.** The text is delimited and the
  system prompt calls it data. Even if the model obeys injected text, it can only
  change a suggestion that the user sees and must save themselves.
- **One more public URL.** It is authenticated and size-limited, but it has no
  per-user rate limit yet. The budget alarm is the backstop.
