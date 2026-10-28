# Container diagram (C4, level 2)

The meetings app on AWS after Lab 6. New in Lab 6: the **agenda parser**
function, **Amazon Bedrock**, and the two flows of Paste an agenda:

- **parse**: browser → agenda parser → Bedrock (Claude). Read-only: it returns
  a suggestion as JSON and writes nothing.
- **save**: browser → meetings API → database. The same validated path as every
  other write, which also stores the AI suggestion next to the saved agenda.

```mermaid
C4Container
    title Container diagram: SuccessfulSuccess meetings (Lab 6)

    Person(user, "User", "Plans meetings and their agendas")

    System_Boundary(app, "SuccessfulSuccess") {
        Container(spa, "Web app", "Next.js static export on S3 + CloudFront", "Today's meetings, meeting details, Add agenda and Paste an agenda")
        Container(api, "Meetings API", "FastAPI on Lambda (function URL), in the VPC", "Meetings and agendas; checks the Cognito token; the only path that writes")
        ContainerDb(db, "Database", "PostgreSQL on Amazon RDS, private subnets", "Meetings, participants, users, agendas with ai_suggestion")
        Container(parser, "Agenda parser", "Python on Lambda (function URL), outside the VPC", "Pasted text to a suggested agenda; checks the Cognito token; never writes")
        Container(builder, "Report builder", "Lambda in the VPC", "Builds the weekly CSV report")
        Container(mailer, "Report mailer", "Lambda outside the VPC", "Emails the report")
        ContainerQueue(queue, "Report requests", "Amazon SQS", "Scheduled and manual report requests")
        ContainerDb(bucket, "Reports bucket", "Amazon S3", "Weekly CSV reports")
    }

    System_Ext(cognito, "Amazon Cognito", "User pool: sign-in and access tokens")
    System_Ext(bedrock, "Amazon Bedrock", "Claude through the Anthropic Messages API (bedrock-mantle)")
    System_Ext(scheduler, "EventBridge Scheduler", "Monday 09:00")
    System_Ext(ses, "Amazon SES", "Email")

    Rel(user, spa, "Uses", "HTTPS")
    Rel(spa, cognito, "Signs in", "HTTPS")
    Rel(spa, parser, "parse: pasted text, today, tz", "HTTPS POST + access token")
    Rel(parser, bedrock, "parse: record_agenda tool call", "HTTPS, IAM role")
    Rel(parser, cognito, "Fetches JWKS", "HTTPS")
    Rel(spa, api, "save: agenda + ai_suggestion", "HTTPS POST + access token")
    Rel(api, db, "save: reads and writes", "PostgreSQL")
    Rel(scheduler, queue, "Weekly request")
    Rel(queue, builder, "Triggers")
    Rel(builder, db, "Reads", "PostgreSQL")
    Rel(builder, bucket, "Writes CSV", "S3 gateway endpoint")
    Rel(bucket, mailer, "Object created")
    Rel(mailer, ses, "Sends email")
```
