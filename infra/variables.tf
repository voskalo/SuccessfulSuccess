variable "project_name" {
  type        = string
  description = "Prefix for every resource name. Must match the PROJECT_NAME tag of the other stacks."
  default     = "successfulsuccess"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "app_urls" {
  type        = list(string)
  description = "Every URL the site is served from, each ending in '/'. Cognito sends people back there."
  default     = ["http://localhost:3000/"]
}

variable "google_client_id" {
  type        = string
  description = "OAuth client id of a Google 'Web application' client. Empty leaves Google sign-in out."
  default     = ""
}

variable "google_client_secret" {
  type      = string
  default   = ""
  sensitive = true
}

variable "image_uri" {
  type        = string
  description = "Backend container image pinned by digest: <repo>@sha256:<digest>. Built and pushed by make aws-push."
}

variable "architecture" {
  type    = string
  default = "x86_64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "architecture must be x86_64 or arm64."
  }
}

variable "parser_model" {
  type        = string
  description = "The Bedrock model the agenda parser calls."
  default     = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
}

variable "cors_origins" {
  type        = list(string)
  description = "Origins allowed to call the agenda parser from the browser."
  default     = ["*"]
}

variable "ses_email" {
  type        = string
  description = "Verified SES identity: sender and recipient of the weekly report."
}

variable "budget_email" {
  type        = string
  description = "Where the monthly AWS Budgets alarm is sent. Empty uses ses_email."
  default     = ""
}

variable "budget_limit_usd" {
  type    = number
  default = 5
}

variable "app_timezone" {
  type    = string
  default = "Europe/Kyiv"
}

variable "db_password" {
  type        = string
  description = "Master password of the database created by infra/backend.yml. Set as TF_VAR_db_password, never in a file."
  sensitive   = true
}
