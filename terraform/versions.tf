terraform {
  required_version = ">= 1.5.0"

  required_providers {
    incus = {
      source  = "lxc/incus"
      version = "~> 1.0"
    }
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 2.0"
    }
  }

  # Uncomment for remote state management
  # backend "s3" {
  #   bucket         = "homelab-terraform"
  #   key            = "incus/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }
}
