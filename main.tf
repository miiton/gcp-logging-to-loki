variable "gcp_project" {}
variable "gcp_region" {}
variable "gcp_zone" {}
variable "loki_url" {}
variable "loki_tenant_id" {}
variable "loki_labels" {}

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.24.0"
    }
  }
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
  zone    = var.gcp_zone
}

resource "google_pubsub_topic" "bq_job_statistics_topic" {
  name = "bq-job-statistics-topic"
}

resource "google_logging_project_sink" "bq_job_completed" {
  name                   = "bq-job-completed-sink"
  filter                 = "resource.type=bigquery_resource AND protoPayload.methodName=jobservice.jobcompleted"
  destination            = "pubsub.googleapis.com/${google_pubsub_topic.bq_job_statistics_topic.id}"
  unique_writer_identity = true
}

resource "google_project_iam_member" "bq_job_completed" {
  project = var.gcp_project
  role    = "roles/pubsub.publisher"
  member  = google_logging_project_sink.bq_job_completed.writer_identity
}

resource "google_logging_project_sink" "bq_job_inserted" {
  name                   = "bq-job-insert-sink"
  filter                 = "resource.type=bigquery_resource AND protoPayload.methodName=jobservice.insert"
  destination            = "pubsub.googleapis.com/${google_pubsub_topic.bq_job_statistics_topic.id}"
  unique_writer_identity = true
}

resource "google_project_iam_member" "bq_job_inserted" {
  project = var.gcp_project
  role    = "roles/pubsub.publisher"
  member  = google_logging_project_sink.bq_job_inserted.writer_identity
}

resource "google_storage_bucket" "function_assets" {
  name     = "${var.gcp_project}_function-assets"
  location = "US"
}

resource "google_storage_bucket_object" "push_function" {
  name   = "push_bq_query_statistic.zip"
  bucket = google_storage_bucket.function_assets.name
  source = "./push_bq_query_statistics/dist/function.zip"
}

resource "google_cloudfunctions_function" "push_function" {
  name        = "bq-query-statistics-push"
  description = "BigQuery query statistics log push to Loki."
  runtime     = "go116"

  available_memory_mb   = 128
  source_archive_bucket = google_storage_bucket.function_assets.name
  source_archive_object = google_storage_bucket_object.push_function.name
  timeout               = 60
  entry_point           = "Push"

  event_trigger {
    event_type = "google.pubsub.topic.publish"
    resource   = google_pubsub_topic.bq_job_statistics_topic.name
  }

  environment_variables = {
    LOKI_URL       = var.loki_url
    LOKI_TENANT_ID = var.loki_tenant_id
    LOKI_LABELS    = var.loki_labels
  }
}
