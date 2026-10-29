import logging
import os
from email.message import EmailMessage

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client("s3")
ses = boto3.client("sesv2")


def handler(event, context):
    logger.info("report-mailer triggered by s3")

    record = event["Records"][0]
    bucket = record["s3"]["bucket"]["name"]
    key = record["s3"]["object"]["key"]

    # Download CSV
    response = s3.get_object(Bucket=bucket, Key=key)
    csv_data = response["Body"].read()

    # Build email
    sender = os.environ["SENDER_EMAIL"]
    msg = EmailMessage()
    msg["Subject"] = "Weekly Meetings Report"
    msg["From"] = sender
    msg["To"] = sender
    msg.set_content("Please find the weekly meetings report attached.")

    msg.add_attachment(
        csv_data,
        maintype="text",
        subtype="csv",
        filename=key.split("/")[-1],
    )

    # Send email
    ses.send_email(
        FromEmailAddress=sender,
        Destination={"ToAddresses": [sender]},
        Content={"Raw": {"Data": msg.as_bytes()}},
    )

    return {"status": "sent", "key": key}
