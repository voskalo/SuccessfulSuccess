"""AWS Lambda entry point: the report builder."""

import datetime
import json
import logging
import os

import boto3
from app.reports.weekly import build_weekly_report

# Configure structured logging to standard output
logger = logging.getLogger()
logger.setLevel(logging.INFO)
# Remove default lambda handlers so we can format nicely if we wanted, but default is fine
# Just making sure we log info level.


def detect_trigger(event: dict) -> str:
    """Determine what triggered the function."""
    if "Records" in event and event["Records"][0].get("eventSource") == "aws:sqs":
        return "sqs"
    return "schedule"


def get_previous_iso_week() -> str:
    """Return the previous ISO week string, e.g. '2026-W39'."""
    today = datetime.date.today()
    last_week = today - datetime.timedelta(days=7)
    return f"{last_week.isocalendar().year}-W{last_week.isocalendar().week:02d}"


def handler(event, context):
    """Entry point for the report-builder Lambda."""
    
    # 1. Parse the event
    trigger = detect_trigger(event)
    payload = event
    
    if trigger == "sqs":
        # Event comes wrapped in an SQS record
        body = event["Records"][0]["body"]
        if isinstance(body, str):
            payload = json.loads(body)
        else:
            payload = body

    week = payload.get("week")
    if not week:
        week = get_previous_iso_week()

    # 2. Log exactly as requested
    logger.info(f"report-builder triggered by {trigger} for week {week}")

    # 3. Build the report
    csv_bytes = build_weekly_report(week)
    
    # 4. Upload to S3
    bucket_name = os.environ["REPORTS_BUCKET"]
    key = f"reports/{week}.csv"
    
    s3 = boto3.client("s3")
    s3.put_object(
        Bucket=bucket_name,
        Key=key,
        Body=csv_bytes,
        ContentType="text/csv"
    )
    
    return {"status": "success", "week": week, "key": key}

