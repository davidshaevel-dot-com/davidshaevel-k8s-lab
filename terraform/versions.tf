terraform {
  required_version = ">= 1.9"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
  # Local state is intentional: the lab is throwaway and single-operator.
  # terraform.tfstate holds the database password; it is gitignored.
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {
    resource_group {
      # `make down` must always be able to delete the lab resource group.
      prevent_deletion_if_contains_resources = false
    }
  }
}
