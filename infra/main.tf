terraform {
  backend "gcs" {
  }
}

variable "project_id" {
  description = "The project ID"
  type        = string
  default     = "shikanime-studio-labs"
}

variable "location" {
  description = "The location"
  type        = string
  default     = "europe"
}

variable "region" {
  description = "The region"
  type        = string
  default     = "europe-west1"
}

variable "zone" {
  description = "The zone"
  type        = string
  default     = "europe-west1-b"
}

variable "name" {
  description = "The name"
  type        = string
  default     = "oracle-cdc"
}

variable "display_name" {
  description = "The display name"
  type        = string
  default     = "Oracle CDC"
}

variable "password" {
  description = "The password"
  type        = string
  default     = "sTGYtm5EYwgj5t"
  sensitive   = true
}

variable "ip_ranges" {
  description = "The IP ranges"
  type        = map(string)
  default = {
    database   = "10.128.0.0/24"
    datastream = "10.128.1.0/24"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_artifact_registry_repository" "default" {
  project       = var.project_id
  repository_id = var.name
  format        = "DOCKER"
  location      = var.region
}

resource "google_artifact_registry_repository_iam_member" "default" {
  repository = google_artifact_registry_repository.default.name
  role       = "roles/artifactregistry.reader"
  member     = module.service_accounts.iam_email
}

module "service_accounts" {
  source  = "terraform-google-modules/service-accounts/google"
  version = "~> 4.0"

  project_id    = var.project_id
  names         = [var.name]
  project_roles = []
}

module "container_vm" {
  source  = "terraform-google-modules/container-vm/google"
  version = "~> 3.1"

  container = {
    image = "europe-west1-docker.pkg.dev/shikanime-studio-labs/oracle-cdc-containers/oracle/database"
    env = [
      {
        name  = "ORACLE_PWD"
        value = var.password
      }
    ],
  }
  restart_policy = "Always"
}

module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "~> 9.1"

  project_id   = var.project_id
  network_name = var.name
  routing_mode = "GLOBAL"
  subnets = [
    {
      subnet_name           = var.name
      subnet_ip             = var.ip_ranges.database
      subnet_region         = "europe-west1"
      subnet_private_access = "true"
    },
  ]
  ingress_rules = [
    {
      name        = "allow-ssh"
      description = "Allow SSH from anywhere"
      source_ranges = [
        "35.235.240.0/20"
      ]
      target_tags = [
        "allow-ssh"
      ]
      allow = [
        {
          protocol = "tcp"
          ports    = ["22"]
        }
      ]
    },
    {
      name        = "allow-oracle-database-from-datastream"
      description = "Allow Oracle Database port to Datastream IP range"
      source_ranges = [
        var.ip_ranges.datastream
      ]
      target_service_accounts = [
        module.service_accounts.email
      ]
      allow = [
        {
          protocol = "tcp"
          ports    = ["1521"]
        }
      ]
    }
  ]
}

module "instance_template" {
  source  = "terraform-google-modules/vm/google//modules/instance_template"
  version = "~> 11.0"

  region             = var.region
  project_id         = var.project_id
  subnetwork         = module.vpc.subnets_names[0]
  subnetwork_project = var.project_id
  service_account = {
    email  = module.service_accounts.email
    scopes = ["storage-ro"]
  }
  machine_type = "e2-medium"
  tags         = ["allow-ssh"]
  metadata = {
    gce-container-declaration = module.container_vm.metadata_value
    google-logging-enabled    = "true"
    google-monitoring-enabled = "true"
  }
  labels = {
    container-vm = module.container_vm.vm_container_label
  }
  source_image = module.container_vm.source_image
  spot         = true
}

module "compute_instance" {
  source  = "terraform-google-modules/vm/google//modules/compute_instance"
  version = "~> 11.0"

  region              = var.region
  zone                = var.zone
  subnetwork          = module.vpc.subnets_names[0]
  num_instances       = 1
  hostname            = var.name
  instance_template   = module.instance_template.self_link
  deletion_protection = false
}

resource "google_datastream_connection_profile" "source" {
  project               = var.project_id
  display_name          = var.display_name
  location              = var.region
  connection_profile_id = var.name
  oracle_profile {
    hostname         = module.compute_instance.instances_details[0].network_interface[0].network_ip
    port             = 1521
    username         = "system"
    password         = var.password
    database_service = "FREEPDB1"
  }
  private_connectivity {
    private_connection = google_datastream_private_connection.default.id
  }
}

resource "google_datastream_private_connection" "default" {
  project               = var.project_id
  display_name          = var.display_name
  location              = var.region
  private_connection_id = var.name
  vpc_peering_config {
    vpc    = module.vpc.network_id
    subnet = var.ip_ranges.datastream
  }
}

resource "google_datastream_connection_profile" "destination" {
  display_name          = "${var.display_name} BigQuery"
  location              = var.region
  connection_profile_id = "${var.name}-bigquery"
  bigquery_profile {}
}

resource "google_bigquery_dataset" "dataset" {
  project       = var.project_id
  dataset_id    = replace(var.name, "-", "_")
  friendly_name = var.display_name
  location      = var.location == "europe" ? "EU" : var.location
}

resource "google_datastream_stream" "default" {
  stream_id                 = var.name
  desired_state             = "RUNNING"
  create_without_validation = true
  location                  = var.region
  display_name              = var.display_name
  source_config {
    source_connection_profile = google_datastream_connection_profile.source.id
    oracle_source_config {
      include_objects {
        oracle_schemas {
          schema = "SYSTEM"
          oracle_tables {
            table = "PEOPLE_FULL_NAMES"
          }
        }
      }
    }
  }
  destination_config {
    destination_connection_profile = google_datastream_connection_profile.destination.id
    bigquery_destination_config {
      data_freshness = "0s"
      single_target_dataset {
        dataset_id = google_bigquery_dataset.dataset.id
      }
    }
  }
  backfill_all {
  }
}
