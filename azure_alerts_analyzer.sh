#!/bin/bash

# Ensure this script is run with bash
if [ -z "$BASH_VERSION" ]; then
    echo "This script requires bash. Please run with: bash $0 $@"
    exit 1
fi

#################################################################################
# Azure Alerts Analysis Script
# Purpose: Download and analyze Azure alerts for specified time periods
# Features: Alert correlation, resource analysis, tuning recommendations
# Compatible with: Ubuntu 24.04 LTS (Noble Numbat), Ubuntu 22.04, Debian-based systems
#################################################################################

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

#################################################################################
# SETUP AND PREREQUISITE CHECK SECTION
#################################################################################

# Function to check if running on Ubuntu 24 or compatible distro
check_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo -e "${CYAN}Detected OS: $NAME $VERSION${NC}"
        
        # Check for Ubuntu 24 specifically
        if [[ "$ID" == "ubuntu" ]] && [[ "$VERSION_ID" == "24.04" ]]; then
            echo -e "${GREEN}✓ Ubuntu 24.04 LTS (Noble Numbat) detected - Fully compatible${NC}"
            return 0
        elif [[ "$ID" == "ubuntu" ]] && [[ "$VERSION_ID" > "22.00" ]]; then
            echo -e "${GREEN}✓ Compatible Ubuntu version detected${NC}"
            return 0
        elif [[ "$ID_LIKE" == *"ubuntu"* ]] || [[ "$ID" == "debian" ]]; then
            echo -e "${GREEN}✓ Compatible Debian-based distribution detected${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠ Warning: This script is optimized for Ubuntu 24.04 LTS${NC}"
            echo -e "${YELLOW}  Other distributions may require manual adjustment${NC}"
            read -p "Continue anyway? (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    else
        echo -e "${YELLOW}⚠ Cannot detect OS version${NC}"
    fi
}

# Function to check and install prerequisites
check_and_install_prerequisites() {
    echo -e "${CYAN}================================================================================================${NC}"
    echo -e "${GREEN}CHECKING AND INSTALLING PREREQUISITES${NC}"
    echo -e "${CYAN}================================================================================================${NC}"
    echo ""
    
    local needs_update=false
    local missing_packages=()
    
    # Check for Python 3
    echo -n -e "${BLUE}Checking Python 3...${NC} "
    if command -v python3 &> /dev/null; then
        PYTHON_VERSION=$(python3 --version 2>&1 | sed 's/Python //' | grep -o '[0-9]\+\.[0-9]\+')
        echo -e "${GREEN}✓ Found Python $PYTHON_VERSION${NC}"
    else
        echo -e "${RED}✗ Not found${NC}"
        missing_packages+=("python3")
        missing_packages+=("python3-pip")
    fi
    
    # Check for pip3
    echo -n -e "${BLUE}Checking pip3...${NC} "
    if command -v pip3 &> /dev/null; then
        PIP_VERSION=$(pip3 --version 2>&1 | grep -o 'pip [0-9]\+\.[0-9]\+')
        echo -e "${GREEN}✓ Found $PIP_VERSION${NC}"
    else
        echo -e "${YELLOW}✗ Not found${NC}"
        missing_packages+=("python3-pip")
    fi
    
    # Check for curl
    echo -n -e "${BLUE}Checking curl...${NC} "
    if command -v curl &> /dev/null; then
        CURL_VERSION=$(curl --version 2>&1 | head -n1 | grep -o 'curl [0-9]\+\.[0-9]\+')
        echo -e "${GREEN}✓ Found $CURL_VERSION${NC}"
    else
        echo -e "${RED}✗ Not found${NC}"
        missing_packages+=("curl")
    fi
    
    # Check for jq (JSON processor)
    echo -n -e "${BLUE}Checking jq...${NC} "
    if command -v jq &> /dev/null; then
        JQ_VERSION=$(jq --version 2>&1 | grep -o '[0-9]\+\.[0-9]\+')
        echo -e "${GREEN}✓ Found jq-$JQ_VERSION${NC}"
    else
        echo -e "${YELLOW}✗ Not found (optional but recommended)${NC}"
        missing_packages+=("jq")
    fi
    
    # Check for Azure CLI
    echo -n -e "${BLUE}Checking Azure CLI...${NC} "
    if command -v az &> /dev/null; then
        AZ_VERSION=$(az version --query '"azure-cli"' -o tsv 2>/dev/null)
        echo -e "${GREEN}✓ Found Azure CLI $AZ_VERSION${NC}"
        
        # Check if logged in
        echo -n -e "${BLUE}Checking Azure login status...${NC} "
        if az account show &> /dev/null; then
            CURRENT_SUB=$(az account show --query name -o tsv)
            echo -e "${GREEN}✓ Logged in to: $CURRENT_SUB${NC}"
        else
            echo -e "${YELLOW}✗ Not logged in${NC}"
            echo -e "${YELLOW}  Run 'az login --tenant <tenant-id>' after setup completes${NC}"
        fi
    else
        echo -e "${RED}✗ Not found${NC}"
        needs_update=true
    fi
    
    # Install missing system packages
    if [ ${#missing_packages[@]} -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}Missing packages detected: ${missing_packages[*]}${NC}"
        read -p "Install missing packages? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${CYAN}Updating package list...${NC}"
            sudo apt-get update
            
            echo -e "${CYAN}Installing missing packages...${NC}"
            sudo apt-get install -y "${missing_packages[@]}"
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✓ Packages installed successfully${NC}"
            else
                echo -e "${RED}✗ Package installation failed${NC}"
                exit 1
            fi
        fi
    fi
    
    # Install Azure CLI if missing
    if ! command -v az &> /dev/null; then
        echo ""
        echo -e "${YELLOW}Azure CLI is not installed${NC}"
        echo -e "${CYAN}Note: Azure CLI requires adding Microsoft's repository${NC}"
        read -p "Install Azure CLI from Microsoft repository? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${CYAN}Installing Azure CLI for Ubuntu 24.04...${NC}"
            
            # Install prerequisites for repository
            echo -e "${BLUE}Step 1: Installing repository prerequisites...${NC}"
            sudo apt-get update
            sudo apt-get install -y ca-certificates curl apt-transport-https lsb-release gnupg
            
            # Add Microsoft GPG key (Ubuntu 24.04 method)
            echo -e "${BLUE}Step 2: Adding Microsoft GPG key...${NC}"
            sudo mkdir -p /etc/apt/keyrings
            curl -sLS https://packages.microsoft.com/keys/microsoft.asc | \
                gpg --dearmor | \
                sudo tee /etc/apt/keyrings/microsoft.gpg > /dev/null
            sudo chmod go+r /etc/apt/keyrings/microsoft.gpg
            
            # Add Azure CLI repository
            echo -e "${BLUE}Step 3: Adding Azure CLI repository...${NC}"
            AZ_DIST=$(lsb_release -cs)
            echo "deb [arch=`dpkg --print-architecture` signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $AZ_DIST main" | \
                sudo tee /etc/apt/sources.list.d/azure-cli.list
            
            # Update and install Azure CLI
            echo -e "${BLUE}Step 4: Installing Azure CLI...${NC}"
            sudo apt-get update
            sudo apt-get install -y azure-cli
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✓ Azure CLI installed successfully${NC}"
                echo -e "${YELLOW}Please run 'az login --tenant <tenant-id>' to authenticate${NC}"
            else
                echo -e "${RED}✗ Azure CLI installation failed${NC}"
                echo -e "${YELLOW}Try manual installation:${NC}"
                echo "  curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash"
                exit 1
            fi
        else
            echo -e "${RED}Azure CLI is required to run this script${NC}"
            exit 1
        fi
    fi
    
    # Check Python packages
    echo ""
    echo -e "${BLUE}Checking Python packages...${NC}"
    
    local python_packages_needed=false
    
    # Check for required Python modules
    python3 -c "import json, datetime, collections, sys" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Required Python standard libraries missing${NC}"
        echo -e "${YELLOW}This is unusual - your Python installation may be incomplete${NC}"
        python_packages_needed=true
    else
        echo -e "${GREEN}✓ Required Python standard libraries present${NC}"
    fi
    
    # Create setup completion marker
    echo ""
    echo -e "${GREEN}✓ Prerequisite check complete${NC}"
    echo ""
}

# Function to create setup script for first-time users
create_setup_script() {
    cat > setup_azure_alerts.sh << 'SETUP_EOF'
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
SETUP_EOF
    
    chmod +x setup_azure_alerts.sh
    echo -e "${GREEN}Created setup_azure_alerts.sh - Run this first if you haven't set up the prerequisites${NC}"
}

# Main setup check
if [[ "$1" == "--setup" ]] || [[ "$1" == "-S" ]]; then
    check_distro
    check_and_install_prerequisites
    exit 0
fi

# Quick check if Azure CLI is available
if ! command -v az &> /dev/null; then
    echo -e "${RED}Azure CLI is not installed!${NC}"
    echo -e "${YELLOW}Run one of the following:${NC}"
    echo -e "  1. ${CYAN}$0 --setup${NC} (guided setup)"
    echo -e "  2. ${CYAN}curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash${NC} (direct install)"
    echo ""
    create_setup_script
    echo -e "${YELLOW}Or run: ${CYAN}./setup_azure_alerts.sh${NC} for complete setup${NC}"
    exit 1
fi

# Check if logged in to Azure and get current tenant
echo -e "${CYAN}Checking Azure login status...${NC}"
if ! az account show &> /dev/null; then
    echo -e "${YELLOW}Not logged in to Azure${NC}"
    echo -e "Please run: ${CYAN}az login${NC} or ${CYAN}az login --tenant <tenant-id>${NC}"
    exit 1
else
    CURRENT_TENANT=$(az account show --query tenantId -o tsv 2>/dev/null)
    CURRENT_SUB_NAME=$(az account show --query name -o tsv 2>/dev/null)
    CURRENT_SUB_ID=$(az account show --query id -o tsv 2>/dev/null)
    echo -e "${GREEN}✓ Logged in to Azure${NC}"
    echo -e "  Current Tenant: ${YELLOW}$CURRENT_TENANT${NC}"
    echo -e "  Current Subscription: ${YELLOW}$CURRENT_SUB_NAME ($CURRENT_SUB_ID)${NC}"
fi

# Configuration
OUTPUT_DIR="azure_alerts_analysis_$(date +%Y%m%d_%H%M%S)"
SUBSCRIPTION=""
TENANT_ID=""
DAYS_BACK=7
RESOURCE_GROUP=""
ALL_SUBSCRIPTIONS=false
SKIP_MAINTENANCE=false
DEBUG_MODE=false

# Function to display usage
show_usage() {
    echo -e "${CYAN}================================================================================================${NC}"
    echo -e "${GREEN}Azure Alerts Analysis Tool${NC}"
    echo -e "${CYAN}================================================================================================${NC}"
    echo ""
    echo -e "${CYAN}Note: Currently logged into tenant ${YELLOW}$CURRENT_TENANT${NC}"
    echo -e "${CYAN}      Analysis will only include subscriptions in this tenant${NC}"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -s, --subscription <id>    Azure subscription ID (must be in current tenant)"
    echo "  -t, --tenant <id>          Azure tenant ID (validates against current login)"
    echo "  -a, --all-subscriptions    Analyze alerts across all subscriptions in current tenant"
    echo "  -d, --days <number>         Number of days to analyze (7, 14, or 30, default: 7)"
    echo "  -r, --resource-group <name> Specific resource group to analyze (optional)"
    echo "  --skip-maintenance          Skip maintenance window checks (faster execution)"
    echo "  --debug                     Debug mode: only process first 3 subscriptions"
    echo "  -h, --help                  Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -d 14                                      # Use current subscription and tenant"
    echo "  $0 -s <subscription-id> -d 30                # Specific subscription in current tenant"
    echo "  $0 -a -d 7                                    # All subscriptions in current tenant"
    echo "  $0 -a --debug -d 7                           # First 3 subscriptions only (debug mode)"
    echo "  $0 -t <tenant-id> -a -d 7                    # Validate tenant then analyze all subscriptions"
    echo "  $0 -r <resource-group> -d 7                  # Filter by resource group"
    echo "  $0 -d 14 --skip-maintenance                  # Skip maintenance checks for faster execution"
    echo ""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--subscription)
            SUBSCRIPTION="$2"
            shift 2
            ;;
        -t|--tenant)
            TENANT_ID="$2"
            shift 2
            ;;
        -a|--all-subscriptions)
            ALL_SUBSCRIPTIONS=true
            shift 1
            ;;
        -d|--days)
            DAYS_BACK="$2"
            shift 2
            ;;
        -r|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
            ;;
        --skip-maintenance)
            SKIP_MAINTENANCE=true
            shift 1
            ;;
        --debug)
            DEBUG_MODE=true
            shift 1
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_usage
            exit 1
            ;;
    esac
done

# Validate days parameter
if [[ ! "$DAYS_BACK" =~ ^(7|14|30)$ ]]; then
    echo -e "${RED}Error: Days must be 7, 14, or 30${NC}"
    exit 1
fi

# Validate conflicting options
if [ "$ALL_SUBSCRIPTIONS" = true ] && [ -n "$SUBSCRIPTION" ]; then
    echo -e "${RED}Error: Cannot specify both --all-subscriptions and --subscription${NC}"
    exit 1
fi

if [ "$DEBUG_MODE" = true ] && [ "$ALL_SUBSCRIPTIONS" != true ]; then
    echo -e "${RED}Error: --debug flag can only be used with --all-subscriptions${NC}"
    exit 1
fi

