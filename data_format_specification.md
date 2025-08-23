# Azure Alert Data Exchange Format Specification

## Overview
This document defines the standardized data format used for exchanging alert data between the Azure Alert Crawler, Analyzer, and Dashboard Generator components.

## File Structure

### Directory Layout
```
azure_alerts_data_YYYYMMDD_HHMMSS/
├── metadata.json                    # Run metadata and configuration
├── subscriptions/
│   ├── subscription_1_Name/
│   │   ├── subscription_info.json   # Subscription details
│   │   ├── activity_alerts.json     # Activity log alerts
│   │   ├── alert_history.json       # Alert management API data
│   │   ├── metric_alert_rules.json  # Metric alert rules
│   │   ├── maintenance_windows.json # Maintenance schedules
│   │   └── collection_status.json   # Collection status and errors
│   └── subscription_2_Name/
│       └── ...
└── tenant_summary.json              # Cross-subscription summary
```

## Data Format Specifications

### 1. metadata.json
```json
{
  "version": "1.0",
  "collection_timestamp": "2025-08-23T10:00:00Z",
  "tenant_id": "12345678-1234-1234-1234-123456789012",
  "collection_config": {
    "days_back": 7,
    "include_maintenance": true,
    "include_resource_health": true,
    "timeout_seconds": 30
  },
  "subscriptions_processed": 3,
  "subscriptions_successful": 3,
  "subscriptions_failed": 0,
  "total_alerts_collected": 150,
  "collection_duration_seconds": 245
}
```

### 2. subscription_info.json
```json
{
  "subscription_id": "8cff88e3-7424-4403-bccc-d8b4672f4d39",
  "subscription_name": "Production Subscription",
  "tenant_id": "12345678-1234-1234-1234-123456789012",
  "state": "Enabled",
  "collection_timestamp": "2025-08-23T10:05:00Z",
  "resource_groups": [
    "rg-prod-eastus",
    "rg-prod-westus"
  ]
}
```

### 3. activity_alerts.json
```json
[
  {
    "id": "activity-alert-001",
    "timestamp": "2025-08-23T09:30:00Z",
    "level": "Warning",
    "operationName": "Microsoft.Compute/virtualMachines/write",
    "eventName": "VM Configuration Changed",
    "resourceId": "/subscriptions/.../resourceGroups/rg-prod/providers/Microsoft.Compute/virtualMachines/vm-prod-01",
    "resourceType": {
      "value": "Microsoft.Compute/virtualMachines",
      "localizedValue": "Virtual Machine"
    },
    "resourceGroup": "rg-prod",
    "status": "Succeeded",
    "description": "Virtual machine configuration was modified",
    "correlationId": "12345678-abcd-1234-abcd-123456789012",
    "category": "Administrative",
    "caller": "user@domain.com"
  }
]
```

### 4. alert_history.json
```json
[
  {
    "alertId": "alert-mgmt-001",
    "name": "High CPU Utilization",
    "severity": "Sev2",
    "alertState": "New",
    "monitorCondition": "Fired",
    "targetResource": "/subscriptions/.../resourceGroups/rg-prod/providers/Microsoft.Compute/virtualMachines/vm-prod-01",
    "targetResourceType": "Microsoft.Compute/virtualMachines",
    "targetResourceGroup": "rg-prod",
    "startDateTime": "2025-08-23T09:15:00Z",
    "lastModifiedDateTime": "2025-08-23T09:15:00Z",
    "monitorService": "Platform",
    "signalType": "Metric",
    "description": "CPU utilization is above 85% for the past 5 minutes",
    "alertRule": "HighCPUAlert-VM-Production",
    "condition": {
      "metric": "Percentage CPU",
      "operator": "GreaterThan",
      "threshold": 85,
      "timeAggregation": "Average",
      "windowSize": "PT5M"
    }
  }
]
```

### 5. metric_alert_rules.json
```json
[
  {
    "id": "/subscriptions/.../resourceGroups/rg-alerts/providers/microsoft.insights/metricAlerts/HighCPUAlert",
    "name": "HighCPUAlert-VM-Production",
    "description": "Alert when CPU exceeds 85%",
    "severity": 2,
    "enabled": true,
    "scopes": [
      "/subscriptions/.../resourceGroups/rg-prod"
    ],
    "evaluationFrequency": "PT1M",
    "windowSize": "PT5M",
    "criteria": {
      "odata.type": "Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria",
      "allOf": [
        {
          "name": "High CPU",
          "metricName": "Percentage CPU",
          "operator": "GreaterThan",
          "threshold": 85,
          "timeAggregation": "Average"
        }
      ]
    },
    "actions": [
      {
        "actionGroupId": "/subscriptions/.../resourceGroups/rg-alerts/providers/microsoft.insights/actiongroups/production-alerts",
        "webHookProperties": {}
      }
    ]
  }
]
```

