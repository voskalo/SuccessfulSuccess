"""`make llm-hello`: one call to Claude through the Bedrock Converse API."""

import boto3

from app.config import settings


def main() -> None:
    client = boto3.client("bedrock-runtime", region_name="us-east-1")
    resp = client.converse(
        modelId=settings.parser_model,
        messages=[{"role": "user", "content": [{"text": "In one sentence: what is an ISO week?"}]}],
        inferenceConfig={"maxTokens": 1024},
    )
    print(resp["output"]["message"]["content"][0]["text"])
    print(resp["stopReason"], resp["usage"]["inputTokens"], resp["usage"]["outputTokens"])


if __name__ == "__main__":
    main()