# Handle tenant validation if specific tenant ID is provided
if [ -n "$TENANT_ID" ]; then
    echo -e "${CYAN}Validating specified tenant: ${YELLOW}$TENANT_ID${NC}"
    if [ "$CURRENT_TENANT" != "$TENANT_ID" ]; then
        echo -e "${YELLOW}Current tenant ($CURRENT_TENANT) doesn't match specified tenant ($TENANT_ID)${NC}"
        echo -e "${CYAN}Please run: ${YELLOW}az login --tenant $TENANT_ID${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Already logged into correct tenant: $TENANT_ID${NC}"
else
    # No specific tenant provided, use current tenant
    TENANT_ID="$CURRENT_TENANT"
    echo -e "${CYAN}Using current tenant: ${YELLOW}$TENANT_ID${NC}"
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo -e "${CYAN}================================================================================================${NC}"
echo -e "${GREEN}Starting Azure Alerts Analysis${NC}"
echo -e "${CYAN}================================================================================================${NC}"
echo -e "Analysis Period: ${YELLOW}$DAYS_BACK days${NC}"
echo -e "Output Directory: ${YELLOW}$OUTPUT_DIR${NC}"

# Function to get all subscriptions in current tenant
get_all_subscriptions() {
    echo -e "${BLUE}Getting all subscriptions in current tenant ($TENANT_ID)...${NC}" >&2
    az account list --query "[?state=='Enabled' && tenantId=='$TENANT_ID'].{id:id,name:name}" -o tsv
}

analyze_subscription_alerts() {
    local output_dir="$1"
    
    # Debug: Verify function is available and directory exists
    echo "DEBUG: analyze_subscription_alerts function called with output_dir: $output_dir" >&2
    
    # Verify output directory exists
    if [ ! -d "$output_dir" ]; then
        echo -e "${RED}Error: Output directory does not exist: $output_dir${NC}"
        return 1
    fi
    
    echo -e "${BLUE}  Working in directory: $output_dir${NC}"
    
    # Get current subscription info
    CURRENT_SUB=$(az account show --query name -o tsv)
    CURRENT_SUB_ID=$(az account show --query id -o tsv)
    echo -e "Current Subscription: ${YELLOW}$CURRENT_SUB ($CURRENT_SUB_ID)${NC}"
    echo ""

    # Calculate date range
END_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
START_DATE=$(date -u -d "$DAYS_BACK days ago" +"%Y-%m-%dT%H:%M:%SZ")

echo -e "${BLUE}Analyzing alerts from $START_DATE to $END_DATE${NC}"
echo ""

#################################################################################
# Section 1: Download Activity Log Alerts
#################################################################################
echo -e "${GREEN}[1/8] Downloading Activity Log Alerts...${NC}"

# Build query based on resource group filter
if [ -n "$RESOURCE_GROUP" ]; then
    QUERY_FILTER="eventTimestamp ge '$START_DATE' and eventTimestamp le '$END_DATE' and resourceGroupName eq '$RESOURCE_GROUP'"
else
    QUERY_FILTER="eventTimestamp ge '$START_DATE' and eventTimestamp le '$END_DATE'"
fi

echo -e "${BLUE}  Querying activity log for alerts...${NC}"
timeout 60 az monitor activity-log list \
    --start-time "$START_DATE" \
    --end-time "$END_DATE" \
    --query "[?category.value=='Alert' || level=='Error' || level=='Warning' || level=='Critical'].{
        timestamp: eventTimestamp,
        level: level,
        category: category.value,
        resourceGroup: resourceGroupName,
        resourceType: resourceType,
        resourceId: resourceId,
        operationName: operationName.value,
        status: status.value,
        description: properties.message,
        correlationId: correlationId
    }" \
    -o json > "$output_dir/activity_alerts.json" || {
    echo -e "${YELLOW}  Warning: Could not retrieve activity log alerts${NC}"
    echo "[]" > "$output_dir/activity_alerts.json"
}

#################################################################################
# Section 2: Download Metric Alerts
#################################################################################
echo -e "${GREEN}[2/8] Downloading Metric Alerts...${NC}"

# Get all metric alert rules
echo -e "${BLUE}  Querying metric alert rules...${NC}"
timeout 45 az monitor metrics alert list \
    --query "[].{
        name: name,
        resourceGroup: resourceGroup,
        enabled: enabled,
        severity: severity,
        description: description,
        targetResourceType: targetResourceType,
        targetResourceRegion: targetResourceRegion,
        criteria: criteria,
        autoMitigate: autoMitigate,
        lastUpdatedTime: lastUpdatedTime
    }" \
    -o json > "$output_dir/metric_alert_rules.json" || {
    echo -e "${YELLOW}  Warning: Could not retrieve metric alert rules${NC}"
    echo "[]" > "$output_dir/metric_alert_rules.json"
}

#################################################################################
# Section 3: Download Alert History
#################################################################################
echo -e "${GREEN}[3/8] Downloading Alert History...${NC}"

# Get alert history from Azure Monitor with timeout - including all alert states
echo -e "${BLUE}  Querying alert management API for all alert states...${NC}"
timeout 60 az rest --method GET \
    --uri "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/providers/Microsoft.AlertsManagement/alerts?api-version=2019-05-05-preview&timeRange=${DAYS_BACK}d&alertState=New,Acknowledged,Closed" \
    --query "value[].{
        alertId: id,
        name: name,
        severity: properties.essentials.severity,
        alertState: properties.essentials.alertState,
        monitorCondition: properties.essentials.monitorCondition,
        targetResource: properties.essentials.targetResource,
        targetResourceType: properties.essentials.targetResourceType,
        targetResourceGroup: properties.essentials.targetResourceGroup,
        startDateTime: properties.essentials.startDateTime,
        lastModifiedDateTime: properties.essentials.lastModifiedDateTime,
        monitorService: properties.essentials.monitorService,
        signalType: properties.essentials.signalType,
        description: properties.essentials.description,
        alertRule: properties.essentials.alertRule
    }" \
    -o json > "$output_dir/alert_history.json" 2>/dev/null || {
    echo -e "${YELLOW}  Warning: Could not retrieve alert history from Management API${NC}"
    echo "[]" > "$output_dir/alert_history.json"
}

#################################################################################
# Section 4: Analyze and Generate Reports
#################################################################################
echo -e "${GREEN}[4/8] Analyzing Alert Data...${NC}"

# Create analysis Python script
cat > "$output_dir/analyze_alerts.py" << 'EOF'
import json
import sys
from datetime import datetime, timedelta
from collections import Counter, defaultdict
import re

def load_json_file(filename):
    try:
        with open(filename, 'r') as f:
            return json.load(f)
    except:
        return []