### 6. maintenance_windows.json
```json
[
  {
    "id": "/subscriptions/.../resourceGroups/rg-maintenance/providers/Microsoft.Maintenance/maintenanceConfigurations/weekly-maintenance",
    "name": "weekly-maintenance",
    "maintenanceScope": "InGuestPatch",
    "startDateTime": "2025-08-24T02:00:00Z",
    "duration": "PT4H",
    "timeZone": "UTC",
    "recurEvery": "Week Sunday"
  }
]
```

### 7. collection_status.json
```json
{
  "subscription_id": "8cff88e3-7424-4403-bccc-d8b4672f4d39",
  "collection_start": "2025-08-23T10:00:00Z",
  "collection_end": "2025-08-23T10:05:00Z",
  "collection_success": true,
  "components": {
    "activity_alerts": {
      "success": true,
      "count": 25,
      "errors": []
    },
    "alert_history": {
      "success": true,
      "count": 45,
      "errors": []
    },
    "metric_rules": {
      "success": true,
      "count": 12,
      "errors": []
    },
    "maintenance_windows": {
      "success": false,
      "count": 0,
      "errors": ["Timeout retrieving maintenance configurations"]
    }
  },
  "total_alerts": 70,
  "api_calls_made": 8,
  "rate_limit_hits": 0,
  "warnings": [
    "Some resources were inaccessible due to permissions"
  ]
}
```

### 8. tenant_summary.json
```json
{
  "tenant_id": "12345678-1234-1234-1234-123456789012",
  "collection_timestamp": "2025-08-23T10:15:00Z",
  "summary": {
    "total_subscriptions": 3,
    "successful_subscriptions": 3,
    "failed_subscriptions": 0,
    "total_alerts": 150,
    "total_alert_rules": 45,
    "collection_duration_seconds": 245
  },
  "subscription_summary": [
    {
      "subscription_id": "8cff88e3-7424-4403-bccc-d8b4672f4d39",
      "name": "Production Subscription",
      "alert_count": 70,
      "collection_success": true
    }
  ]
}
```

## Analysis Output Format

### 9. analysis_results.json
```json
{
  "analysis_timestamp": "2025-08-23T10:20:00Z",
  "analysis_version": "2.0",
  "source_data_timestamp": "2025-08-23T10:15:00Z",
  "analysis_config": {
    "timeframe_days": 7,
    "include_resource_health": true,
    "severity_focus": ["Sev0", "Sev1", "Sev2"]
  },
  "metrics": {
    "total_alerts": 150,
    "severity_breakdown": {
      "Sev0": 2,
      "Sev1": 8,
      "Sev2": 25,
      "Sev3": 65,
      "Sev4": 50
    },
    "alert_state_breakdown": {
      "New": 45,
      "Acknowledged": 30,
      "Closed": 75
    },
    "alert_state_by_severity": {
      "Sev0": {"New": 2, "Acknowledged": 0, "Closed": 0},
      "Sev1": {"New": 3, "Acknowledged": 2, "Closed": 3}
    }
  },
  "top_alert_rules": {
    "HighCPUAlert-VM-Production": 25,
    "DiskSpaceAlert-Storage": 20,
    "MemoryAlert-AppService": 15
  },
  "alert_rule_details": {
    "HighCPUAlert-VM-Production": {
      "rule_name": "HighCPUAlert-VM-Production",
      "alert_count": 25,
      "severities": {"Sev2": 20, "Sev3": 5},
      "states": {"New": 10, "Acknowledged": 5, "Closed": 10},
      "affected_resources": [
        "/subscriptions/.../providers/Microsoft.Compute/virtualMachines/vm-prod-01",
        "/subscriptions/.../providers/Microsoft.Compute/virtualMachines/vm-prod-02"
      ],
      "affected_resource_count": 15,
      "sample_alerts": [
        {
          "alert_id": "alert-001",
          "name": "High CPU Utilization",
          "severity": "Sev2",
          "state": "New",
          "resource": "/subscriptions/.../vm-prod-01",
          "start_time": "2025-08-23T09:15:00Z",
          "description": "CPU utilization is above 85%"
        }
      ]
    }
  },
  "resource_health_alerts": [],
  "recommendations": [
    {
      "type": "noise_reduction",
      "rule_name": "HighCPUAlert-VM-Production",
      "description": "Consider increasing threshold from 85% to 90%",
      "impact": "Reduce ~30% of alerts",
      "priority": "medium"
    }
  ]
}
```

## Version Compatibility

- **Version 1.0**: Initial format specification
- Backward compatibility maintained through version field
- New fields can be added without breaking existing processors
- Deprecated fields marked in documentation before removal

## Error Handling

### Error Format
```json
{
  "error_type": "api_timeout",
  "error_message": "Request timed out after 30 seconds",
  "error_timestamp": "2025-08-23T10:02:30Z",
  "component": "activity_alerts",
  "subscription_id": "8cff88e3-7424-4403-bccc-d8b4672f4d39",
  "retry_attempted": true,
  "retry_count": 2
}
```

## Schema Validation

Each component should validate input/output against JSON schemas to ensure data integrity and compatibility across the pipeline.

## Performance Considerations

- Use streaming JSON parsing for large datasets
- Implement compression for stored data files
- Consider partitioning by date for long-term storage
- Use indexes on commonly queried fields