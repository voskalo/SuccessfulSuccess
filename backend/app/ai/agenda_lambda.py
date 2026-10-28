"""AWS Lambda entry point: the agenda parser behind its own function URL.

Runs outside the VPC: it needs no database, only Bedrock and Cognito's JWKS.
It never writes anything; saving goes through the main API.
"""

import asyncio
import base64
import json
import logging
import time
from datetime import date

from botocore.exceptions import BotoCoreError, ClientError

from app.ai.agenda import PROMPT_VERSION, AgendaParseError, cost_usd, parse_agenda
from app.auth import AuthError, CurrentUser, get_verifier
from app.config import settings

MAX_TEXT_LENGTH = 10_000
THROTTLING_CODES = {"ThrottlingException", "TooManyRequestsException"}

log = logging.getLogger("meetings.ai")
log.setLevel(logging.INFO)

# One loop for the life of the execution environment, so the verifier's cached
# signing keys survive from one invocation to the next.
_loop = asyncio.new_event_loop()


def verify_cognito_token(authorization: str) -> CurrentUser:
    """Check the Cognito access token from Lab 4; raises AuthError."""
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise AuthError("Sign in to continue.")
    return _loop.run_until_complete(get_verifier().verify(token))


def _response(status: int, body: dict) -> dict:
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body),
    }


def handler(event, context):
    try:
        user = verify_cognito_token(event.get("headers", {}).get("authorization", ""))
    except AuthError as e:
        return _response(401, {"error": str(e)})

    try:
        raw = event.get("body") or ""
        if event.get("isBase64Encoded"):
            raw = base64.b64decode(raw).decode()
        body = json.loads(raw)
        text, today, tz = body["text"], date.fromisoformat(body["today"]), body["tz"]
    except (ValueError, KeyError, TypeError):
        return _response(400, {"error": "send JSON with text, today (YYYY-MM-DD) and tz"})
    if len(text) > MAX_TEXT_LENGTH:
        return _response(413, {"error": f"the text is longer than {MAX_TEXT_LENGTH} characters"})

    started = time.monotonic()
    try:
        agenda, usage = parse_agenda(text, today, tz)
    except AgendaParseError as e:
        return _response(422, {"error": str(e)})
    except ClientError as e:
        code = e.response.get("Error", {}).get("Code", "")
        if code in THROTTLING_CODES:
            log.warning(json.dumps({"event": "agenda_throttled", "user": user.sub}))
            return _response(429, {"error": "the model is busy, try again in a minute"})
        log.error(json.dumps({"event": "agenda_failed", "user": user.sub, "error": code}))
        return _response(502, {"error": "the model is unavailable"})
    except BotoCoreError as e:
        log.error(json.dumps({"event": "agenda_failed", "user": user.sub, "error": str(e)}))
        return _response(502, {"error": "the model is unavailable"})

    log.info(
        json.dumps(
            {
                "event": "agenda_parsed",
                "user": user.sub,
                "model": settings.parser_model,
                "prompt_version": PROMPT_VERSION,
                **usage,
                "latency_ms": int((time.monotonic() - started) * 1000),
                "cost_usd": cost_usd(settings.parser_model, usage),
            }
        )
    )
    return _response(
        200,
        {
            "agenda": agenda.model_dump(mode="json"),
            "model": settings.parser_model,
            "prompt_version": PROMPT_VERSION,
        },
    )
