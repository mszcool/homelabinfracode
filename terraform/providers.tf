provider "incus" {
  # Use Incus remotes already configured in your local Incus config directory
  # The config_dir points to where your client certificates and remotes.yaml are stored
  # This respects the INCUS_CONF environment variable if set
  
  # Example: If INCUS_CONF=/home/mszcool/incus/ring0/
  # Then Terraform will use the remotes configured in that directory
}