def analyze_alerts(days_back):
    # Load data
    activity_alerts = load_json_file('activity_alerts.json')
    metric_rules = load_json_file('metric_alert_rules.json')
    alert_history = load_json_file('alert_history.json')
    
    # Initialize analysis containers
    analysis = {
        'total_alerts': len(activity_alerts) + len(alert_history),
        'severity_breakdown': Counter(),
        'alert_state_breakdown': Counter(),
        'alert_state_by_severity': defaultdict(lambda: defaultdict(int)),
        'resource_type_breakdown': Counter(),
        'resource_group_breakdown': Counter(),
        'hourly_distribution': defaultdict(int),
        'daily_distribution': defaultdict(int),
        'top_alerting_resources': Counter(),
        'top_alerts_by_severity': {
            'Sev0': Counter(),
            'Sev1': Counter(), 
            'Sev2': Counter(),
            'Sev3': Counter(),
            'Sev4': Counter()
        },
        'alert_lifecycle_metrics': {
            'new_alerts': 0,
            'acknowledged_alerts': 0,
            'closed_alerts': 0,
            'avg_time_to_acknowledge': 0,
            'avg_time_to_close': 0
        },
        'correlation_patterns': [],
        'tuning_recommendations': [],
        'alert_storms': [],
        'maintenance_windows': [],
        'resource_health_alerts': [],
        'top_alert_rules': Counter(),
        'alert_rule_details': {},
        'alert_name_to_rule_mapping': Counter()
    }
    
    # Analyze activity alerts
    for alert in activity_alerts:
        # Handle severity/level
        level = alert.get('level')
        if level and isinstance(level, str):
            analysis['severity_breakdown'][level] += 1
            
            # Track activity alert rules (often stored differently)
            alert_name = alert.get('operationName') or alert.get('eventName', 'Unknown Activity')
            alert_rule = alert.get('alertRule') or alert.get('operationName', 'Activity Log Alert')
            
            if isinstance(alert_rule, str):
                analysis['top_alert_rules'][alert_rule] += 1
                analysis['alert_name_to_rule_mapping'][f"{alert_name} -> {alert_rule}"] += 1
                
                # Store rule details for activity alerts
                if alert_rule not in analysis['alert_rule_details']:
                    analysis['alert_rule_details'][alert_rule] = {
                        'rule_name': alert_rule,
                        'alert_count': 0,
                        'severities': Counter(),
                        'states': Counter(),
                        'affected_resources': set(),
                        'sample_alerts': []
                    }
                
                rule_details = analysis['alert_rule_details'][alert_rule]
                rule_details['alert_count'] += 1
                rule_details['severities'][level] += 1
                rule_details['states']['Activity'] += 1  # Activity alerts don't have traditional states
                
                resource_id = alert.get('resourceId')
                if resource_id and isinstance(resource_id, str):
                    rule_details['affected_resources'].add(resource_id)
                
                # Store sample activity alert
                if len(rule_details['sample_alerts']) < 3:
                    rule_details['sample_alerts'].append({
                        'alert_id': alert.get('correlationId', 'Unknown'),
                        'name': alert_name,
                        'severity': level,
                        'state': 'Activity',
                        'resource': resource_id,
                        'start_time': alert.get('timestamp', 'Unknown'),
                        'description': alert.get('description', 'Activity log alert')[:100] + '...' if len(str(alert.get('description', ''))) > 100 else alert.get('description', 'Activity log alert')
                    })
        
        # Handle resourceType - could be string or dict
        resource_type = alert.get('resourceType')
        if resource_type:
            if isinstance(resource_type, dict):
                # If it's a dict, try to get the value or localizedValue
                resource_type_str = resource_type.get('value') or resource_type.get('localizedValue') or str(resource_type)
            else:
                resource_type_str = str(resource_type)
            analysis['resource_type_breakdown'][resource_type_str] += 1
        
        # Handle resourceGroup
        resource_group = alert.get('resourceGroup')
        if resource_group and isinstance(resource_group, str):
            analysis['resource_group_breakdown'][resource_group] += 1
        
        # Handle resourceId  
        resource_id = alert.get('resourceId')
        if resource_id and isinstance(resource_id, str):
            analysis['top_alerting_resources'][resource_id] += 1
        
        # Time distribution
        timestamp = alert.get('timestamp')
        if timestamp and isinstance(timestamp, str):
            try:
                dt = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
                hour = dt.hour
                day = dt.strftime('%Y-%m-%d')
                analysis['hourly_distribution'][hour] += 1
                analysis['daily_distribution'][day] += 1
            except:
                pass  # Skip invalid timestamps
    
    # Analyze alert history with enhanced state tracking
    for alert in alert_history:
        # Severity analysis
        severity = alert.get('severity')
        if severity and isinstance(severity, str):
            analysis['severity_breakdown'][severity] += 1
            
            # Track top alerts by severity
            alert_name = alert.get('name', 'Unknown Alert')
            if isinstance(alert_name, str) and severity in analysis['top_alerts_by_severity']:
                analysis['top_alerts_by_severity'][severity][alert_name] += 1
                
            # Track alert rule information
            alert_rule = alert.get('alertRule', 'Unknown Rule')
            if isinstance(alert_rule, str):
                analysis['top_alert_rules'][alert_rule] += 1
                # Map alert name to rule
                analysis['alert_name_to_rule_mapping'][f"{alert_name} -> {alert_rule}"] += 1
                # Store rule details
                if alert_rule not in analysis['alert_rule_details']:
                    analysis['alert_rule_details'][alert_rule] = {
                        'rule_name': alert_rule,
                        'alert_count': 0,
                        'severities': Counter(),
                        'states': Counter(),
                        'affected_resources': set(),
                        'sample_alerts': []
                    }
                
                rule_details = analysis['alert_rule_details'][alert_rule]
                rule_details['alert_count'] += 1
                rule_details['severities'][severity] += 1
                rule_details['states'][alert_state] += 1
                
                if target_resource and isinstance(target_resource, str):
                    rule_details['affected_resources'].add(target_resource)
                
                # Store sample alert for reference (limit to 3 samples per rule)
                if len(rule_details['sample_alerts']) < 3:
                    rule_details['sample_alerts'].append({
                        'alert_id': alert.get('alertId', 'Unknown'),
                        'name': alert_name,
                        'severity': severity,
                        'state': alert_state,
                        'resource': target_resource,
                        'start_time': alert.get('startDateTime', 'Unknown'),
                        'description': alert.get('description', 'No description')[:100] + '...' if len(str(alert.get('description', ''))) > 100 else alert.get('description', 'No description')
                    })
        
        # Alert state analysis
        alert_state = alert.get('alertState')
        if alert_state and isinstance(alert_state, str):
            analysis['alert_state_breakdown'][alert_state] += 1
            
            # Track alert state by severity
            if severity and isinstance(severity, str):
                analysis['alert_state_by_severity'][severity][alert_state] += 1
            
            # Count lifecycle metrics
            if alert_state == 'New':
                analysis['alert_lifecycle_metrics']['new_alerts'] += 1
            elif alert_state == 'Acknowledged':
                analysis['alert_lifecycle_metrics']['acknowledged_alerts'] += 1
            elif alert_state == 'Closed':
                analysis['alert_lifecycle_metrics']['closed_alerts'] += 1
        
        # Resource analysis - handle potential dict values
        target_resource_type = alert.get('targetResourceType')
        if target_resource_type:
            if isinstance(target_resource_type, dict):
                target_resource_type_str = target_resource_type.get('value') or target_resource_type.get('localizedValue') or str(target_resource_type)
            else:
                target_resource_type_str = str(target_resource_type)
            analysis['resource_type_breakdown'][target_resource_type_str] += 1
            
        target_resource_group = alert.get('targetResourceGroup')
        if target_resource_group and isinstance(target_resource_group, str):
            analysis['resource_group_breakdown'][target_resource_group] += 1
            
        target_resource = alert.get('targetResource')
        if target_resource and isinstance(target_resource, str):
            analysis['top_alerting_resources'][target_resource] += 1
            
        # Time distribution for alert history
        start_date_time = alert.get('startDateTime')
        if start_date_time and isinstance(start_date_time, str):
            try:
                dt = datetime.fromisoformat(start_date_time.replace('Z', '+00:00'))
                hour = dt.hour
                day = dt.strftime('%Y-%m-%d')
                analysis['hourly_distribution'][hour] += 1
                analysis['daily_distribution'][day] += 1
            except:
                pass  # Skip invalid timestamps
    
    # Collect detailed ResourceHealth alert analysis
    for alert in activity_alerts + alert_history:
        alert_name = alert.get('name') or alert.get('alertRule', '')
        if isinstance(alert_name, str) and 'ResourceHealthUnhealthyAlert' in alert_name:
            resource_health_detail = {
                'alert_id': alert.get('alertId') or alert.get('id', 'Unknown'),
                'name': alert_name,
                'severity': alert.get('severity') or alert.get('level', 'Unknown'),
                'state': alert.get('alertState') or 'Unknown',
                'resource': alert.get('targetResource') or alert.get('resourceId', 'Unknown'),
                'resource_type': alert.get('targetResourceType') or alert.get('resourceType', 'Unknown'),
                'resource_group': alert.get('targetResourceGroup') or alert.get('resourceGroup', 'Unknown'),
                'start_time': alert.get('startDateTime') or alert.get('timestamp', 'Unknown'),
                'last_modified': alert.get('lastModifiedDateTime', 'Unknown'),
                'description': alert.get('description', 'No description available'),
                'monitor_condition': alert.get('monitorCondition', 'Unknown'),
                'monitor_service': alert.get('monitorService', 'ResourceHealth')
            }
            
            # Handle dict values safely
            for field in ['resource_type', 'severity']:
                if isinstance(resource_health_detail[field], dict):
                    resource_health_detail[field] = resource_health_detail[field].get('value') or resource_health_detail[field].get('localizedValue') or str(resource_health_detail[field])
            
            analysis['resource_health_alerts'].append(resource_health_detail)
    
    # Detect alert storms (>10 alerts in 5 minutes)
    time_windows = defaultdict(list)
    for alert in activity_alerts:
        timestamp = alert.get('timestamp')
        if timestamp and isinstance(timestamp, str):
            try:
                dt = datetime.fromisoformat(timestamp.replace('Z', '+00:00'))
                window = dt.replace(minute=(dt.minute // 5) * 5, second=0, microsecond=0)
                time_windows[window].append(alert)
            except:
                pass  # Skip invalid timestamps
    
    for window, alerts in time_windows.items():
        if len(alerts) > 10:
            # Safely extract resource IDs
            resources = []
            for a in alerts:
                resource_id = a.get('resourceId')
                if resource_id and isinstance(resource_id, str):
                    resources.append(resource_id)
            
            analysis['alert_storms'].append({
                'time': window.isoformat(),
                'count': len(alerts),
                'resources': list(set(resources))[:5]
            })
    
    # Generate tuning recommendations
    # Find non-critical alerts that fire frequently
    low_severity_frequent = []
    for resource, count in analysis['top_alerting_resources'].most_common(20):
        # Check if this resource has mostly low-severity alerts
        low_sev_count = 0
        for a in activity_alerts:
            resource_id = a.get('resourceId')
            level = a.get('level')
            if (isinstance(resource_id, str) and resource_id == resource and 
                isinstance(level, str) and level in ['Warning', 'Informational']):
                low_sev_count += 1
        
        if low_sev_count > count * 0.7 and count > 5:
            low_severity_frequent.append({
                'resource': resource,
                'alert_count': count,
                'recommendation': 'Consider adjusting thresholds or reducing alert sensitivity'
            })
    
    analysis['tuning_recommendations'] = low_severity_frequent
    
    # Detect correlation patterns
    correlation_groups = defaultdict(list)
    for alert in activity_alerts:
        correlation_id = alert.get('correlationId')
        if correlation_id and isinstance(correlation_id, str):
            correlation_groups[correlation_id].append(alert)
    
    for corr_id, alerts in correlation_groups.items():
        if len(alerts) > 2:
            # Safely extract resource IDs
            resources = []
            for a in alerts:
                resource_id = a.get('resourceId')
                if resource_id and isinstance(resource_id, str):
                    resources.append(resource_id)
            
            analysis['correlation_patterns'].append({
                'correlation_id': corr_id,
                'alert_count': len(alerts),
                'resources': list(set(resources))[:5],
                'time_span': 'Multiple related alerts'
            })
    
    return analysis

def generate_report(analysis, days_back):
    report = []
    report.append("=" * 80)
    report.append(f"AZURE ALERTS ANALYSIS REPORT - LAST {days_back} DAYS")
    report.append("=" * 80)
    report.append("")
    
    # Executive Summary
    report.append("EXECUTIVE SUMMARY")
    report.append("-" * 40)
    report.append(f"Total Alerts: {analysis['total_alerts']}")
    report.append(f"Average Alerts/Day: {analysis['total_alerts'] / days_back:.1f}")
    report.append("")
    
    # Severity Breakdown
    report.append("SEVERITY BREAKDOWN")
    report.append("-" * 40)
    for severity, count in analysis['severity_breakdown'].most_common():
        percentage = (count / analysis['total_alerts'] * 100) if analysis['total_alerts'] > 0 else 0
        report.append(f"  {severity}: {count} ({percentage:.1f}%)")
    report.append("")
    
    # Alert State Breakdown
    report.append("ALERT STATE BREAKDOWN")
    report.append("-" * 40)
    for state, count in analysis['alert_state_breakdown'].most_common():
        percentage = (count / analysis['total_alerts'] * 100) if analysis['total_alerts'] > 0 else 0
        report.append(f"  {state}: {count} ({percentage:.1f}%)")
    report.append("")
    
    # Alert Lifecycle Metrics
    report.append("ALERT LIFECYCLE METRICS")
    report.append("-" * 40)
    lifecycle = analysis['alert_lifecycle_metrics']
    report.append(f"  New Alerts: {lifecycle['new_alerts']}")
    report.append(f"  Acknowledged Alerts: {lifecycle['acknowledged_alerts']}")
    report.append(f"  Closed Alerts: {lifecycle['closed_alerts']}")
    if lifecycle['new_alerts'] > 0:
        ack_rate = (lifecycle['acknowledged_alerts'] / lifecycle['new_alerts'] * 100)
        report.append(f"  Acknowledgment Rate: {ack_rate:.1f}%")
    if lifecycle['new_alerts'] > 0:
        close_rate = (lifecycle['closed_alerts'] / lifecycle['new_alerts'] * 100)
        report.append(f"  Resolution Rate: {close_rate:.1f}%")
    report.append("")
    
    # Top Alerts by Severity
    report.append("TOP ALERTS BY SEVERITY")
    report.append("-" * 40)
    for severity in ['Sev0', 'Sev1', 'Sev2', 'Sev3', 'Sev4']:
        if severity in analysis['top_alerts_by_severity'] and analysis['top_alerts_by_severity'][severity]:
            report.append(f"  {severity} Alerts:")
            for alert_name, count in analysis['top_alerts_by_severity'][severity].most_common(5):
                report.append(f"    {alert_name}: {count} occurrences")
    report.append("")
    
    # Top Alerting Resources
    report.append("TOP 10 ALERTING RESOURCES")
    report.append("-" * 40)
    for resource, count in analysis['top_alerting_resources'].most_common(10):
        report.append(f"  {count} alerts: {resource}")
    report.append("")
    
    # Resource Type Distribution
    report.append("ALERTS BY RESOURCE TYPE")
    report.append("-" * 40)
    for res_type, count in analysis['resource_type_breakdown'].most_common(10):
        report.append(f"  {res_type}: {count}")
    report.append("")
    
    # Alert Storms
    if analysis['alert_storms']:
        report.append("DETECTED ALERT STORMS")
        report.append("-" * 40)
        for storm in analysis['alert_storms'][:5]:
            report.append(f"  Time: {storm['time']}")
            report.append(f"    Alert Count: {storm['count']}")
            report.append(f"    Affected Resources: {', '.join(storm['resources'])}")
        report.append("")
    
    # Correlation Patterns
    if analysis['correlation_patterns']:
        report.append("CORRELATED ALERT PATTERNS")
        report.append("-" * 40)
        for pattern in analysis['correlation_patterns'][:5]:
            report.append(f"  Correlation ID: {pattern['correlation_id']}")
            report.append(f"    Related Alerts: {pattern['alert_count']}")
            report.append(f"    Resources: {', '.join(pattern['resources'])}")
        report.append("")
    
    # Tuning Recommendations
    if analysis['tuning_recommendations']:
        report.append("TUNING RECOMMENDATIONS")
        report.append("-" * 40)
        report.append("Resources with high volumes of non-critical alerts:")
        for rec in analysis['tuning_recommendations'][:10]:
            report.append(f"  Resource: {rec['resource']}")
            report.append(f"    Alert Count: {rec['alert_count']}")
            report.append(f"    Recommendation: {rec['recommendation']}")
        report.append("")
    
    # Hourly Distribution
    report.append("HOURLY ALERT DISTRIBUTION")
    report.append("-" * 40)
    for hour in range(24):
        count = analysis['hourly_distribution'].get(hour, 0)
        bar = '#' * min(50, int(count * 50 / max(analysis['hourly_distribution'].values(), default=1)))
        report.append(f"  {hour:02d}:00 [{count:3d}] {bar}")
    report.append("")
    
    # Daily Trend
    report.append("DAILY ALERT TREND")
    report.append("-" * 40)
    sorted_days = sorted(analysis['daily_distribution'].items())
    for day, count in sorted_days[-7:]:
        bar = '#' * min(50, int(count * 50 / max(analysis['daily_distribution'].values(), default=1)))
        report.append(f"  {day} [{count:3d}] {bar}")
    report.append("")
    
    # Recommendations
    report.append("KEY RECOMMENDATIONS")
    report.append("-" * 40)
    
    # Check for alert fatigue
    if analysis['total_alerts'] / days_back > 100:
        report.append("⚠ HIGH ALERT VOLUME DETECTED")
        report.append("  - Review alert thresholds to reduce noise")
        report.append("  - Implement alert suppression rules for known issues")
        report.append("  - Consider aggregating related alerts")
    
    # Check severity distribution
    low_sev_percentage = (analysis['severity_breakdown'].get('Warning', 0) + 
                         analysis['severity_breakdown'].get('Informational', 0)) / max(analysis['total_alerts'], 1) * 100
    if low_sev_percentage > 70:
        report.append("⚠ HIGH PERCENTAGE OF LOW-SEVERITY ALERTS")
        report.append("  - Review if all warning/info alerts need immediate attention")
        report.append("  - Consider routing low-severity alerts to a separate channel")
    
    # Check for recurring patterns
    if len(analysis['correlation_patterns']) > 5:
        report.append("⚠ MULTIPLE CORRELATION PATTERNS DETECTED")
        report.append("  - Investigate root causes of correlated alerts")
        report.append("  - Consider creating composite alerts for related issues")
    
    report.append("")
    report.append("=" * 80)
    
    return '\n'.join(report)

if __name__ == "__main__":
    days_back = int(sys.argv[1]) if len(sys.argv) > 1 else 7
    analysis = analyze_alerts(days_back)
    report = generate_report(analysis, days_back)
    
    # Save report
    with open('analysis_report.txt', 'w') as f:
        f.write(report)
    
    # Save JSON analysis
    with open('analysis_data.json', 'w') as f:
        # Convert Counter objects to dict for JSON serialization
        # Convert Counter objects to regular dicts for JSON serialization
        top_alerts_by_severity_json = {}
        for severity, counter in analysis['top_alerts_by_severity'].items():
            if counter:  # Only include severities that have alerts
                top_alerts_by_severity_json[severity] = dict(counter.most_common(10))
        
        # Convert alert_state_by_severity to regular dict for JSON serialization
        alert_state_by_severity_json = {}
        for severity, states in analysis['alert_state_by_severity'].items():
            alert_state_by_severity_json[severity] = dict(states)
        
        # Convert alert rule details for JSON serialization
        alert_rule_details_json = {}
        for rule_name, details in analysis['alert_rule_details'].items():
            alert_rule_details_json[rule_name] = {
                'rule_name': details['rule_name'],
                'alert_count': details['alert_count'],
                'severities': dict(details['severities']),
                'states': dict(details['states']),
                'affected_resources': list(details['affected_resources'])[:10],  # Limit to top 10 resources
                'affected_resource_count': len(details['affected_resources']),
                'sample_alerts': details['sample_alerts']
            }
        
        analysis_json = {
            'total_alerts': analysis['total_alerts'],
            'severity_breakdown': dict(analysis['severity_breakdown']),
            'alert_state_breakdown': dict(analysis['alert_state_breakdown']),
            'alert_state_by_severity': alert_state_by_severity_json,
            'alert_lifecycle_metrics': analysis['alert_lifecycle_metrics'],
            'resource_type_breakdown': dict(analysis['resource_type_breakdown']),
            'resource_group_breakdown': dict(analysis['resource_group_breakdown']),
            'top_alerting_resources': dict(analysis['top_alerting_resources'].most_common(20)),
            'top_alerts_by_severity': top_alerts_by_severity_json,
            'hourly_distribution': dict(analysis['hourly_distribution']),
            'daily_distribution': dict(analysis['daily_distribution']),
            'correlation_patterns': analysis['correlation_patterns'],
            'tuning_recommendations': analysis['tuning_recommendations'],
            'alert_storms': analysis['alert_storms'],
            'resource_health_alerts': analysis['resource_health_alerts'],
            'top_alert_rules': dict(analysis['top_alert_rules'].most_common(15)),
            'alert_rule_details': alert_rule_details_json,
            'alert_name_to_rule_mapping': dict(analysis['alert_name_to_rule_mapping'].most_common(20))
        }
        json.dump(analysis_json, f, indent=2, default=str)
    
    print(report)
EOF

# Run Python analysis in the correct directory
cd "$output_dir" || {
    echo -e "${RED}Error: Could not change to output directory: $output_dir${NC}"
    return 1
}
python3 analyze_alerts.py $DAYS_BACK
# Go back to the original working directory
cd - > /dev/null

#################################################################################
# Section 5: Get Alert Rules Configuration
#################################################################################
echo -e "${GREEN}[5/8] Analyzing Alert Rules Configuration...${NC}"

# Get all alert rules
echo -e "${BLUE}  Generating alert rules summary...${NC}"
timeout 30 az monitor metrics alert list --query "[].{
    name: name,
    enabled: enabled,
    severity: severity,
    frequency: evaluationFrequency,
    windowSize: windowSize
}" -o table > "$output_dir/alert_rules_summary.txt" || {
    echo -e "${YELLOW}  Warning: Could not generate alert rules summary${NC}"
    echo "No alert rules data available" > "$output_dir/alert_rules_summary.txt"
}

