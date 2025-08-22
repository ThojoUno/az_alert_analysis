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
