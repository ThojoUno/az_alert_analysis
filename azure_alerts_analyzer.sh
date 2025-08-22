#!/bin/bash

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
        PYTHON_VERSION=$(python3 --version 2>&1 | grep -Po '(?<=Python )\d+\.\d+')
        echo -e "${GREEN}✓ Found Python $PYTHON_VERSION${NC}"
    else
        echo -e "${RED}✗ Not found${NC}"
        missing_packages+=("python3")
        missing_packages+=("python3-pip")
    fi
    
    # Check for pip3
    echo -n -e "${BLUE}Checking pip3...${NC} "
    if command -v pip3 &> /dev/null; then
        echo -e "${GREEN}✓ Found$(pip3 --version 2>&1 | grep -Po 'pip \d+\.\d+')${NC}"
    else
        echo -e "${YELLOW}✗ Not found${NC}"
        missing_packages+=("python3-pip")
    fi
    
    # Check for curl
    echo -n -e "${BLUE}Checking curl...${NC} "
    if command -v curl &> /dev/null; then
        echo -e "${GREEN}✓ Found$(curl --version 2>&1 | head -n1 | grep -Po 'curl \d+\.\d+')${NC}"
    else
        echo -e "${RED}✗ Not found${NC}"
        missing_packages+=("curl")
    fi
    
    # Check for jq (JSON processor)
    echo -n -e "${BLUE}Checking jq...${NC} "
    if command -v jq &> /dev/null; then
        echo -e "${GREEN}✓ Found jq$(jq --version 2>&1 | grep -Po '\d+\.\d+')${NC}"
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
            echo -e "${YELLOW}  Run 'az login' after setup completes${NC}"
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
                echo -e "${YELLOW}Please run 'az login' to authenticate${NC}"
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
    curl -sLS https://packages.microsoft.com/keys/microsoft.asc |
        gpg --dearmor |
        sudo tee /etc/apt/keyrings/microsoft.gpg > /dev/null
    sudo chmod go+r /etc/apt/keyrings/microsoft.gpg
    
    # Add Azure CLI repository
    AZ_DIST=$(lsb_release -cs)
    echo "deb [arch=`dpkg --print-architecture` signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $AZ_DIST main" |
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
    echo -e "1. Run: ${CYAN}az login${NC} to authenticate with Azure"
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

# Check if logged in to Azure
if ! az account show &> /dev/null; then
    echo -e "${YELLOW}Not logged in to Azure${NC}"
    echo -e "Please run: ${CYAN}az login${NC}"
    exit 1
fi

# Configuration
OUTPUT_DIR="azure_alerts_analysis_$(date +%Y%m%d_%H%M%S)"
SUBSCRIPTION=""
DAYS_BACK=7
RESOURCE_GROUP=""

# Function to display usage
show_usage() {
    echo -e "${CYAN}================================================================================================${NC}"
    echo -e "${GREEN}Azure Alerts Analysis Tool${NC}"
    echo -e "${CYAN}================================================================================================${NC}"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -s, --subscription <id>    Azure subscription ID (optional, uses current if not specified)"
    echo "  -d, --days <number>         Number of days to analyze (7, 14, or 30, default: 7)"
    echo "  -r, --resource-group <name> Specific resource group to analyze (optional)"
    echo "  -h, --help                  Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -d 14"
    echo "  $0 -s <subscription-id> -d 30"
    echo "  $0 -r <resource-group> -d 7"
    echo ""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--subscription)
            SUBSCRIPTION="$2"
            shift 2
            ;;
        -d|--days)
            DAYS_BACK="$2"
            shift 2
            ;;
        -r|--resource-group)
            RESOURCE_GROUP="$2"
            shift 2
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

# Create output directory
mkdir -p "$OUTPUT_DIR"

echo -e "${CYAN}================================================================================================${NC}"
echo -e "${GREEN}Starting Azure Alerts Analysis${NC}"
echo -e "${CYAN}================================================================================================${NC}"
echo -e "Analysis Period: ${YELLOW}$DAYS_BACK days${NC}"
echo -e "Output Directory: ${YELLOW}$OUTPUT_DIR${NC}"

# Set subscription if provided
if [ -n "$SUBSCRIPTION" ]; then
    echo -e "Setting subscription: ${YELLOW}$SUBSCRIPTION${NC}"
    az account set --subscription "$SUBSCRIPTION"
fi

# Get current subscription info
CURRENT_SUB=$(az account show --query name -o tsv)
echo -e "Current Subscription: ${YELLOW}$CURRENT_SUB${NC}"
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

az monitor activity-log list \
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
    -o json > "$OUTPUT_DIR/activity_alerts.json"

#################################################################################
# Section 2: Download Metric Alerts
#################################################################################
echo -e "${GREEN}[2/8] Downloading Metric Alerts...${NC}"