#################################################################################
# Section 6: Check for Scheduled Maintenance
#################################################################################
if [ "$SKIP_MAINTENANCE" = true ]; then
    echo -e "${GREEN}[6/8] Skipping Maintenance Checks (--skip-maintenance flag)${NC}"
    echo "[]" > "$output_dir/maintenance_windows.json"
    echo "[]" > "$output_dir/upcoming_maintenance.json"
else
    echo -e "${GREEN}[6/8] Checking for Scheduled Maintenance...${NC}"

# Query for maintenance configurations with timeout
echo -e "${BLUE}  Querying maintenance configurations...${NC}"
timeout 30 az maintenance configuration list \
    --query "[].{
        name: name,
        maintenanceScope: maintenanceScope,
        startDateTime: window.startDateTime,
        duration: window.duration,
        timeZone: window.timeZone,
        recurEvery: window.recurEvery
    }" \
    -o json > "$output_dir/maintenance_windows.json" 2>/dev/null || {
    echo -e "${YELLOW}  Warning: Could not retrieve maintenance configurations${NC}"
    echo "[]" > "$output_dir/maintenance_windows.json"
}

# Query for upcoming maintenance updates with timeout
echo -e "${BLUE}  Querying upcoming maintenance updates...${NC}"
timeout 30 az rest --method GET \
    --uri "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/providers/Microsoft.Maintenance/updates?api-version=2021-05-01" \
    --query "value[].{
        name: name,
        status: properties.status,
        impactType: properties.impactType,
        impactDurationInSec: properties.impactDurationInSec,
        notBefore: properties.notBefore,
        resourceId: properties.resourceId
    }" \
    -o json > "$output_dir/upcoming_maintenance.json" 2>/dev/null || {
    echo -e "${YELLOW}  Warning: Could not retrieve upcoming maintenance updates${NC}"
    echo "[]" > "$output_dir/upcoming_maintenance.json"
}
fi

#################################################################################
# Section 7: Generate Maintenance Report
#################################################################################
echo -e "${GREEN}[7/8] Generating Maintenance Report...${NC}"

cat > "$output_dir/maintenance_report.py" << 'EOF'
import json
from datetime import datetime, timedelta

def generate_maintenance_report():
    try:
        with open('maintenance_windows.json', 'r') as f:
            maintenance_configs = json.load(f)
    except:
        maintenance_configs = []
    
    try:
        with open('upcoming_maintenance.json', 'r') as f:
            upcoming_maintenance = json.load(f)
    except:
        upcoming_maintenance = []
    
    report = []
    report.append("\n" + "=" * 80)
    report.append("MAINTENANCE SCHEDULE REPORT")
    report.append("=" * 80)
    
    if maintenance_configs:
        report.append("\nCONFIGURED MAINTENANCE WINDOWS")
        report.append("-" * 40)
        for config in maintenance_configs:
            report.append(f"  Name: {config.get('name', 'N/A')}")
            report.append(f"    Scope: {config.get('maintenanceScope', 'N/A')}")
            report.append(f"    Start: {config.get('startDateTime', 'N/A')}")
            report.append(f"    Duration: {config.get('duration', 'N/A')}")
            report.append(f"    Recurrence: {config.get('recurEvery', 'N/A')}")
            report.append("")
    else:
        report.append("\nNo configured maintenance windows found")
    
    if upcoming_maintenance:
        report.append("\nUPCOMING MAINTENANCE EVENTS")
        report.append("-" * 40)
        for event in upcoming_maintenance:
            report.append(f"  Resource: {event.get('resourceId', 'N/A')}")
            report.append(f"    Status: {event.get('status', 'N/A')}")
            report.append(f"    Impact Type: {event.get('impactType', 'N/A')}")
            report.append(f"    Not Before: {event.get('notBefore', 'N/A')}")
            report.append("")
    else:
        report.append("\nNo upcoming maintenance events found")
    
    report.append("=" * 80)
    return '\n'.join(report)

if __name__ == "__main__":
    report = generate_maintenance_report()
    with open('maintenance_report.txt', 'w') as f:
        f.write(report)
    print(report)
EOF

# Run Python maintenance report in the correct directory
cd "$output_dir" || {
    echo -e "${RED}Error: Could not change to output directory: $output_dir${NC}"
    return 1
}
python3 maintenance_report.py
# Go back to the original working directory
cd - > /dev/null

#################################################################################
# Section 8: Generate Final Summary
#################################################################################
echo -e "${GREEN}[8/8] Generating Final Summary...${NC}"

# Create HTML dashboard
cat > "$output_dir/dashboard.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Azure Alerts Analysis Dashboard</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 20px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background-color: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1 {
            color: #0078d4;
            border-bottom: 3px solid #0078d4;
            padding-bottom: 10px;
        }
        h2 {
            color: #323130;
            margin-top: 30px;
            border-bottom: 1px solid #edebe9;
            padding-bottom: 5px;
        }
        .metric-card {
            display: inline-block;
            padding: 15px;
            margin: 10px;
            background-color: #f3f2f1;
            border-radius: 4px;
            min-width: 150px;
            text-align: center;
        }
        .metric-value {
            font-size: 32px;
            font-weight: bold;
            color: #0078d4;
        }
        .metric-label {
            font-size: 14px;
            color: #605e5c;
            margin-top: 5px;
        }
        .severity-critical {
            color: #d13438;
        }
        .severity-error {
            color: #e81123;
        }
        .severity-warning {
            color: #ff8c00;
        }
        .severity-info {
            color: #0078d4;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 15px;
        }
        th {
            background-color: #0078d4;
            color: white;
            padding: 10px;
            text-align: left;
        }
        td {
            padding: 8px;
            border-bottom: 1px solid #edebe9;
        }
        tr:hover {
            background-color: #f3f2f1;
        }
        .recommendation {
            background-color: #fff4ce;
            border-left: 4px solid #ffb900;
            padding: 10px;
            margin: 10px 0;
        }
        .alert-storm {
            background-color: #fde7e9;
            border-left: 4px solid #d13438;
            padding: 10px;
            margin: 10px 0;
        }
        pre {
            background-color: #f3f2f1;
            padding: 10px;
            border-radius: 4px;
            overflow-x: auto;
        }
    </style>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head>
