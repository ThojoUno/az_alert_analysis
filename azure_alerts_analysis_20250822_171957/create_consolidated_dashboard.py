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
        'subscription_summary': []
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
