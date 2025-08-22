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
    <title>Consolidated Azure Alerts Analysis Dashboard</title>
    <style>
        body {{
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 20px;
            background-color: #f5f5f5;
        }}
        .container {{
            max-width: 1200px;
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
        }}
        h2 {{
            color: #323130;
            margin-top: 30px;
            border-bottom: 1px solid #edebe9;
            padding-bottom: 5px;
        }}
        .metric-card {{
            display: inline-block;
            padding: 15px;
            margin: 10px;
            background-color: #f3f2f1;
            border-radius: 4px;
            min-width: 150px;
            text-align: center;
        }}
        .metric-value {{
            font-size: 32px;
            font-weight: bold;
            color: #0078d4;
        }}
        .metric-label {{
            font-size: 14px;
            color: #605e5c;
            margin-top: 5px;
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
            padding: 10px;
            text-align: left;
        }}
        td {{
            padding: 8px;
            border-bottom: 1px solid #edebe9;
        }}
        tr:hover {{
            background-color: #f3f2f1;
        }}
        .subscription-card {{
            background-color: #f8f9fa;
            border: 1px solid #dee2e6;
            border-radius: 4px;
            padding: 15px;
            margin: 10px 0;
        }}
        .subscription-name {{
            font-weight: bold;
            color: #0078d4;
        }}
        .no-data {{
            color: #6c757d;
            font-style: italic;
        }}
    </style>
</head>
<body>
    <div class="container">
        <h1>Consolidated Azure Alerts Analysis Dashboard</h1>
        <p>Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
        
        <h2>Overall Metrics</h2>
        <div class="metric-card">
            <div class="metric-value">{data['total_alerts']}</div>
            <div class="metric-label">Total Alerts</div>
        </div>
        <div class="metric-card">
            <div class="metric-value">{len(data['subscription_summary'])}</div>
            <div class="metric-label">Subscriptions Analyzed</div>
        </div>
        <div class="metric-card">
            <div class="metric-value">{sum(1 for sub in data['subscription_summary'] if sub['has_data'])}</div>
            <div class="metric-label">Subscriptions with Alerts</div>
        </div>
        
        <h2>Severity Breakdown</h2>
        <table>
            <tr><th>Severity</th><th>Count</th><th>Percentage</th></tr>'''
    
    total_alerts = data['total_alerts']
    for severity, count in data['severity_breakdown'].items():
        percentage = (count / total_alerts * 100) if total_alerts > 0 else 0
        severity_class = f"severity-{severity.lower().replace('sev', '')}"
        dashboard_html += f'''
            <tr>
                <td class="{severity_class}">{severity}</td>
                <td>{count}</td>
                <td>{percentage:.1f}%</td>
            </tr>'''
    
    dashboard_html += '''
        </table>
        
        <h2>Resource Type Breakdown</h2>
        <table>
            <tr><th>Resource Type</th><th>Alert Count</th></tr>'''
    
    for resource_type, count in sorted(data['resource_type_breakdown'].items(), key=lambda x: x[1], reverse=True)[:10]:
        dashboard_html += f'''
            <tr><td>{resource_type}</td><td>{count}</td></tr>'''
    
    dashboard_html += '''
        </table>
        
        <h2>Subscription Summary</h2>'''
    
    for sub in sorted(data['subscription_summary'], key=lambda x: x['total_alerts'], reverse=True):
        status_class = "" if sub['has_data'] else "no-data"
        status_text = f"{sub['total_alerts']} alerts" if sub['has_data'] else "No alerts found"
        
        dashboard_html += f'''
        <div class="subscription-card">
            <div class="subscription-name">{sub['name']}</div>
            <div>ID: {sub['id']}</div>
            <div class="{status_class}">Status: {status_text}</div>
            <div>Directory: {sub['directory']}</div>
        </div>'''
    
    dashboard_html += '''
    </div>
</body>
</html>'''
    
    return dashboard_html

def main():
    print("Creating consolidated dashboard...")
    
    # Aggregate data from all subscriptions
    consolidated_data = aggregate_subscription_data()
    
    # Save consolidated analysis data
    with open('consolidated_analysis_data.json', 'w') as f:
        json.dump(consolidated_data, f, indent=2)
    
    print(f"\\nConsolidated Analysis Summary:")
    print(f"Total Alerts: {consolidated_data['total_alerts']}")
    print(f"Subscriptions: {len(consolidated_data['subscription_summary'])}")
    print(f"Subscriptions with alerts: {sum(1 for sub in consolidated_data['subscription_summary'] if sub['has_data'])}")
    
    # Create consolidated dashboard
    dashboard_html = create_consolidated_dashboard(consolidated_data)
    
    with open('consolidated_dashboard.html', 'w') as f:
        f.write(dashboard_html)
    
    print("\\nFiles created:")
    print("- consolidated_analysis_data.json")
    print("- consolidated_dashboard.html")
    print("\\nOpen consolidated_dashboard.html in your browser to view the results.")

if __name__ == "__main__":
    main()