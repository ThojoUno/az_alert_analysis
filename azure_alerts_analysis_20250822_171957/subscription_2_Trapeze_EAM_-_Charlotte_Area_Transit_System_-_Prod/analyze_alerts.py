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
        'resource_health_alerts': []
    }
    
    # Analyze activity alerts
    for alert in activity_alerts:
        # Handle severity/level
        level = alert.get('level')
        if level and isinstance(level, str):
            analysis['severity_breakdown'][level] += 1
        
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
            'resource_health_alerts': analysis['resource_health_alerts']
        }
        json.dump(analysis_json, f, indent=2, default=str)
    
    print(report)
