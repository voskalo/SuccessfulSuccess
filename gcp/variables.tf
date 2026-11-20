variable "project_id" {
  description = "The Google Cloud project. Permanent and globally unique."
  type        = string
}

variable "region" {
  description = "Where the database, the API and the image registry live."
  type        = string
  default     = "us-central1"
}

variable "project_name" {
  description = "Prefix for resource names, the same as on AWS."
  type        = string
  default     = "successfulsuccess"
}

variable "image_tag" {
  description = "The backend image tag in Artifact Registry to run on Cloud Run."
  type        = string
  default     = "latest"
}

variable "db_running" {
  description = "false stops the Cloud SQL instance: compute stops billing, its storage still bills."
  type        = bool
  default     = true
}

variable "app_timezone" {
  description = "The timezone that decides what \"today\" is."
  type        = string
  default     = "Europe/Kyiv"
}

# Sign-in stays on AWS for now: the API checks Cognito access tokens.
variable "cognito_region" {
  description = "The region of the Cognito user pool."
  type        = string
  default     = "us-east-1"
}

variable "cognito_user_pool_id" {
  description = "The Cognito user pool whose tokens the API accepts (infra/ output user_pool_id)."
  type        = string
}

variable "cognito_client_id" {
  description = "The Cognito app client (infra/ output user_pool_client_id)."
  type        = string
}