<body>
    <div class="container">
        <h1>Azure Alerts Analysis Dashboard</h1>
        <p id="timestamp"></p>
        
        <div id="metrics"></div>
        <div id="charts"></div>
        <div id="tables"></div>
        <div id="recommendations"></div>
    </div>
    
    <script>
        // Load analysis data
        fetch('analysis_data.json')
            .then(response => response.json())
            .then(data => {
                document.getElementById('timestamp').innerHTML = 
                    'Generated: ' + new Date().toLocaleString();
                
                // Display metrics
                let metricsHtml = `
                    <div class="metric-card">
                        <div class="metric-value">${data.total_alerts}</div>
                        <div class="metric-label">Total Alerts</div>
                    </div>
                `;
                
                // Add alert state metrics if available
                if (data.alert_lifecycle_metrics) {
                    metricsHtml += `
                        <div class="metric-card">
                            <div class="metric-value">${data.alert_lifecycle_metrics.new_alerts}</div>
                            <div class="metric-label">New Alerts</div>
                        </div>
                        <div class="metric-card">
                            <div class="metric-value">${data.alert_lifecycle_metrics.acknowledged_alerts}</div>
                            <div class="metric-label">Acknowledged</div>
                        </div>
                        <div class="metric-card">
                            <div class="metric-value">${data.alert_lifecycle_metrics.closed_alerts}</div>
                            <div class="metric-label">Closed/Resolved</div>
                        </div>
                    `;
                }
                
                document.getElementById('metrics').innerHTML = metricsHtml;
                
                // Display severity breakdown
                let chartsHtml = '<h2>Alert Severity Distribution</h2>';
                if (data.severity_breakdown) {
                    chartsHtml += '<table><tr><th>Severity</th><th>Count</th><th>Percentage</th></tr>';
                    const total = data.total_alerts;
                    Object.entries(data.severity_breakdown).forEach(([severity, count]) => {
                        const percentage = total > 0 ? (count / total * 100).toFixed(1) : 0;
                        const severityClass = getSeverityClass(severity);
                        chartsHtml += `<tr><td class="${severityClass}">${severity}</td><td>${count}</td><td>${percentage}%</td></tr>`;
                    });
                    chartsHtml += '</table>';
                }
                
                // Display alert state breakdown with severity details
                if (data.alert_state_breakdown) {
                    chartsHtml += '<h2>Alert State Distribution</h2>';
                    chartsHtml += '<table><tr><th>State</th><th>Count</th><th>Percentage</th><th>Severity Breakdown</th></tr>';
                    const total = data.total_alerts;
                    Object.entries(data.alert_state_breakdown).forEach(([state, count]) => {
                        const percentage = total > 0 ? (count / total * 100).toFixed(1) : 0;
                        
                        // Build severity breakdown for this state
                        let severityDetails = '';
                        if (data.alert_state_by_severity) {
                            const severities = [];
                            Object.entries(data.alert_state_by_severity).forEach(([severity, states]) => {
                                if (states[state] && states[state] > 0) {
                                    const severityClass = getSeverityClass(severity);
                                    severities.push(`<span class="${severityClass}">${severity}: ${states[state]}</span>`);
                                }
                            });
                            severityDetails = severities.length > 0 ? severities.join('<br>') : 'None';
                        }
                        
                        chartsHtml += `<tr><td><strong>${state}</strong></td><td>${count}</td><td>${percentage}%</td><td>${severityDetails}</td></tr>`;
                    });
                    chartsHtml += '</table>';
                }
                
                document.getElementById('charts').innerHTML = chartsHtml;
                
                // Display top alerts by severity
                let tablesHtml = '<h2>Top Alerts by Severity</h2>';
                if (data.top_alerts_by_severity) {
                    ['Sev0', 'Sev1', 'Sev2', 'Sev3', 'Sev4'].forEach(severity => {
                        if (data.top_alerts_by_severity[severity] && Object.keys(data.top_alerts_by_severity[severity]).length > 0) {
                            const severityClass = getSeverityClass(severity);
                            tablesHtml += `<h3 class="${severityClass}">${severity} Alerts</h3>`;
                            tablesHtml += '<table><tr><th>Alert Name</th><th>Occurrences</th></tr>';
                            Object.entries(data.top_alerts_by_severity[severity])
                                .sort(([,a], [,b]) => b - a)
                                .slice(0, 10)
                                .forEach(([alertName, count]) => {
                                    tablesHtml += `<tr><td>${alertName}</td><td>${count}</td></tr>`;
                                });
                            tablesHtml += '</table>';
                        }
                    });
                }
                
                // Display top alerting resources
                if (data.top_alerting_resources) {
                    tablesHtml += '<h2>Top Alerting Resources</h2>';
                    tablesHtml += '<table><tr><th>AffectedResource</th><th>Alert Count</th></tr>';
                    Object.entries(data.top_alerting_resources)
                        .sort(([,a], [,b]) => b - a)
                        .slice(0, 10)
                        .forEach(([resource, count]) => {
                            // Truncate long resource names
                            const displayName = resource.length > 80 ? resource.substring(0, 77) + '...' : resource;
                            tablesHtml += `<tr><td title="${resource}">${displayName}</td><td>${count}</td></tr>`;
                        });
                    tablesHtml += '</table>';
                }
                
                // Display top alert rules analysis
                if (data.top_alert_rules && Object.keys(data.top_alert_rules).length > 0) {
                    tablesHtml += '<h2>🔧 Top Alert Rules Analysis</h2>';
                    tablesHtml += '<table><tr><th>Alert Rule</th><th>Triggered Count</th><th>Severity Distribution</th><th>Affected Resources</th><th>Actions</th></tr>';
                    
                    // Sort by alert count descending
                    const sortedRules = Object.entries(data.top_alert_rules).sort(([,a], [,b]) => b - a);
                    
                    sortedRules.slice(0, 10).forEach(([ruleName, count]) => {
                        const ruleDetails = data.alert_rule_details?.[ruleName];
                        
                        // Build severity distribution
                        let severityBreakdown = 'Unknown';
                        if (ruleDetails?.severities) {
                            const severities = [];
                            Object.entries(ruleDetails.severities).forEach(([severity, count]) => {
                                const severityClass = getSeverityClass(severity);
                                severities.push(`<span class="${severityClass}">${severity}: ${count}</span>`);
                            });
                            severityBreakdown = severities.join('<br>');
                        }
                        
                        // Build affected resources info
                        let resourceInfo = 'Unknown';
                        if (ruleDetails?.affected_resource_count) {
                            resourceInfo = `${ruleDetails.affected_resource_count} resources`;
                            if (ruleDetails.affected_resource_count > 5) {
                                resourceInfo += ` <span style="color: #d13438;">(High Impact)</span>`;
                            }
                        }
                        
                        // Action buttons
                        const actions = `
                            <button onclick="showRuleDetails('${ruleName.replace(/'/g, '\\')}')" 
                                    style="background-color: #0078d4; color: white; border: none; padding: 4px 8px; border-radius: 2px; cursor: pointer; margin: 1px;">
                                Details
                            </button>
                            <button onclick="showTuningTips('${ruleName.replace(/'/g, '\\')}')" 
                                    style="background-color: #107c10; color: white; border: none; padding: 4px 8px; border-radius: 2px; cursor: pointer; margin: 1px;">
                                Tune
                            </button>
                        `;
                        
                        const displayName = ruleName.length > 60 ? ruleName.substring(0, 57) + '...' : ruleName;
                        tablesHtml += `<tr>
                            <td title="${ruleName}">${displayName}</td>
                            <td><strong>${count}</strong></td>
                            <td>${severityBreakdown}</td>
                            <td>${resourceInfo}</td>
                            <td>${actions}</td>
                        </tr>`;
                    });
                    
                    tablesHtml += '</table>';
                    
                    // Add rule details modal container
                    tablesHtml += `
                        <div id="ruleDetailsModal" style="display: none; position: fixed; top: 50%; left: 50%; transform: translate(-50%, -50%); 
                             background: white; border: 2px solid #0078d4; border-radius: 8px; padding: 20px; max-width: 80%; max-height: 80%; 
                             overflow-y: auto; z-index: 1000; box-shadow: 0 4px 20px rgba(0,0,0,0.3);">
                            <div id="ruleDetailsContent"></div>
                            <button onclick="document.getElementById('ruleDetailsModal').style.display='none'" 
                                    style="background-color: #d13438; color: white; border: none; padding: 8px 16px; border-radius: 4px; cursor: pointer; margin-top: 10px;">
                                Close
                            </button>
                        </div>
                        <div id="modalOverlay" onclick="document.getElementById('ruleDetailsModal').style.display='none'" 
                             style="display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.5); z-index: 999;"></div>
                    `;
                }
                
                // Add ResourceHealth dashboard link if available
                if (data.resource_health_alerts && data.resource_health_alerts.length > 0) {
                    tablesHtml += '<div style="background-color: #e7f3ff; border-left: 4px solid #0078d4; padding: 15px; margin: 20px 0;">';
                    tablesHtml += '<h3>🏥 ResourceHealth Alerts Detected</h3>';
                    tablesHtml += `<p>Found ${data.resource_health_alerts.length} ResourceHealth unhealthy alerts that may be causing noise.</p>`;
                    tablesHtml += '<a href="resourcehealth_dashboard.html" style="display: inline-block; background-color: #d13438; color: white; padding: 10px 20px; text-decoration: none; border-radius: 4px;">View Detailed ResourceHealth Analysis →</a>';
                    tablesHtml += '</div>';
                }
                
                document.getElementById('tables').innerHTML = tablesHtml;
                
                // Display recommendations and storms
                let recommendationsHtml = '';
                if (data.alert_storms && data.alert_storms.length > 0) {
                    recommendationsHtml += '<h2>Detected Alert Storms</h2>';
                    data.alert_storms.forEach(storm => {
                        recommendationsHtml += `
                            <div class="alert-storm">
                                <strong>Alert Storm:</strong> ${storm.count} alerts at ${storm.time}<br>
                                <strong>Affected Resources:</strong> ${storm.resources.join(', ')}
                            </div>
                        `;
                    });
                }
                
                if (data.tuning_recommendations && data.tuning_recommendations.length > 0) {
                    recommendationsHtml += '<h2>Tuning Recommendations</h2>';
                    data.tuning_recommendations.forEach(rec => {
                        recommendationsHtml += `
                            <div class="recommendation">
                                <strong>Resource:</strong> ${rec.resource}<br>
                                <strong>Alert Count:</strong> ${rec.alert_count}<br>
                                <strong>Recommendation:</strong> ${rec.recommendation}
                            </div>
                        `;
                    });
                }
                
                document.getElementById('recommendations').innerHTML = recommendationsHtml;
                
                // JavaScript functions for alert rule analysis
                window.showRuleDetails = function(ruleName) {
                    const ruleDetails = data.alert_rule_details?.[ruleName];
                    if (!ruleDetails) {
                        alert('No details available for this rule');
                        return;
                    }
                    
                    let detailsHtml = `
                        <h2>🔧 Alert Rule Details</h2>
                        <h3>${ruleName}</h3>
                        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin: 20px 0;">
                            <div>
                                <h4>📊 Statistics</h4>
                                <ul>
                                    <li><strong>Total Alerts:</strong> ${ruleDetails.alert_count}</li>
                                    <li><strong>Affected Resources:</strong> ${ruleDetails.affected_resource_count}</li>
                                </ul>
                                
                                <h4>⚠️ Severity Breakdown</h4>
                                <ul>`;
                    
                    Object.entries(ruleDetails.severities || {}).forEach(([severity, count]) => {
                        const severityClass = getSeverityClass(severity);
                        detailsHtml += `<li><span class="${severityClass}">${severity}: ${count}</span></li>`;
                    });
                    
                    detailsHtml += `</ul>
                                
                                <h4>🔄 Alert States</h4>
                                <ul>`;
                    
                    Object.entries(ruleDetails.states || {}).forEach(([state, count]) => {
                        detailsHtml += `<li><strong>${state}:</strong> ${count}</li>`;
                    });
                    
                    detailsHtml += `</ul>
                            </div>
                            <div>
                                <h4>🎯 Sample Affected Resources</h4>
                                <ul>`;
                    
                    (ruleDetails.affected_resources || []).slice(0, 5).forEach(resource => {
                        const shortResource = resource.length > 80 ? resource.substring(0, 77) + '...' : resource;
                        detailsHtml += `<li title="${resource}">${shortResource}</li>`;
                    });
                    
                    detailsHtml += `</ul>
                                
                                <h4>📋 Sample Alerts</h4>`;
                    
                    (ruleDetails.sample_alerts || []).forEach(alert => {
                        const severityClass = getSeverityClass(alert.severity);
                        detailsHtml += `
                            <div style="border: 1px solid #edebe9; padding: 8px; margin: 5px 0; border-radius: 4px;">
                                <div><strong>Alert:</strong> ${alert.name}</div>
                                <div><strong>Severity:</strong> <span class="${severityClass}">${alert.severity}</span></div>
                                <div><strong>State:</strong> ${alert.state}</div>
                                <div><strong>Time:</strong> ${alert.start_time}</div>
                                <div><strong>Description:</strong> ${alert.description}</div>
                            </div>`;
                    });
                    
                    detailsHtml += '</div></div>';
                    
                    document.getElementById('ruleDetailsContent').innerHTML = detailsHtml;
                    document.getElementById('ruleDetailsModal').style.display = 'block';
                    document.getElementById('modalOverlay').style.display = 'block';
                };
                
                window.showTuningTips = function(ruleName) {
                    const ruleDetails = data.alert_rule_details?.[ruleName];
                    if (!ruleDetails) {
                        alert('No tuning tips available for this rule');
                        return;
                    }
                    
                    let tuningHtml = `
                        <h2>🔧 Alert Rule Tuning Recommendations</h2>
                        <h3>${ruleName}</h3>
                        <div style="margin: 20px 0;">`;
                    
                    // Generate specific tuning recommendations
                    const totalAlerts = ruleDetails.alert_count;
                    const severityBreakdown = ruleDetails.severities || {};
                    const stateBreakdown = ruleDetails.states || {};
                    
                    tuningHtml += '<h4>🎯 Specific Recommendations:</h4><ul>';
                    
                    // Check for noise patterns
                    const lowSeverityCount = (severityBreakdown['Sev3'] || 0) + (severityBreakdown['Sev4'] || 0) + (severityBreakdown['Informational'] || 0);
                    if (lowSeverityCount > totalAlerts * 0.7) {
                        tuningHtml += '<li><strong>Noise Reduction:</strong> This rule generates mostly low-severity alerts. Consider raising the threshold or changing severity levels.</li>';
                    }
                    
                    if (totalAlerts > 50) {
                        tuningHtml += '<li><strong>High Volume:</strong> This rule is very active. Consider adding suppression logic or increasing evaluation frequency.</li>';
                    }
                    
                    if (ruleDetails.affected_resource_count > 20) {
                        tuningHtml += '<li><strong>Wide Impact:</strong> This rule affects many resources. Consider resource-specific thresholds or scoping.</li>';
                    }
                    
                    const newAlerts = stateBreakdown['New'] || 0;
                    if (newAlerts > totalAlerts * 0.8) {
                        tuningHtml += '<li><strong>Low Acknowledgment:</strong> Most alerts remain unacknowledged. Review if this rule provides actionable insights.</li>';
                    }
                    
                    // Add general tuning tips
                    tuningHtml += '</ul><h4>💡 General Tuning Tips:</h4><ul>';
                    tuningHtml += '<li>Review alert threshold values and evaluation frequency</li>';
                    tuningHtml += '<li>Consider implementing time-based suppression for known maintenance windows</li>';
                    tuningHtml += '<li>Add resource grouping or scoping to reduce noise</li>';
                    tuningHtml += '<li>Evaluate if the alert provides actionable information for operations</li>';
                    tuningHtml += '<li>Consider consolidating with related alerts to reduce notification fatigue</li>';
                    tuningHtml += '</ul></div>';
                    
                    document.getElementById('ruleDetailsContent').innerHTML = tuningHtml;
                    document.getElementById('ruleDetailsModal').style.display = 'block';
                    document.getElementById('modalOverlay').style.display = 'block';
                };
                
                // Helper function to get severity CSS class
                function getSeverityClass(severity) {
                    const severityMap = {
                        'Sev0': 'severity-critical',
                        'Sev1': 'severity-error', 
                        'Sev2': 'severity-warning',
                        'Sev3': 'severity-info',
                        'Sev4': 'severity-info',
                        'Critical': 'severity-critical',
                        'Error': 'severity-error',
                        'Warning': 'severity-warning',
                        'Informational': 'severity-info'
                    };
                    return severityMap[severity] || '';
                }
            })
            .catch(error => console.error('Error loading data:', error));
    </script>
</body>
</html>
EOF

# Generate ResourceHealth detailed dashboard if we have ResourceHealth alerts
cd "$output_dir" || { echo -e "${RED}Error: Could not change to output directory${NC}"; return 1; }

python3 -c "
import json

# Load analysis data
try:
    with open('analysis_data.json', 'r') as f:
        data = json.load(f)
except:
    data = {'resource_health_alerts': []}

resource_health_alerts = data.get('resource_health_alerts', [])

