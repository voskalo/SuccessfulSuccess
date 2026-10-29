# Non-secret values only. Secrets (db_password, google_client_secret) and the
# email address (ses_email) are variables of the HCP Terraform workspace.
project_name     = "successfulsuccess"
region           = "us-east-1"
app_urls         = ["http://localhost:3000/", "https://d1x5zfouftkeqp.cloudfront.net/"]
cors_origins     = ["https://d1x5zfouftkeqp.cloudfront.net"]
google_client_id = "134328590389-tdf04897frndt430nn2mii3dn4s56mj3.apps.googleusercontent.com"

# The backend image, pinned by digest. make aws-push prints a new one.
image_uri = "112372944251.dkr.ecr.us-east-1.amazonaws.com/successfulsuccess-backend@sha256:83e3636f1ba1ee2f232a0509c61d7be11aac8911f0b9cc5007b52e3cb4cfe356"
