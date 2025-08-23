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