if resource_health_alerts:
    print(f'Generating ResourceHealth detailed dashboard with {len(resource_health_alerts)} alerts...')
    
    # Create detailed ResourceHealth dashboard
    dashboard_html = '''<!DOCTYPE html>
<html>
<head>
    <title>ResourceHealth Unhealthy Alerts - Detailed Analysis</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 20px;
            background-color: #f5f5f5;
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
            background-color: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1 {
            color: #d13438;
            border-bottom: 3px solid #d13438;
            padding-bottom: 10px;
        }
        h2 {
            color: #323130;
            margin-top: 30px;
            border-bottom: 1px solid #edebe9;
            padding-bottom: 5px;
        }
        .summary-cards {
            display: flex;
            flex-wrap: wrap;
            gap: 15px;
            margin-bottom: 30px;
        }
        .summary-card {
            background: linear-gradient(135deg, #0078d4, #005a9e);
            color: white;
            padding: 20px;
            border-radius: 8px;
            min-width: 200px;
            flex: 1;
        }
        .summary-card h3 {
            margin: 0 0 10px 0;
            color: white;
        }
        .summary-card .value {
            font-size: 28px;
            font-weight: bold;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 15px;
        }
        th {
            background-color: #d13438;
            color: white;
            padding: 12px;
            text-align: left;
            font-weight: bold;
        }
        td {
            padding: 10px;
            border-bottom: 1px solid #edebe9;
            vertical-align: top;
        }
        tr:hover {
            background-color: #fff4ce;
        }
        .severity-critical { color: #d13438; font-weight: bold; }
        .severity-error { color: #e81123; font-weight: bold; }
        .severity-warning { color: #ff8c00; font-weight: bold; }
        .severity-info { color: #0078d4; font-weight: bold; }
        .state-new { background-color: #fde7e9; color: #d13438; padding: 4px 8px; border-radius: 4px; }
        .state-acknowledged { background-color: #fff4ce; color: #8a6914; padding: 4px 8px; border-radius: 4px; }
        .state-closed { background-color: #dff6dd; color: #107c10; padding: 4px 8px; border-radius: 4px; }
        .resource-truncated {
            max-width: 300px;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        .back-link {
            display: inline-block;
            background-color: #0078d4;
            color: white;
            padding: 10px 20px;
            text-decoration: none;
            border-radius: 4px;
            margin-bottom: 20px;
        }
        .back-link:hover {
            background-color: #005a9e;
        }
        .filter-container {
            background-color: #f8f9fa;
            padding: 15px;
            border-radius: 4px;
            margin-bottom: 20px;
        }
        .filter-button {
            background-color: #6c757d;
            color: white;
            border: none;
            padding: 8px 16px;
            margin: 2px;
            border-radius: 4px;
            cursor: pointer;
        }
        .filter-button.active {
            background-color: #0078d4;
        }
        .alert-description {
            max-width: 400px;
            font-style: italic;
            color: #6c757d;
        }
        .insights-box {
            background-color: #e7f3ff;
            border-left: 4px solid #0078d4;
            padding: 15px;
            margin: 20px 0;
        }
    </style>
    <script>
        function filterAlerts(filterType) {
            const rows = document.querySelectorAll('#alertsTable tbody tr');
            const buttons = document.querySelectorAll('.filter-button');
            
            // Update button states
            buttons.forEach(btn => btn.classList.remove('active'));
            event.target.classList.add('active');
            
            rows.forEach(row => {
                const severity = row.children[2].textContent.trim();
                const state = row.children[3].textContent.trim();
                
                switch(filterType) {
                    case 'all':
                        row.style.display = '';
                        break;
                    case 'critical':
                        row.style.display = severity.includes('Sev0') || severity.includes('Critical') ? '' : 'none';
                        break;
                    case 'new':
                        row.style.display = state.includes('New') ? '' : 'none';
                        break;
                    case 'frequent':
                        // Show resources that appear multiple times
                        const resource = row.children[4].textContent;
                        const resourceCount = Array.from(rows).filter(r => r.children[4].textContent === resource).length;
                        row.style.display = resourceCount > 1 ? '' : 'none';
                        break;
                }
            });
        }
    </script>
</head>
<body>
    <div class=\"container\">
        <a href=\"dashboard.html\" class=\"back-link\">← Back to Main Dashboard</a>
        
        <h1>🏥 ResourceHealth Unhealthy Alerts - Detailed Analysis</h1>
        <p><strong>Generated:</strong> ''' + str(json.dumps(resource_health_alerts[0].get('start_time', 'Unknown'))[:10] if resource_health_alerts else 'Unknown') + '''</p>
        
        <div class=\"insights-box\">
            <h3>💡 Analysis Insights</h3>
            <ul>
                <li><strong>Total ResourceHealth Alerts:</strong> ''' + str(len(resource_health_alerts)) + '''</li>
                <li><strong>Purpose:</strong> These alerts indicate when Azure resources are experiencing health issues</li>
                <li><strong>Recommendation:</strong> Focus on Critical/Sev0 and frequent alerts for immediate attention</li>
                <li><strong>Tuning Tip:</strong> Resources with repeated low-severity alerts may need threshold adjustments</li>
            </ul>
        </div>
'''
    
    # Calculate summary statistics
    severities = {}
    states = {}
    resources = {}
    resource_types = {}
    
    for alert in resource_health_alerts:
        # Count severities
        sev = alert.get('severity', 'Unknown')
        severities[sev] = severities.get(sev, 0) + 1
        
        # Count states
        state = alert.get('state', 'Unknown')
        states[state] = states.get(state, 0) + 1
        
        # Count resources
        resource = alert.get('resource', 'Unknown')
        resources[resource] = resources.get(resource, 0) + 1
        
        # Count resource types
        res_type = str(alert.get('resource_type', 'Unknown'))
        resource_types[res_type] = resource_types.get(res_type, 0) + 1
    
    # Add summary cards
    dashboard_html += '''
        <div class=\"summary-cards\">
            <div class=\"summary-card\">
                <h3>Total Alerts</h3>
                <div class=\"value\">''' + str(len(resource_health_alerts)) + '''</div>
            </div>
            <div class=\"summary-card\">
                <h3>Affected Resources</h3>
                <div class=\"value\">''' + str(len(resources)) + '''</div>
            </div>
            <div class=\"summary-card\">
                <h3>Resource Types</h3>
                <div class=\"value\">''' + str(len(resource_types)) + '''</div>
            </div>
            <div class=\"summary-card\">
                <h3>New Alerts</h3>
                <div class=\"value\">''' + str(states.get('New', 0)) + '''</div>
            </div>
        </div>
        
        <div class=\"filter-container\">
            <strong>Quick Filters:</strong>
            <button class=\"filter-button active\" onclick=\"filterAlerts('all')\">All Alerts</button>
            <button class=\"filter-button\" onclick=\"filterAlerts('critical')\">Critical Only</button>
            <button class=\"filter-button\" onclick=\"filterAlerts('new')\">New Alerts</button>
            <button class=\"filter-button\" onclick=\"filterAlerts('frequent')\">Frequent Resources</button>
        </div>
'''
    
    # Add detailed alerts table
    dashboard_html += '''
        <h2>🔍 Detailed ResourceHealth Alerts</h2>
        <table id=\"alertsTable\">
            <thead>
                <tr>
                    <th>Alert ID</th>
                    <th>Alert Name</th>
                    <th>Severity</th>
                    <th>State</th>
                    <th>AffectedResource</th>
                    <th>Resource Type</th>
                    <th>Resource Group</th>
                    <th>Start Time</th>
                    <th>Description</th>
                </tr>
            </thead>
            <tbody>'''
    
    # Sort alerts by severity and start time
    severity_order = {'Sev0': 0, 'Critical': 0, 'Sev1': 1, 'Error': 1, 'Sev2': 2, 'Warning': 2, 'Sev3': 3, 'Sev4': 4, 'Informational': 4}
    sorted_alerts = sorted(resource_health_alerts, key=lambda x: (severity_order.get(x.get('severity', 'Unknown'), 5), x.get('start_time', '')), reverse=False)
    
    for alert in sorted_alerts:
        # Get severity CSS class
        sev = alert.get('severity', 'Unknown')
        sev_class = 'severity-critical' if sev in ['Sev0', 'Critical'] else 'severity-error' if sev in ['Sev1', 'Error'] else 'severity-warning' if sev in ['Sev2', 'Warning'] else 'severity-info'
        
        # Get state CSS class
        state = alert.get('state', 'Unknown')
        state_class = f'state-{state.lower()}' if state.lower() in ['new', 'acknowledged', 'closed'] else ''
        
        # Truncate long resource names
        resource = alert.get('resource', 'Unknown')
        resource_display = resource if len(resource) <= 60 else resource[:57] + '...'
        
        # Format start time
        start_time = alert.get('start_time', 'Unknown')
        if start_time != 'Unknown' and 'T' in start_time:
            start_time = start_time.replace('T', ' ').split('.')[0]
        
        # Truncate description
        description = alert.get('description', 'No description')
        desc_display = description if len(description) <= 80 else description[:77] + '...'
        
        dashboard_html += f'''
                <tr>
                    <td>{alert.get('alert_id', 'Unknown')[:20]}</td>
                    <td>{alert.get('name', 'Unknown')}</td>
                    <td><span class=\"{sev_class}\">{sev}</span></td>
                    <td><span class=\"{state_class}\">{state}</span></td>
                    <td class=\"resource-truncated\" title=\"{resource}\">{resource_display}</td>
                    <td>{alert.get('resource_type', 'Unknown')}</td>
                    <td>{alert.get('resource_group', 'Unknown')}</td>
                    <td>{start_time}</td>
                    <td class=\"alert-description\" title=\"{description}\">{desc_display}</td>
                </tr>'''
    
    dashboard_html += '''
            </tbody>
        </table>
        
        <h2>📊 Summary Analysis</h2>
        <div style=\"display: flex; gap: 30px; flex-wrap: wrap;\">
            <div style=\"flex: 1; min-width: 300px;\">
                <h3>Severity Breakdown</h3>
                <table>
                    <tr><th>Severity</th><th>Count</th><th>%</th></tr>'''
    
    for sev, count in sorted(severities.items(), key=lambda x: severity_order.get(x[0], 5)):
        percentage = (count / len(resource_health_alerts) * 100) if resource_health_alerts else 0
        sev_class = 'severity-critical' if sev in ['Sev0', 'Critical'] else 'severity-error' if sev in ['Sev1', 'Error'] else 'severity-warning' if sev in ['Sev2', 'Warning'] else 'severity-info'
        dashboard_html += f'<tr><td class=\"{sev_class}\">{sev}</td><td>{count}</td><td>{percentage:.1f}%</td></tr>'
    
    dashboard_html += '''
                </table>
            </div>
            <div style=\"flex: 1; min-width: 300px;\">
                <h3>Alert States</h3>
                <table>
                    <tr><th>State</th><th>Count</th><th>%</th></tr>'''
    
    for state, count in states.items():
        percentage = (count / len(resource_health_alerts) * 100) if resource_health_alerts else 0
        state_class = f'state-{state.lower()}' if state.lower() in ['new', 'acknowledged', 'closed'] else ''
        dashboard_html += f'<tr><td><span class=\"{state_class}\">{state}</span></td><td>{count}</td><td>{percentage:.1f}%</td></tr>'
    
    dashboard_html += '''
                </table>
            </div>
        </div>
        
        <h2>🎯 Top Affected Resources</h2>
        <table>
            <tr><th>AffectedResource</th><th>Alert Count</th><th>Resource Type</th></tr>'''
    
    # Show top 15 most affected resources
    for resource, count in sorted(resources.items(), key=lambda x: x[1], reverse=True)[:15]:
        # Find resource type for this resource
        res_type = 'Unknown'
        for alert in resource_health_alerts:
            if alert.get('resource') == resource:
                res_type = str(alert.get('resource_type', 'Unknown'))
                break
        
        resource_display = resource if len(resource) <= 80 else resource[:77] + '...'
        dashboard_html += f'<tr><td title=\"{resource}\">{resource_display}</td><td>{count}</td><td>{res_type}</td></tr>'
    
    dashboard_html += '''
        </table>
        
        <div class=\"insights-box\" style=\"margin-top: 30px;\">
            <h3>🔧 Tuning Recommendations</h3>
            <ul>'''
    
    # Generate specific recommendations
    critical_count = severities.get('Sev0', 0) + severities.get('Critical', 0)
    new_count = states.get('New', 0)
    frequent_resources = [r for r, c in resources.items() if c > 2]
    
    if critical_count > 0:
        dashboard_html += f'<li><strong>High Priority:</strong> {critical_count} critical ResourceHealth alerts need immediate attention</li>'
    
    if new_count > len(resource_health_alerts) * 0.7:
        dashboard_html += f'<li><strong>Alert Fatigue Risk:</strong> {new_count} unacknowledged alerts - consider bulk acknowledgment for non-critical issues</li>'
    
    if frequent_resources:
        dashboard_html += f'<li><strong>Frequent Alerters:</strong> {len(frequent_resources)} resources have multiple alerts - investigate for chronic issues</li>'
    
    low_sev_count = severities.get('Sev3', 0) + severities.get('Sev4', 0) + severities.get('Informational', 0)
    if low_sev_count > len(resource_health_alerts) * 0.5:
        dashboard_html += f'<li><strong>Noise Reduction:</strong> {low_sev_count} low-severity alerts - consider adjusting thresholds</li>'
    
    dashboard_html += '''
            </ul>
        </div>
    </div>
</body>
</html>'''
    
    # Write the dashboard
    with open('resourcehealth_dashboard.html', 'w') as f:
        f.write(dashboard_html)
    
    print('ResourceHealth detailed dashboard created: resourcehealth_dashboard.html')
else:
    print('No ResourceHealth alerts found - skipping detailed dashboard creation.')
"

cd - > /dev/null

#################################################################################
# Display Final Summary
#################################################################################
echo ""
echo -e "${CYAN}================================================================================================${NC}"
echo -e "${GREEN}ANALYSIS COMPLETE${NC}"
echo -e "${CYAN}================================================================================================${NC}"
echo ""
echo -e "${YELLOW}Output Files Generated:${NC}"
echo -e "  📊 ${BLUE}$output_dir/analysis_report.txt${NC} - Main analysis report"
echo -e "  📈 ${BLUE}$output_dir/analysis_data.json${NC} - Detailed JSON data"
echo -e "  🔧 ${BLUE}$output_dir/maintenance_report.txt${NC} - Maintenance schedule"
echo -e "  📋 ${BLUE}$output_dir/alert_rules_summary.txt${NC} - Alert rules configuration"
echo -e "  🌐 ${BLUE}$output_dir/dashboard.html${NC} - Interactive HTML dashboard"
echo -e "  🏥 ${BLUE}$output_dir/resourcehealth_dashboard.html${NC} - ResourceHealth alerts detailed analysis (if available)"
echo -e "  📁 ${BLUE}$output_dir/${NC} - All raw data files"
echo ""

# Display key findings
if [ -f "$output_dir/analysis_report.txt" ]; then
    echo -e "${YELLOW}Key Findings:${NC}"
    echo -e "${CYAN}---${NC}"
    head -n 30 "$output_dir/analysis_report.txt" | tail -n 20
    echo -e "${CYAN}---${NC}"
    echo ""
    echo -e "${GREEN}Full report available in: $output_dir/analysis_report.txt${NC}"
