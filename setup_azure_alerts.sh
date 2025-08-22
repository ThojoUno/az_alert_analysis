#!/bin/bash

#################################################################################
# Azure Alerts Analyzer - Initial Setup Script for Ubuntu 24.04 LTS
#################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}================================================================================================${NC}"
echo -e "${GREEN}Azure Alerts Analyzer - Setup for Ubuntu 24.04 LTS (Noble Numbat)${NC}"
echo -e "${CYAN}================================================================================================${NC}"
echo ""

# Check Ubuntu version
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo -e "${BLUE}Detected: $NAME $VERSION${NC}"
    if [[ "$VERSION_ID" != "24.04" ]]; then
        echo -e "${YELLOW}Warning: This script is optimized for Ubuntu 24.04${NC}"
    fi
fi

# Step 1: Update system
echo -e "${BLUE}Step 1: Updating system packages...${NC}"
sudo apt update && sudo apt upgrade -y

# Step 2: Install prerequisites
echo -e "${BLUE}Step 2: Installing prerequisites...${NC}"
# Ubuntu 24 uses python3.12 by default
sudo apt install -y python3 python3-pip python3-venv curl jq wget

# Step 3: Install Azure CLI
echo -e "${BLUE}Step 3: Installing Azure CLI...${NC}"
if ! command -v az &> /dev/null; then
    # Install required packages for Azure CLI repository
    sudo apt install -y ca-certificates curl apt-transport-https lsb-release gnupg
    
    # Download and install Microsoft signing key
    sudo mkdir -p /etc/apt/keyrings
    curl -sLS https://packages.microsoft.com/keys/microsoft.asc | \
        gpg --dearmor | \
        sudo tee /etc/apt/keyrings/microsoft.gpg > /dev/null
    sudo chmod go+r /etc/apt/keyrings/microsoft.gpg
    
    # Add Azure CLI repository
    AZ_DIST=$(lsb_release -cs)
    echo "deb [arch=`dpkg --print-architecture` signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $AZ_DIST main" | \
        sudo tee /etc/apt/sources.list.d/azure-cli.list
    
    # Update and install Azure CLI
    sudo apt update
    sudo apt install -y azure-cli
else
    echo -e "${GREEN}Azure CLI already installed${NC}"
fi

# Step 4: Verify installations
echo ""
echo -e "${BLUE}Step 4: Verifying installations...${NC}"

check_command() {
    if command -v $1 &> /dev/null; then
        echo -e "${GREEN}✓ $1 is installed${NC}"
        $1 --version 2>&1 | head -n1
        return 0
    else
        echo -e "${RED}✗ $1 is not installed${NC}"
        return 1
    fi
}

all_good=true
check_command python3 || all_good=false
check_command pip3 || all_good=false
check_command curl || all_good=false
check_command jq || all_good=false
check_command az || all_good=false

if $all_good; then
    echo ""
    echo -e "${GREEN}✅ All prerequisites installed successfully!${NC}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo -e "1. Run: ${CYAN}az login --tenant <tenant-id>${NC} to authenticate with Azure"
    echo -e "2. Run: ${CYAN}./azure_alerts_analyzer.sh${NC} to start analyzing alerts"
    echo ""
    echo -e "${GREEN}Optional: Set default subscription${NC}"
    echo -e "   ${CYAN}az account set --subscription <subscription-id>${NC}"
else
    echo ""
    echo -e "${RED}Some prerequisites failed to install${NC}"
    echo -e "Please check the error messages above and try manual installation"
fi

# Step 5: Make main script executable
if [ -f "azure_alerts_analyzer.sh" ]; then
    chmod +x azure_alerts_analyzer.sh
    echo -e "${GREEN}✓ Main script is now executable${NC}"
fi

echo ""
echo -e "${CYAN}================================================================================================${NC}"