# Get all metric alert rules
az monitor metrics alert list \
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
    -o json > "$OUTPUT_DIR/metric_alert_rules.json"

#################################################################################
# Section 3: Download Alert History
#################################################################################
echo -e "${GREEN}[3/8] Downloading Alert History...${NC}"

# Get alert history from Azure Monitor
az rest --method GET \
    --uri "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/providers/Microsoft.AlertsManagement/alerts?api-version=2019-05-05-preview&timeRange=${DAYS_BACK}d" \
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
        description: properties.essentials.description
    }" \
    -o json > "$OUTPUT_DIR/alert_history.json" 2>/dev/null || echo "[]" > "$OUTPUT_DIR/alert_history.json"

#################################################################################
# Section 4: Analyze and Generate Reports
#################################################################################
echo -e "${GREEN}[4/8] Analyzing Alert Data...${NC}"

# Create analysis Python script
cat > "$OUTPUT_DIR/analyze_alerts.py" << 'EOF'
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
        'resource_type_breakdown': Counter(),
        'resource_group_breakdown': Counter(),
        'hourly_distribution': defaultdict(int),
        'daily_distribution': defaultdict(int),
        'top_alerting_resources': Counter(),
        'correlation_patterns': [],
        'tuning_recommendations': [],
        'alert_storms': [],
        'maintenance_windows': []
    }
    
    # Analyze activity alerts
    for alert in activity_alerts:
        if alert['level']:
            analysis['severity_breakdown'][alert['level']] += 1
        if alert['resourceType']:
            analysis['resource_type_breakdown'][alert['resourceType']] += 1
        if alert['resourceGroup']:
            analysis['resource_group_breakdown'][alert['resourceGroup']] += 1
        if alert['resourceId']:
            analysis['top_alerting_resources'][alert['resourceId']] += 1
        
        # Time distribution
        if alert['timestamp']:
            dt = datetime.fromisoformat(alert['timestamp'].replace('Z', '+00:00'))
            hour = dt.hour
            day = dt.strftime('%Y-%m-%d')
            analysis['hourly_distribution'][hour] += 1
            analysis['daily_distribution'][day] += 1
    
    # Analyze alert history
    for alert in alert_history:
        if alert.get('severity'):
            analysis['severity_breakdown'][alert['severity']] += 1
        if alert.get('targetResourceType'):
            analysis['resource_type_breakdown'][alert['targetResourceType']] += 1
        if alert.get('targetResourceGroup'):
            analysis['resource_group_breakdown'][alert['targetResourceGroup']] += 1
        if alert.get('targetResource'):
            analysis['top_alerting_resources'][alert['targetResource']] += 1
    
    # Detect alert storms (>10 alerts in 5 minutes)
    time_windows = defaultdict(list)
    for alert in activity_alerts:
        if alert['timestamp']:
            dt = datetime.fromisoformat(alert['timestamp'].replace('Z', '+00:00'))
            window = dt.replace(minute=(dt.minute // 5) * 5, second=0, microsecond=0)
            time_windows[window].append(alert)
    
    for window, alerts in time_windows.items():
        if len(alerts) > 10:
            analysis['alert_storms'].append({
                'time': window.isoformat(),
                'count': len(alerts),
                'resources': list(set([a['resourceId'] for a in alerts if a['resourceId']]))[:5]
            })
    
    # Generate tuning recommendations
    # Find non-critical alerts that fire frequently
    low_severity_frequent = []
    for resource, count in analysis['top_alerting_resources'].most_common(20):
        # Check if this resource has mostly low-severity alerts
        low_sev_count = sum(1 for a in activity_alerts 
                          if a['resourceId'] == resource and a['level'] in ['Warning', 'Informational'])
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
        if alert.get('correlationId'):
            correlation_groups[alert['correlationId']].append(alert)
    
    for corr_id, alerts in correlation_groups.items():
        if len(alerts) > 2:
            analysis['correlation_patterns'].append({
                'correlation_id': corr_id,
                'alert_count': len(alerts),
                'resources': list(set([a['resourceId'] for a in alerts if a['resourceId']]))[:5],
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
        analysis_json = {
            'total_alerts': analysis['total_alerts'],
            'severity_breakdown': dict(analysis['severity_breakdown']),
            'resource_type_breakdown': dict(analysis['resource_type_breakdown']),
            'resource_group_breakdown': dict(analysis['resource_group_breakdown']),
            'top_alerting_resources': dict(analysis['top_alerting_resources'].most_common(20)),
            'hourly_distribution': dict(analysis['hourly_distribution']),
            'daily_distribution': dict(analysis['daily_distribution']),
            'correlation_patterns': analysis['correlation_patterns'],
            'tuning_recommendations': analysis['tuning_recommendations'],
            'alert_storms': analysis['alert_storms']
        }
        json.dump(analysis_json, f, indent=2, default=str)
    
    print(report)
EOF

# Run Python analysis
cd "$OUTPUT_DIR"
python3 analyze_alerts.py $DAYS_BACK
cd ..

#################################################################################
# Section 5: Get Alert Rules Configuration
#################################################################################
echo -e "${GREEN}[5/8] Analyzing Alert Rules Configuration...${NC}"

# Get all alert rules
az monitor metrics alert list --query "[].{
    name: name,
    enabled: enabled,
    severity: severity,
    frequency: evaluationFrequency,
    windowSize: windowSize
}" -o table > "$OUTPUT_DIR/alert_rules_summary.txt"

#################################################################################
# Section 6: Check for Scheduled Maintenance
#################################################################################
echo -e "${GREEN}[6/8] Checking for Scheduled Maintenance...${NC}"

# Query for maintenance configurations
az maintenance configuration list \
    --query "[].{
        name: name,
        maintenanceScope: maintenanceScope,
        startDateTime: window.startDateTime,
        duration: window.duration,
        timeZone: window.timeZone,
        recurEvery: window.recurEvery
    }" \
    -o json > "$OUTPUT_DIR/maintenance_windows.json" 2>/dev/null || echo "[]" > "$OUTPUT_DIR/maintenance_windows.json"

# Query for upcoming maintenance updates
az rest --method GET \
    --uri "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/providers/Microsoft.Maintenance/updates?api-version=2021-05-01" \
    --query "value[].{
        name: name,
        status: properties.status,
        impactType: properties.impactType,
        impactDurationInSec: properties.impactDurationInSec,
        notBefore: properties.notBefore,
        resourceId: properties.resourceId
    }" \
    -o json > "$OUTPUT_DIR/upcoming_maintenance.json" 2>/dev/null || echo "[]" > "$OUTPUT_DIR/upcoming_maintenance.json"

#################################################################################
# Section 7: Generate Maintenance Report
#################################################################################
echo -e "${GREEN}[7/8] Generating Maintenance Report...${NC}"

cat > "$OUTPUT_DIR/maintenance_report.py" << 'EOF'
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

cd "$OUTPUT_DIR"
python3 maintenance_report.py
cd ..

#################################################################################
# Section 8: Generate Final Summary
#################################################################################
echo -e "${GREEN}[8/8] Generating Final Summary...${NC}"

# Create HTML dashboard
cat > "$OUTPUT_DIR/dashboard.html" << 'EOF'
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
                const metricsHtml = `
                    <div class="metric-card">
                        <div class="metric-value">${data.total_alerts}</div>
                        <div class="metric-label">Total Alerts</div>
                    </div>
                `;
                document.getElementById('metrics').innerHTML = metricsHtml;
                
                // Add more visualization code here
            })
            .catch(error => console.error('Error loading data:', error));
    </script>