fi

    echo ""
    echo -e "${GREEN}✅ Analysis completed for subscription: $CURRENT_SUB${NC}"
}

# Function to generate consolidated tenant-level dashboard
generate_consolidated_dashboard() {
    local base_output_dir="$1"
    
    echo -e "${BLUE}  Aggregating data from all subscriptions...${NC}"
    
    # Create consolidated dashboard Python script
    cat > "$base_output_dir/create_consolidated_dashboard.py" << 'EOF'
#!/usr/bin/env python3

import json
import os
import glob
from collections import Counter, defaultdict
from datetime import datetime

def load_json_file(filepath):
    """Load JSON file with error handling"""
    try:
        with open(filepath, 'r') as f:
            return json.load(f)
    except:
        return {}

def aggregate_subscription_data():
    """Aggregate data from all subscription directories"""
    
    # Initialize aggregated data
    consolidated = {
        'total_alerts': 0,
        'severity_breakdown': Counter(),
        'alert_state_breakdown': Counter(),
        'alert_state_by_severity': defaultdict(lambda: defaultdict(int)),
        'alert_lifecycle_metrics': {
            'new_alerts': 0,
            'acknowledged_alerts': 0,
            'closed_alerts': 0
        },
        'top_alerts_by_severity': {
            'Sev0': Counter(),
            'Sev1': Counter(),
            'Sev2': Counter(),
            'Sev3': Counter(),
            'Sev4': Counter()
        },
        'resource_type_breakdown': Counter(),
        'resource_group_breakdown': Counter(),
        'top_alerting_resources': Counter(),
        'hourly_distribution': defaultdict(int),
        'daily_distribution': defaultdict(int),
        'correlation_patterns': [],
        'tuning_recommendations': [],
        'alert_storms': [],
        'subscription_summary': [],
        'top_alert_rules': Counter(),
        'alert_rule_details': {},
        'alert_name_to_rule_mapping': Counter()
    }
    
    # Find all subscription directories
    subscription_dirs = glob.glob('subscription_*')
    
    print(f"Found {len(subscription_dirs)} subscription directories")
    
    for sub_dir in subscription_dirs:
        print(f"Processing {sub_dir}...")
        
        # Load subscription info
        sub_info_file = os.path.join(sub_dir, 'subscription_info.txt')
        sub_name = "Unknown"
        sub_id = "Unknown"
        
        if os.path.exists(sub_info_file):
            with open(sub_info_file, 'r') as f:
                lines = f.readlines()
                for line in lines:
                    if line.startswith('Subscription ID:'):
                        sub_id = line.split(':', 1)[1].strip()
                    elif line.startswith('Subscription Name:'):
                        sub_name = line.split(':', 1)[1].strip()
        
        # Load analysis data for this subscription
        analysis_file = os.path.join(sub_dir, 'analysis_data.json')
        if os.path.exists(analysis_file):
            sub_data = load_json_file(analysis_file)
            
            # Aggregate totals
            sub_alerts = sub_data.get('total_alerts', 0)
            consolidated['total_alerts'] += sub_alerts
            
            # Aggregate breakdowns
            for severity, count in sub_data.get('severity_breakdown', {}).items():
                consolidated['severity_breakdown'][severity] += count
                
            # Aggregate alert states
            for state, count in sub_data.get('alert_state_breakdown', {}).items():
                consolidated['alert_state_breakdown'][state] += count
            
            # Aggregate alert state by severity
            for severity, states in sub_data.get('alert_state_by_severity', {}).items():
                for state, count in states.items():
                    consolidated['alert_state_by_severity'][severity][state] += count
            
            # Aggregate lifecycle metrics
            lifecycle = sub_data.get('alert_lifecycle_metrics', {})
            consolidated['alert_lifecycle_metrics']['new_alerts'] += lifecycle.get('new_alerts', 0)
            consolidated['alert_lifecycle_metrics']['acknowledged_alerts'] += lifecycle.get('acknowledged_alerts', 0)
            consolidated['alert_lifecycle_metrics']['closed_alerts'] += lifecycle.get('closed_alerts', 0)
            
            # Aggregate top alerts by severity
            for severity in ['Sev0', 'Sev1', 'Sev2', 'Sev3', 'Sev4']:
                if severity in sub_data.get('top_alerts_by_severity', {}):
                    for alert_name, count in sub_data['top_alerts_by_severity'][severity].items():
                        consolidated['top_alerts_by_severity'][severity][alert_name] += count
                
            for resource_type, count in sub_data.get('resource_type_breakdown', {}).items():
                consolidated['resource_type_breakdown'][resource_type] += count
                
            for rg, count in sub_data.get('resource_group_breakdown', {}).items():
                consolidated['resource_group_breakdown'][rg] += count
                
            for resource, count in sub_data.get('top_alerting_resources', {}).items():
                consolidated['top_alerting_resources'][resource] += count
            
            # Aggregate alert rules
            for rule_name, count in sub_data.get('top_alert_rules', {}).items():
                consolidated['top_alert_rules'][rule_name] += count
            
            # Aggregate alert rule details
            for rule_name, rule_details in sub_data.get('alert_rule_details', {}).items():
                if rule_name not in consolidated['alert_rule_details']:
                    consolidated['alert_rule_details'][rule_name] = {
                        'rule_name': rule_name,
                        'alert_count': 0,
                        'severities': Counter(),
                        'states': Counter(),
                        'affected_resources': set(),
                        'sample_alerts': []
                    }
                
                consolidated_rule = consolidated['alert_rule_details'][rule_name]
                consolidated_rule['alert_count'] += rule_details.get('alert_count', 0)
                
                # Merge severities
                for severity, count in rule_details.get('severities', {}).items():
                    consolidated_rule['severities'][severity] += count
                
                # Merge states
                for state, count in rule_details.get('states', {}).items():
                    consolidated_rule['states'][state] += count
                
                # Merge affected resources
                for resource in rule_details.get('affected_resources', []):
                    consolidated_rule['affected_resources'].add(resource)
                
                # Add sample alerts (limit total samples per rule)
                for sample in rule_details.get('sample_alerts', []):
                    if len(consolidated_rule['sample_alerts']) < 5:  # Limit to 5 samples per rule
                        consolidated_rule['sample_alerts'].append(sample)
            
            # Aggregate alert name to rule mapping
            for mapping, count in sub_data.get('alert_name_to_rule_mapping', {}).items():
                consolidated['alert_name_to_rule_mapping'][mapping] += count
            
            # Add subscription summary
            consolidated['subscription_summary'].append({
                'name': sub_name,
                'id': sub_id,
                'directory': sub_dir,
                'total_alerts': sub_alerts,
                'severity_breakdown': sub_data.get('severity_breakdown', {}),
                'has_data': sub_alerts > 0
            })
            
            print(f"  - {sub_name}: {sub_alerts} alerts")
        else:
            print(f"  - No analysis_data.json found in {sub_dir}")
            consolidated['subscription_summary'].append({
                'name': sub_name,
                'id': sub_id,
                'directory': sub_dir,
                'total_alerts': 0,
                'severity_breakdown': {},
                'has_data': False
            })
    
    # Convert Counters to regular dicts for JSON serialization
    consolidated['severity_breakdown'] = dict(consolidated['severity_breakdown'])
    consolidated['alert_state_breakdown'] = dict(consolidated['alert_state_breakdown'])
    
    # Convert alert state by severity defaultdict to regular dict
    alert_state_by_severity_dict = {}
    for severity, states in consolidated['alert_state_by_severity'].items():
        alert_state_by_severity_dict[severity] = dict(states)
    consolidated['alert_state_by_severity'] = alert_state_by_severity_dict
    
    # Convert top alerts by severity counters
    for severity in consolidated['top_alerts_by_severity']:
        consolidated['top_alerts_by_severity'][severity] = dict(consolidated['top_alerts_by_severity'][severity])
    
    consolidated['resource_type_breakdown'] = dict(consolidated['resource_type_breakdown'])
    consolidated['resource_group_breakdown'] = dict(consolidated['resource_group_breakdown'])
    consolidated['top_alerting_resources'] = dict(consolidated['top_alerting_resources'])
    consolidated['hourly_distribution'] = dict(consolidated['hourly_distribution'])
    consolidated['daily_distribution'] = dict(consolidated['daily_distribution'])
    
    # Convert alert rules data
    consolidated['top_alert_rules'] = dict(consolidated['top_alert_rules'])
    consolidated['alert_name_to_rule_mapping'] = dict(consolidated['alert_name_to_rule_mapping'])
    
    # Convert alert rule details
    for rule_name, rule_details in consolidated['alert_rule_details'].items():
        consolidated['alert_rule_details'][rule_name] = {
            'rule_name': rule_details['rule_name'],
            'alert_count': rule_details['alert_count'],
            'severities': dict(rule_details['severities']),
            'states': dict(rule_details['states']),
            'affected_resources': list(rule_details['affected_resources'])[:15],  # Limit for display
            'affected_resource_count': len(rule_details['affected_resources']),
            'sample_alerts': rule_details['sample_alerts']
        }
    
    return consolidated

def create_consolidated_dashboard(data):
    """Create HTML dashboard with aggregated data"""
    
    dashboard_html = f'''<!DOCTYPE html>
<html>
<head>
    <title>Azure Tenant-Level Alerts Analysis Dashboard</title>
    <style>
        body {{
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 20px;
            background-color: #f5f5f5;
        }}
        .container {{
            max-width: 1400px;
            margin: 0 auto;
            background-color: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }}
        h1 {{
            color: #0078d4;
            border-bottom: 3px solid #0078d4;
            padding-bottom: 10px;
            text-align: center;
        }}
        h2 {{
            color: #323130;
            margin-top: 30px;
            border-bottom: 1px solid #edebe9;
            padding-bottom: 5px;
        }}
        .metric-card {{
            display: inline-block;
            padding: 20px;
            margin: 15px;
            background-color: #f3f2f1;
            border-radius: 8px;
            min-width: 180px;
            text-align: center;
            box-shadow: 0 2px 4px rgba(0,0,0,0.05);
        }}
        .metric-value {{
            font-size: 36px;
            font-weight: bold;
            color: #0078d4;
        }}
        .metric-label {{
            font-size: 16px;
            color: #605e5c;
            margin-top: 8px;
        }}
        .severity-critical {{ color: #d13438; }}
        .severity-error {{ color: #e81123; }}
        .severity-warning {{ color: #ff8c00; }}
        .severity-info {{ color: #0078d4; }}
        table {{
            width: 100%;
            border-collapse: collapse;
            margin-top: 15px;
        }}
        th {{
            background-color: #0078d4;
            color: white;
            padding: 12px;
            text-align: left;
        }}
        td {{
            padding: 10px;
            border-bottom: 1px solid #edebe9;
        }}
        tr:hover {{
            background-color: #f3f2f1;
        }}
        .subscription-card {{
            background-color: #f8f9fa;
            border: 1px solid #dee2e6;
            border-radius: 8px;
            padding: 15px;
            margin: 10px 0;
        }}
        .subscription-name {{
            font-weight: bold;
            color: #0078d4;
            font-size: 18px;
        }}
        .no-data {{
            color: #6c757d;
            font-style: italic;
        }}
        .tenant-info {{
            background-color: #e3f2fd;
            border-left: 4px solid #0078d4;
            padding: 15px;
            margin: 20px 0;
            border-radius: 4px;
        }}
    </style>
</head>
<body>
    <div class="container">
        <h1>🏢 Azure Tenant-Level Alerts Analysis Dashboard</h1>
        <div class="tenant-info">
            <strong>Analysis Generated:</strong> {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}<br>
            <strong>Scope:</strong> Complete Azure Tenant Alert Analysis<br>
            <strong>Subscriptions Analyzed:</strong> {len(data['subscription_summary'])}
        </div>
        
        <h2>📊 Tenant-Level Alert Metrics</h2>
        <div style="text-align: center;">
            <div class="metric-card">
                <div class="metric-value">{data['total_alerts']}</div>
                <div class="metric-label">Total Tenant Alerts</div>
            </div>
            <div class="metric-card">
                <div class="metric-value">{len(data['subscription_summary'])}</div>
                <div class="metric-label">Subscriptions Analyzed</div>
            </div>
            <div class="metric-card">
                <div class="metric-value">{sum(1 for sub in data['subscription_summary'] if sub['has_data'])}</div>
                <div class="metric-label">Subscriptions with Alerts</div>
            </div>
        </div>'''
    
    # Add alert lifecycle metrics if available
    if data['alert_lifecycle_metrics']:
        lifecycle = data['alert_lifecycle_metrics']
        dashboard_html += f'''
        <div style="text-align: center;">
            <div class="metric-card">
                <div class="metric-value">{lifecycle['new_alerts']}</div>
                <div class="metric-label">New Alerts</div>
            </div>
            <div class="metric-card">
                <div class="metric-value">{lifecycle['acknowledged_alerts']}</div>
                <div class="metric-label">Acknowledged Alerts</div>
            </div>
            <div class="metric-card">
                <div class="metric-value">{lifecycle['closed_alerts']}</div>
                <div class="metric-label">Closed/Resolved Alerts</div>
            </div>
        </div>'''
    
    # Severity breakdown
    dashboard_html += '<h2>🚨 Tenant Alert Severity Distribution</h2>'
    if data['severity_breakdown']:
        dashboard_html += '<table><tr><th>Severity</th><th>Count</th><th>Percentage</th></tr>'
        total_alerts = data['total_alerts']
        for severity, count in sorted(data['severity_breakdown'].items(), key=lambda x: x[1], reverse=True):
            percentage = (count / total_alerts * 100) if total_alerts > 0 else 0
            severity_class = get_severity_class(severity)
            dashboard_html += f'<tr><td class="{severity_class}">{severity}</td><td>{count}</td><td>{percentage:.1f}%</td></tr>'
        dashboard_html += '</table>'
    
    # Alert state breakdown with severity details
    if data['alert_state_breakdown']:
        dashboard_html += '<h2>🔄 Alert State Distribution</h2>'
        dashboard_html += '<table><tr><th>State</th><th>Count</th><th>Percentage</th><th>Severity Breakdown</th></tr>'
        total_alerts = data['total_alerts']
        for state, count in sorted(data['alert_state_breakdown'].items(), key=lambda x: x[1], reverse=True):
            percentage = (count / total_alerts * 100) if total_alerts > 0 else 0
            
            # Build severity breakdown for this state
            severity_details = []
            if 'alert_state_by_severity' in data:
                for severity, states in data['alert_state_by_severity'].items():
                    if state in states and states[state] > 0:
                        severity_class = get_severity_class(severity)
                        severity_details.append(f'<span class="{severity_class}">{severity}: {states[state]}</span>')
            
            severity_breakdown = '<br>'.join(severity_details) if severity_details else 'None'
            dashboard_html += f'<tr><td><strong>{state}</strong></td><td>{count}</td><td>{percentage:.1f}%</td><td>{severity_breakdown}</td></tr>'
        dashboard_html += '</table>'
    
    # Top alerts by severity
    dashboard_html += '<h2>⚠️ Top Alerts by Severity (Tenant-Wide)</h2>'
    if data['top_alerts_by_severity']:
        for severity in ['Sev0', 'Sev1', 'Sev2', 'Sev3', 'Sev4']:
            if severity in data['top_alerts_by_severity'] and data['top_alerts_by_severity'][severity]:
                severity_class = get_severity_class(severity)
                dashboard_html += f'<h3 class="{severity_class}">{severity} Alerts (Tenant-Wide)</h3>'
                dashboard_html += '<table><tr><th>Alert Name</th><th>Total Occurrences</th></tr>'
                for alert_name, count in sorted(data['top_alerts_by_severity'][severity].items(), key=lambda x: x[1], reverse=True)[:10]:
                    dashboard_html += f'<tr><td>{alert_name}</td><td>{count}</td></tr>'
                dashboard_html += '</table>'
    
    # Top alerting resources
    if data['top_alerting_resources']:
        dashboard_html += '<h2>🎯 Top Alerting Resources (Tenant-Wide)</h2>'
        dashboard_html += '<table><tr><th>AffectedResource</th><th>Alert Count</th></tr>'
        for resource, count in sorted(data['top_alerting_resources'].items(), key=lambda x: x[1], reverse=True)[:15]:
            display_name = resource if len(resource) <= 100 else resource[:97] + '...'
            dashboard_html += f'<tr><td title="{resource}">{display_name}</td><td>{count}</td></tr>'
        dashboard_html += '</table>'
    
    # Subscription summary
    dashboard_html += '<h2>📋 Per-Subscription Analysis Summary</h2>'
    for sub in sorted(data['subscription_summary'], key=lambda x: x['total_alerts'], reverse=True):
        status_class = "" if sub['has_data'] else "no-data"
        status_text = f"{sub['total_alerts']} alerts" if sub['has_data'] else "No alerts found"
        
        dashboard_html += f'''
        <div class="subscription-card">
            <div class="subscription-name">{sub['name']}</div>
            <div><strong>Subscription ID:</strong> {sub['id']}</div>
            <div class="{status_class}"><strong>Alert Count:</strong> {status_text}</div>
            <div><strong>Analysis Directory:</strong> {sub['directory']}</div>
        </div>'''
    
    dashboard_html += '''
    </div>
</body>
</html>'''
    
    return dashboard_html

def get_severity_class(severity):
    """Get CSS class for severity"""
    severity_map = {
        'Sev0': 'severity-critical',
        'Sev1': 'severity-error', 
        'Sev2': 'severity-warning',
        'Sev3': 'severity-info',
        'Sev4': 'severity-info',
        'Critical': 'severity-critical',
        'Error': 'severity-error',
        'Warning': 'severity-warning',
        'Informational': 'severity-info'
    }
    return severity_map.get(severity, '')

def main():
    print("Creating tenant-level consolidated dashboard...")
    
    # Aggregate data from all subscriptions
    consolidated_data = aggregate_subscription_data()
    
    # Save consolidated analysis data
    with open('tenant_analysis_data.json', 'w') as f:
        json.dump(consolidated_data, f, indent=2)
    
    print(f"\\nTenant-Level Analysis Summary:")
    print(f"Total Alerts: {consolidated_data['total_alerts']}")
    print(f"Subscriptions: {len(consolidated_data['subscription_summary'])}")
    print(f"Subscriptions with alerts: {sum(1 for sub in consolidated_data['subscription_summary'] if sub['has_data'])}")
    
    # Create consolidated dashboard
    dashboard_html = create_consolidated_dashboard(consolidated_data)
    
    with open('tenant_dashboard.html', 'w') as f:
        f.write(dashboard_html)
    
    print("\\nTenant-level files created:")
    print("- tenant_analysis_data.json")
    print("- tenant_dashboard.html")
    print("\\nOpen tenant_dashboard.html in your browser to view the consolidated tenant-level results.")

if __name__ == "__main__":
    main()
EOF
    
    # Run the consolidated dashboard generation
    cd "$base_output_dir" || {
        echo -e "${RED}Error: Could not change to base output directory: $base_output_dir${NC}"
        return 1
    }
    
    python3 create_consolidated_dashboard.py
    
    # Go back to the original working directory
    cd - > /dev/null
    
    echo -e "${GREEN}✅ Tenant-level consolidated dashboard generated${NC}"
}

