terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
  backend "gcs" {
    bucket  = "terraform-state-maksym-fitness" # Змініть на свій бакет
    prefix  = "terraform/state"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# 1. Artifact Registry (заміна Container Registry)
resource "google_artifact_registry_repository" "fitness_repo" {
  location      = var.region
  repository_id = "fitness-app-repo"
  description   = "Docker repository for Fitness App"
  format        = "DOCKER"
}

# 2. VPC Network
resource "google_compute_network" "vpc" {
  name                    = "fitness-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  name          = "fitness-subnet"
  region        = var.region
  network       = google_compute_network.vpc.name
  ip_cidr_range = "10.10.0.0/24"
}

# 3. GKE Cluster
resource "google_container_cluster" "primary" {
  name     = "fitness-gke-cluster"
  location = var.region
  
  # Використовуємо окремий node pool для кращого керування
  remove_default_node_pool = true
  initial_node_count       = 1
  
  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.subnet.name
}

resource "google_container_node_pool" "primary_nodes" {
  name       = "fitness-node-pool"
  location   = var.region
  cluster    = google_container_cluster.primary.name
  node_count = 2

  node_config {
    preemptible  = true # Дешевше для навчальних цілей
    machine_type = "e2-medium"
    
    # Доступи для pulling images з Artifact Registry
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}