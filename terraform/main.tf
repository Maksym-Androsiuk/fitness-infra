terraform {
  backend "gcs" {
    bucket = "terraform-state-maksym-fitness"
    prefix = "terraform/state"
  }
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_project_service" "compute_api" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_compute_network" "vpc_network" {
  name                    = "fitness-vpc"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.compute_api]
}

resource "google_compute_subnetwork" "subnet" {
  name          = "fitness-subnet"
  ip_cidr_range = "10.0.0.0/16"
  network       = google_compute_network.vpc_network.id
  region        = var.region
}

resource "google_artifact_registry_repository" "fitness_repo" {
  location      = var.region
  repository_id = "fitness-repo"
  description   = "Docker repository for Fitness App"
  format        = "DOCKER"
}

resource "google_service_account" "gke_sa" {
  account_id   = "gke-fitness-sa"
  display_name = "GKE Service Account"
}

resource "google_project_iam_member" "gke_sa_roles" {
  for_each = toset([
    "roles/artifactregistry.reader",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter"
  ])
  project = var.project_id
  role    = each.key
  member  = "serviceAccount:${google_service_account.gke_sa.email}"
}

# ==========================================
# ОНОВЛЕНИЙ БЛОК: Зональний GKE Кластер
# ==========================================
resource "google_container_cluster" "primary" {
  name     = "fitness-gke-cluster"
  
  # Використовуємо конкретну зону для пришвидшення деплою та економії
  location = "europe-west1-a" 

  # Збережено твої налаштування мережі
  network    = google_compute_network.vpc_network.id
  subnetwork = google_compute_subnetwork.subnet.id

  remove_default_node_pool = true
  initial_node_count       = 1
}

# ==========================================
# ОНОВЛЕНИЙ БЛОК: Пул робочих нод
# ==========================================
resource "google_container_node_pool" "primary_nodes" {
  name       = "fitness-node-pool"
  
  # Локація строго збігається з локацією кластера
  location   = "europe-west1-a" 
  
  # Використовуємо .id замість .name для точного API-мапінгу
  cluster    = google_container_cluster.primary.id 

  node_count = 1

  node_config {
    preemptible  = true
    machine_type = "e2-medium"
    disk_size_gb = 20

    service_account = google_service_account.gke_sa.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }
}