# Function to analyze single subscription
analyze_subscription() {
    local sub_id="$1"
    local sub_name="$2"
    local sub_output_dir="$3"
    
    echo -e "${GREEN}[SUBSCRIPTION] Analyzing: ${YELLOW}$sub_name ($sub_id)${NC}"
    
    # Set the subscription
    az account set --subscription "$sub_id" || {
        echo -e "${RED}Failed to set subscription: $sub_id${NC}"
        return 1
    }
    
    # Create subscription-specific directory
    echo -e "${BLUE}  Creating output directory: $sub_output_dir${NC}"
    mkdir -p "$sub_output_dir" || {
        echo -e "${RED}Error: Could not create output directory: $sub_output_dir${NC}"
        return 1
    }
    
    # Save subscription info
    echo "Subscription ID: $sub_id" > "$sub_output_dir/subscription_info.txt"
    echo "Subscription Name: $sub_name" >> "$sub_output_dir/subscription_info.txt"
    echo "Analysis Date: $(date)" >> "$sub_output_dir/subscription_info.txt"
    
    # Debug: About to call analyze_subscription_alerts
    echo "DEBUG: About to call analyze_subscription_alerts with: $sub_output_dir" >&2
    echo "DEBUG: Current functions available:" >&2
    declare -F | grep analyze >&2
    
    # Run the alert analysis for this subscription (we'll call the analysis functions here)
    analyze_subscription_alerts "$sub_output_dir"
}

# Set up subscription processing
if [ "$ALL_SUBSCRIPTIONS" = true ]; then
    echo -e "${CYAN}Processing all subscriptions in tenant...${NC}"
    
    # Get all subscriptions
    SUBSCRIPTIONS=$(get_all_subscriptions)
    if [ -z "$SUBSCRIPTIONS" ]; then
        echo -e "${RED}No enabled subscriptions found in tenant${NC}"
        exit 1
    fi
    
    # Apply debug mode limitation
    if [ "$DEBUG_MODE" = true ]; then
        echo -e "${YELLOW}Debug mode enabled: limiting to first 3 subscriptions${NC}"
        SUBSCRIPTIONS=$(echo "$SUBSCRIPTIONS" | head -n 3)
    fi
    
    # Create summary file
    echo "Multi-Subscription Analysis Summary" > "$OUTPUT_DIR/analysis_summary.txt"
    echo "====================================" >> "$OUTPUT_DIR/analysis_summary.txt"
    echo "Analysis Date: $(date)" >> "$OUTPUT_DIR/analysis_summary.txt"
    echo "Analysis Period: $DAYS_BACK days" >> "$OUTPUT_DIR/analysis_summary.txt"
    if [ "$DEBUG_MODE" = true ]; then
        echo "Debug Mode: ENABLED (limited to first 3 subscriptions)" >> "$OUTPUT_DIR/analysis_summary.txt"
    fi
    echo "" >> "$OUTPUT_DIR/analysis_summary.txt"
    
    # Save subscriptions to temporary file to avoid subshell issues
    TEMP_SUBS_FILE="$OUTPUT_DIR/temp_subscriptions.txt"
    echo "$SUBSCRIPTIONS" > "$TEMP_SUBS_FILE"
    
    # Process each subscription
    SUB_COUNT=0
    while IFS=$'\t' read -r sub_id sub_name; do
        # Trim whitespace from both fields
        sub_id=$(echo "$sub_id" | xargs)
        sub_name=$(echo "$sub_name" | xargs)
        SUB_COUNT=$((SUB_COUNT + 1))
        SANITIZED_NAME=$(echo "$sub_name" | tr ' ' '_' | tr -cd '[:alnum:]_-' | cut -c1-50)
        SUB_DIR="$OUTPUT_DIR/subscription_${SUB_COUNT}_${SANITIZED_NAME}"
        
        echo "Subscription $SUB_COUNT: $sub_name ($sub_id)" >> "$OUTPUT_DIR/analysis_summary.txt"
        echo "Output Directory: $SUB_DIR" >> "$OUTPUT_DIR/analysis_summary.txt"
        echo "" >> "$OUTPUT_DIR/analysis_summary.txt"
        
        analyze_subscription "$sub_id" "$sub_name" "$SUB_DIR"
    done < "$TEMP_SUBS_FILE"
    
    # Clean up temporary file
    rm -f "$TEMP_SUBS_FILE"
    
    echo -e "${GREEN}Processed $SUB_COUNT subscriptions${NC}"
    
    # Generate consolidated tenant-level dashboard
    echo -e "${GREEN}[CONSOLIDATE] Generating Tenant-Level Consolidated Dashboard...${NC}"
    generate_consolidated_dashboard "$OUTPUT_DIR"
    
elif [ -n "$SUBSCRIPTION" ]; then
    echo -e "Validating subscription: ${YELLOW}$SUBSCRIPTION${NC}"
    
    # Check if the specified subscription exists and is in the current tenant
    SUB_TENANT=$(az account show --subscription "$SUBSCRIPTION" --query tenantId -o tsv 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Subscription '$SUBSCRIPTION' not found or not accessible${NC}"
        exit 1
    fi
    
    if [ "$SUB_TENANT" != "$TENANT_ID" ]; then
        echo -e "${RED}Error: Subscription '$SUBSCRIPTION' is in tenant '$SUB_TENANT', not current tenant '$TENANT_ID'${NC}"
        echo -e "${YELLOW}Available subscriptions in current tenant:${NC}"
        az account list --query "[?tenantId=='$TENANT_ID' && state=='Enabled'].{name:name,id:id}" -o table
        exit 1
    fi
    
    echo -e "${GREEN}✓ Subscription is in current tenant${NC}"
    echo -e "Setting subscription: ${YELLOW}$SUBSCRIPTION${NC}"
    az account set --subscription "$SUBSCRIPTION"
    analyze_subscription_alerts "$OUTPUT_DIR"
else
    # Use current subscription
    analyze_subscription_alerts "$OUTPUT_DIR"
fi

# Final summary and cleanup
echo ""
echo -e "${CYAN}================================================================================================${NC}"
if [ "$ALL_SUBSCRIPTIONS" = true ]; then
    echo -e "${GREEN}✅ TENANT-LEVEL MULTI-SUBSCRIPTION ANALYSIS COMPLETED SUCCESSFULLY!${NC}"
    echo ""
    echo -e "${YELLOW}📊 TENANT-LEVEL CONSOLIDATED DASHBOARD:${NC}"
    echo -e "   🌐 ${BLUE}$OUTPUT_DIR/tenant_dashboard.html${NC} - Complete tenant-level analysis dashboard"
    echo -e "   📈 ${BLUE}$OUTPUT_DIR/tenant_analysis_data.json${NC} - Aggregated tenant alert data"
    echo ""
    echo -e "${YELLOW}📋 ADDITIONAL REPORTS:${NC}"
    echo -e "   📄 ${BLUE}$OUTPUT_DIR/analysis_summary.txt${NC} - Multi-subscription summary report"
    echo -e "   📁 ${BLUE}$OUTPUT_DIR/subscription_*/${NC} - Individual subscription analysis directories"
    echo ""
    echo -e "${GREEN}🎯 KEY INSIGHT: Open the tenant_dashboard.html file to view all alerts aggregated at the Azure tenant level!${NC}"
else
    echo -e "${GREEN}✅ Single subscription analysis completed successfully!${NC}"
    echo -e "   🌐 ${BLUE}$OUTPUT_DIR/dashboard.html${NC} - Interactive analysis dashboard"
    echo -e "   🏥 ${BLUE}$OUTPUT_DIR/resourcehealth_dashboard.html${NC} - ResourceHealth detailed analysis (if alerts found)"
    echo -e "   📈 ${BLUE}$OUTPUT_DIR/analysis_data.json${NC} - Detailed analysis data"
fi
echo -e "${CYAN}================================================================================================${NC}"
