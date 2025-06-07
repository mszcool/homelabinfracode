# Terraform Installation Guide

Before using the VM automation, you need to install Terraform on your system.

## Linux Installation (Ubuntu/Debian)

```bash
# Install prerequisites
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common

# Add HashiCorp GPG key
wget -O- https://apt.releases.hashicorp.com/gpg | \
    gpg --dearmor | \
    sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg

# Add HashiCorp repository
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
    https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/hashicorp.list

# Update and install Terraform
sudo apt update
sudo apt-get install terraform

# Verify installation
terraform version
```

## Alternative Installation Methods

### Using Snap
```bash
sudo snap install terraform
```

### Using Binary Download
```bash
# Download latest version (check https://releases.hashicorp.com/terraform/ for latest)
wget https://releases.hashicorp.com/terraform/1.7.5/terraform_1.7.5_linux_amd64.zip

# Extract and install
unzip terraform_1.7.5_linux_amd64.zip
sudo mv terraform /usr/local/bin/
terraform version
```

## Windows Installation

### Using Chocolatey
```powershell
choco install terraform
```

### Using Scoop
```powershell
scoop install terraform
```

### Manual Installation
1. Download from https://releases.hashicorp.com/terraform/
2. Extract to a directory in your PATH
3. Verify with `terraform version`

## Verification

After installation, verify Terraform is working:
```bash
terraform version
terraform help
```

## Provider-Specific Prerequisites

### Incus Provider
```bash
# Install Incus
sudo snap install incus --classic

# Initialize Incus
sudo incus admin init --minimal

# Add your user to incus group
sudo usermod -a -G incus $USER

# Log out and back in, then verify
incus list
```

### Hyper-V Provider (Windows)
```powershell
# Enable Hyper-V (requires restart)
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All

# Verify Hyper-V is enabled
Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V

# Check Hyper-V module
Get-Module -Name Hyper-V -ListAvailable
```

## Next Steps

After installing Terraform and the required providers:

1. Navigate to the terraform directory
2. Choose your provider (incus or hyperv)
3. Run the validation script: `./validate-config.sh`
4. Follow the deployment guide: `DEPLOYMENT-GUIDE.md`