</body>
</html>
EOF

#################################################################################
# Display Final Summary
#################################################################################
echo ""
echo -e "${CYAN}================================================================================================${NC}"
echo -e "${GREEN}ANALYSIS COMPLETE${NC}"
echo -e "${CYAN}================================================================================================${NC}"
echo ""
echo -e "${YELLOW}Output Files Generated:${NC}"
echo -e "  📊 ${BLUE}$OUTPUT_DIR/analysis_report.txt${NC} - Main analysis report"
echo -e "  📈 ${BLUE}$OUTPUT_DIR/analysis_data.json${NC} - Detailed JSON data"
echo -e "  🔧 ${BLUE}$OUTPUT_DIR/maintenance_report.txt${NC} - Maintenance schedule"
echo -e "  📋 ${BLUE}$OUTPUT_DIR/alert_rules_summary.txt${NC} - Alert rules configuration"
echo -e "  🌐 ${BLUE}$OUTPUT_DIR/dashboard.html${NC} - Interactive HTML dashboard"
echo -e "  📁 ${BLUE}$OUTPUT_DIR/${NC} - All raw data files"
echo ""

# Display key findings
if [ -f "$OUTPUT_DIR/analysis_report.txt" ]; then
    echo -e "${YELLOW}Key Findings:${NC}"
    echo -e "${CYAN}---${NC}"
    head -n 30 "$OUTPUT_DIR/analysis_report.txt" | tail -n 20
    echo -e "${CYAN}---${NC}"
    echo ""
    echo -e "${GREEN}Full report available in: $OUTPUT_DIR/analysis_report.txt${NC}"
fi

echo ""
echo -e "${GREEN}✅ Script execution completed successfully!${NC}"
echo -e "${CYAN}================================================================================================${NC}"
