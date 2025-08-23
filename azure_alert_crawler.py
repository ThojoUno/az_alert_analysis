#!/usr/bin/env python3
"""
Azure Alert Data Crawler

This script collects alert data from Azure APIs and stores it in standardized JSON format
for processing by the Azure Alert Analyzer.

Author: Claude AI Assistant
Version: 1.0
"""

import json
import os
import subprocess
import sys
from datetime import datetime, timedelta
from concurrent.futures import ThreadPoolExecutor, as_completed
import logging
import argparse
import time
from typing import Dict, List, Any, Optional, Tuple
import uuid


class AzureAlertCrawler:
    """
    Collects alert data from Azure subscriptions and stores in standardized format.
    """
    
    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.logger = self._setup_logging()
        self.output_dir = None
        self.tenant_id = None
        self.stats = {
            'start_time': datetime.now(),
            'subscriptions_processed': 0,
            'subscriptions_successful': 0,
            'subscriptions_failed': 0,
            'total_alerts_collected': 0,
            'api_calls_made': 0,
            'rate_limit_hits': 0
        }
    
    def _setup_logging(self) -> logging.Logger:
        """Setup logging configuration."""
        logger = logging.getLogger('azure_alert_crawler')
        logger.setLevel(logging.INFO)
        
        if not logger.handlers:
            handler = logging.StreamHandler()
            formatter = logging.Formatter(
                '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
            )
            handler.setFormatter(formatter)
            logger.addHandler(handler)
        
        return logger
    
    def _run_az_command(self, command: List[str], timeout: int = 30) -> Tuple[bool, Any]:
        """
        Execute Azure CLI command with timeout and error handling.
        
        Args:
            command: Azure CLI command as list
            timeout: Command timeout in seconds
            
        Returns:
            Tuple of (success, result_or_error)
        """
        try:
            self.stats['api_calls_made'] += 1
            self.logger.debug(f"Executing: {' '.join(command)}")
            
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                timeout=timeout,
                check=True
            )
            
            if result.stdout.strip():
                return True, json.loads(result.stdout)
            else:
                return True, []
                
        except subprocess.TimeoutExpired:
            self.logger.warning(f"Command timed out after {timeout}s: {' '.join(command)}")
            return False, f"Timeout after {timeout}s"
        
        except subprocess.CalledProcessError as e:
            error_msg = e.stderr.strip() if e.stderr else str(e)
            if "rate limit" in error_msg.lower():
                self.stats['rate_limit_hits'] += 1
                self.logger.warning(f"Rate limit hit: {error_msg}")
                time.sleep(5)  # Wait before retry
            else:
                self.logger.error(f"Command failed: {error_msg}")
            return False, error_msg
        
        except json.JSONDecodeError as e:
            self.logger.error(f"Failed to parse JSON response: {e}")
            return False, f"JSON decode error: {e}"
        
        except Exception as e:
            self.logger.error(f"Unexpected error: {e}")
            return False, f"Unexpected error: {e}"
    
    def _check_azure_login(self) -> bool:
        """Check if user is logged into Azure CLI."""
        success, result = self._run_az_command(['az', 'account', 'show'])
        if success:
            self.tenant_id = result.get('tenantId')
            self.logger.info(f"Logged into Azure tenant: {self.tenant_id}")
            return True
        else:
            self.logger.error("Not logged into Azure CLI. Please run 'az login'")
            return False
    
    def _get_subscriptions(self) -> List[Dict[str, Any]]:
        """Get list of accessible subscriptions in current tenant."""
        success, subscriptions = self._run_az_command([
            'az', 'account', 'list',
            '--query', '[].{id:id, name:name, state:state, tenantId:tenantId}',
            '-o', 'json'
        ])
        
        if not success:
            self.logger.error(f"Failed to get subscriptions: {subscriptions}")
            return []
        
        # Filter to current tenant only
        tenant_subscriptions = [
            sub for sub in subscriptions 
            if sub.get('tenantId') == self.tenant_id and sub.get('state') == 'Enabled'
        ]
        
        self.logger.info(f"Found {len(tenant_subscriptions)} enabled subscriptions in current tenant")
        return tenant_subscriptions
    
    def _collect_subscription_info(self, subscription: Dict[str, Any], sub_dir: str) -> bool:
        """Collect and store subscription information."""
        try:
            # Get resource groups
            success, resource_groups = self._run_az_command([
                'az', 'group', 'list',
                '--subscription', subscription['id'],
                '--query', '[].name',
                '-o', 'json'
            ], timeout=self.config['timeout_seconds'])
            
            subscription_info = {
                'subscription_id': subscription['id'],
                'subscription_name': subscription['name'],
                'tenant_id': subscription['tenantId'],
                'state': subscription['state'],
                'collection_timestamp': datetime.now().isoformat() + 'Z',
                'resource_groups': resource_groups if success else []
            }
            
            with open(os.path.join(sub_dir, 'subscription_info.json'), 'w') as f:
                json.dump(subscription_info, f, indent=2)
            
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to collect subscription info: {e}")
            return False
    
    def _collect_activity_alerts(self, subscription_id: str, sub_dir: str) -> Tuple[bool, int]:
        """Collect activity log alerts for subscription."""
        try:
            start_time = (datetime.now() - timedelta(days=self.config['days_back'])).isoformat()
            
            success, activity_data = self._run_az_command([
                'az', 'monitor', 'activity-log', 'list',
                '--subscription', subscription_id,
                '--start-time', start_time,
                '--query', '''[].{
                    id: eventDataId,
                    timestamp: eventTimestamp,
                    level: level,
                    operationName: operationName.localizedValue,
                    eventName: eventName.localizedValue,
                    resourceId: resourceId,
                    resourceType: resourceType,
                    resourceGroup: resourceGroupName,
                    status: status.localizedValue,
                    description: description,
                    correlationId: correlationId,
                    category: category.localizedValue,
                    caller: caller
                }''',
                '-o', 'json'
            ], timeout=self.config['timeout_seconds'])
            
            if success:
                # Filter for alert-relevant events
                alert_events = [
                    event for event in activity_data
                    if event.get('level') in ['Critical', 'Error', 'Warning', 'Informational']
                ]
                
                with open(os.path.join(sub_dir, 'activity_alerts.json'), 'w') as f:
                    json.dump(alert_events, f, indent=2)
                
                return True, len(alert_events)
            else:
                # Create empty file on failure
                with open(os.path.join(sub_dir, 'activity_alerts.json'), 'w') as f:
                    json.dump([], f)
                return False, 0
                
        except Exception as e:
            self.logger.error(f"Failed to collect activity alerts: {e}")
            return False, 0
    
    def _collect_alert_history(self, subscription_id: str, sub_dir: str) -> Tuple[bool, int]:
        """Collect alert management history for subscription."""
        try:
            # Query alert management API
            success, alert_data = self._run_az_command([
                'az', 'rest',
                '--method', 'GET',
                '--uri', f'https://management.azure.com/subscriptions/{subscription_id}/providers/Microsoft.AlertsManagement/alerts',
                '--uri-parameters', f'api-version=2019-05-05&timeRange=7d',
                '--query', '''value[].{
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
                }''',
                '-o', 'json'
            ], timeout=self.config['timeout_seconds'])
            
            if success:
                with open(os.path.join(sub_dir, 'alert_history.json'), 'w') as f:
                    json.dump(alert_data, f, indent=2)
                return True, len(alert_data)
            else:
                with open(os.path.join(sub_dir, 'alert_history.json'), 'w') as f:
                    json.dump([], f)
                return False, 0
                
        except Exception as e:
            self.logger.error(f"Failed to collect alert history: {e}")
            return False, 0
    
    def _collect_metric_alert_rules(self, subscription_id: str, sub_dir: str) -> Tuple[bool, int]:
        """Collect metric alert rules for subscription."""
        try:
            success, rules_data = self._run_az_command([
                'az', 'monitor', 'metrics', 'alert', 'list',
                '--subscription', subscription_id,
                '-o', 'json'
            ], timeout=self.config['timeout_seconds'])
            
            if success:
                with open(os.path.join(sub_dir, 'metric_alert_rules.json'), 'w') as f:
                    json.dump(rules_data, f, indent=2)
                return True, len(rules_data)
            else:
                with open(os.path.join(sub_dir, 'metric_alert_rules.json'), 'w') as f:
                    json.dump([], f)
                return False, 0
                
        except Exception as e:
            self.logger.error(f"Failed to collect metric alert rules: {e}")
            return False, 0
    
    def _collect_maintenance_windows(self, subscription_id: str, sub_dir: str) -> Tuple[bool, int]:
        """Collect maintenance windows for subscription."""
        if not self.config.get('include_maintenance', True):
            return True, 0
        
        try:
            success, maintenance_data = self._run_az_command([
                'az', 'rest',
                '--method', 'GET',
                '--uri', f'https://management.azure.com/subscriptions/{subscription_id}/providers/Microsoft.Maintenance/maintenanceConfigurations',
                '--uri-parameters', 'api-version=2021-05-01',
                '--query', '''value[].{
                    id: id,
                    name: name,
                    maintenanceScope: properties.maintenanceScope,
                    startDateTime: properties.maintenanceWindow.startDateTime,
                    duration: properties.maintenanceWindow.duration,
                    timeZone: properties.maintenanceWindow.timeZone,
                    recurEvery: properties.maintenanceWindow.recurEvery
                }''',
                '-o', 'json'
            ], timeout=self.config['timeout_seconds'])
            
            if success:
                with open(os.path.join(sub_dir, 'maintenance_windows.json'), 'w') as f:
                    json.dump(maintenance_data, f, indent=2)
                return True, len(maintenance_data)
            else:
                with open(os.path.join(sub_dir, 'maintenance_windows.json'), 'w') as f:
                    json.dump([], f)
                return False, 0
                
        except Exception as e:
            self.logger.error(f"Failed to collect maintenance windows: {e}")
            return False, 0
    
    def _collect_subscription_data(self, subscription: Dict[str, Any]) -> Dict[str, Any]:
        """Collect all data for a single subscription."""
        subscription_id = subscription['id']
        subscription_name = subscription['name']
        
        self.logger.info(f"Processing subscription: {subscription_name}")
        
        # Create subscription directory
        safe_name = "".join(c for c in subscription_name if c.isalnum() or c in (' ', '-', '_')).rstrip()
        safe_name = safe_name.replace(' ', '_')
        sub_dir_name = f"subscription_{subscription_id[:8]}_{safe_name}"
        sub_dir = os.path.join(self.output_dir, 'subscriptions', sub_dir_name)
        os.makedirs(sub_dir, exist_ok=True)
        
        # Collection status tracking
        collection_status = {
            'subscription_id': subscription_id,
            'collection_start': datetime.now().isoformat() + 'Z',
            'collection_end': None,
            'collection_success': True,
            'components': {},
            'total_alerts': 0,
            'api_calls_made': 0,
            'rate_limit_hits': 0,
            'warnings': []
        }
        
        # Set subscription context
        subprocess.run(['az', 'account', 'set', '--subscription', subscription_id], 
                      capture_output=True, check=True)
        
        try:
            # Collect subscription info
            success = self._collect_subscription_info(subscription, sub_dir)
            collection_status['components']['subscription_info'] = {'success': success, 'errors': [] if success else ['Failed to collect subscription info']}
            
            # Collect activity alerts
            success, count = self._collect_activity_alerts(subscription_id, sub_dir)
            collection_status['components']['activity_alerts'] = {
                'success': success,
                'count': count,
                'errors': [] if success else ['Failed to collect activity alerts']
            }
            if success:
                collection_status['total_alerts'] += count
            
            # Collect alert history
            success, count = self._collect_alert_history(subscription_id, sub_dir)
            collection_status['components']['alert_history'] = {
                'success': success,
                'count': count,
                'errors': [] if success else ['Failed to collect alert history']
            }
            if success:
                collection_status['total_alerts'] += count
            
            # Collect metric alert rules
            success, count = self._collect_metric_alert_rules(subscription_id, sub_dir)
            collection_status['components']['metric_rules'] = {
                'success': success,
                'count': count,
                'errors': [] if success else ['Failed to collect metric alert rules']
            }
            
            # Collect maintenance windows
            success, count = self._collect_maintenance_windows(subscription_id, sub_dir)
            collection_status['components']['maintenance_windows'] = {
                'success': success,
                'count': count,
                'errors': [] if success else ['Failed to collect maintenance windows']
            }
            
        except Exception as e:
            self.logger.error(f"Failed to process subscription {subscription_name}: {e}")
            collection_status['collection_success'] = False
            collection_status['warnings'].append(f"Processing failed: {e}")
        
        finally:
            collection_status['collection_end'] = datetime.now().isoformat() + 'Z'
            
            # Save collection status
            with open(os.path.join(sub_dir, 'collection_status.json'), 'w') as f:
                json.dump(collection_status, f, indent=2)
        
        return {
            'subscription_id': subscription_id,
            'name': subscription_name,
            'alert_count': collection_status['total_alerts'],
            'collection_success': collection_status['collection_success'],
            'directory': sub_dir_name
        }
    
    def collect_all_data(self) -> bool:
        """Main method to collect data from all subscriptions."""
        self.logger.info("Starting Azure Alert Data Collection")
        
        # Check Azure login
        if not self._check_azure_login():
            return False
        
        # Get subscriptions
        subscriptions = self._get_subscriptions()
        if not subscriptions:
            self.logger.error("No accessible subscriptions found")
            return False
        
        # Apply debug limit if configured
        if self.config.get('debug_mode', False):
            debug_limit = self.config.get('debug_subscription_limit', 3)
            subscriptions = subscriptions[:debug_limit]
            self.logger.info(f"Debug mode: limiting to {len(subscriptions)} subscriptions")
        
        # Create output directory
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        self.output_dir = os.path.join(os.getcwd(), f'azure_alerts_data_{timestamp}')
        os.makedirs(self.output_dir, exist_ok=True)
        os.makedirs(os.path.join(self.output_dir, 'subscriptions'), exist_ok=True)
        
        self.logger.info(f"Output directory: {self.output_dir}")
        
        # Collect data from subscriptions
        subscription_results = []
        
        if self.config.get('parallel_processing', True):
            # Parallel processing
            max_workers = min(self.config.get('max_workers', 3), len(subscriptions))
            with ThreadPoolExecutor(max_workers=max_workers) as executor:
                future_to_subscription = {
                    executor.submit(self._collect_subscription_data, sub): sub
                    for sub in subscriptions
                }
                
                for future in as_completed(future_to_subscription):
                    try:
                        result = future.result()
                        subscription_results.append(result)
                        self.stats['subscriptions_processed'] += 1
                        
                        if result['collection_success']:
                            self.stats['subscriptions_successful'] += 1
                            self.stats['total_alerts_collected'] += result['alert_count']
                        else:
                            self.stats['subscriptions_failed'] += 1
                            
                    except Exception as e:
                        self.logger.error(f"Subscription processing failed: {e}")
                        self.stats['subscriptions_failed'] += 1
        else:
            # Sequential processing
            for subscription in subscriptions:
                try:
                    result = self._collect_subscription_data(subscription)
                    subscription_results.append(result)
                    self.stats['subscriptions_processed'] += 1
                    
                    if result['collection_success']:
                        self.stats['subscriptions_successful'] += 1
                        self.stats['total_alerts_collected'] += result['alert_count']
                    else:
                        self.stats['subscriptions_failed'] += 1
                        
                except Exception as e:
                    self.logger.error(f"Subscription processing failed: {e}")
                    self.stats['subscriptions_failed'] += 1
        
        # Generate metadata and tenant summary
        self._generate_metadata(subscription_results)
        self._generate_tenant_summary(subscription_results)
        
        # Final statistics
        duration = (datetime.now() - self.stats['start_time']).total_seconds()
        self.logger.info(f"Collection completed in {duration:.1f}s")
        self.logger.info(f"Processed {self.stats['subscriptions_processed']} subscriptions")
        self.logger.info(f"Successful: {self.stats['subscriptions_successful']}, Failed: {self.stats['subscriptions_failed']}")
        self.logger.info(f"Total alerts collected: {self.stats['total_alerts_collected']}")
        self.logger.info(f"Output directory: {self.output_dir}")
        
        return self.stats['subscriptions_successful'] > 0
    
    def _generate_metadata(self, subscription_results: List[Dict[str, Any]]) -> None:
        """Generate collection metadata file."""
        duration = (datetime.now() - self.stats['start_time']).total_seconds()
        
        metadata = {
            'version': '1.0',
            'collection_timestamp': datetime.now().isoformat() + 'Z',
            'tenant_id': self.tenant_id,
            'collection_config': self.config,
            'subscriptions_processed': self.stats['subscriptions_processed'],
            'subscriptions_successful': self.stats['subscriptions_successful'],
            'subscriptions_failed': self.stats['subscriptions_failed'],
            'total_alerts_collected': self.stats['total_alerts_collected'],
            'collection_duration_seconds': int(duration),
            'api_calls_made': self.stats['api_calls_made'],
            'rate_limit_hits': self.stats['rate_limit_hits']
        }
        
        with open(os.path.join(self.output_dir, 'metadata.json'), 'w') as f:
            json.dump(metadata, f, indent=2)
    
    def _generate_tenant_summary(self, subscription_results: List[Dict[str, Any]]) -> None:
        """Generate tenant-level summary file."""
        tenant_summary = {
            'tenant_id': self.tenant_id,
            'collection_timestamp': datetime.now().isoformat() + 'Z',
            'summary': {
                'total_subscriptions': len(subscription_results),
                'successful_subscriptions': self.stats['subscriptions_successful'],
                'failed_subscriptions': self.stats['subscriptions_failed'],
                'total_alerts': self.stats['total_alerts_collected'],
                'collection_duration_seconds': int((datetime.now() - self.stats['start_time']).total_seconds())
            },
            'subscription_summary': subscription_results
        }
        
        with open(os.path.join(self.output_dir, 'tenant_summary.json'), 'w') as f:
            json.dump(tenant_summary, f, indent=2)


def main():
    """Main entry point for the Azure Alert Crawler."""
    parser = argparse.ArgumentParser(description='Azure Alert Data Crawler')
    parser.add_argument('--days-back', type=int, default=7, 
                       help='Number of days back to collect alerts (default: 7)')
    parser.add_argument('--timeout', type=int, default=30,
                       help='API call timeout in seconds (default: 30)')
    parser.add_argument('--no-maintenance', action='store_true',
                       help='Skip maintenance window collection')
    parser.add_argument('--debug', action='store_true',
                       help='Enable debug mode (limit to 3 subscriptions)')
    parser.add_argument('--max-workers', type=int, default=3,
                       help='Maximum parallel workers (default: 3)')
    parser.add_argument('--sequential', action='store_true',
                       help='Use sequential processing instead of parallel')
    parser.add_argument('--verbose', '-v', action='store_true',
                       help='Enable verbose logging')
    
    args = parser.parse_args()
    
    # Configure logging
    if args.verbose:
        logging.getLogger('azure_alert_crawler').setLevel(logging.DEBUG)
    
    # Build configuration
    config = {
        'days_back': args.days_back,
        'timeout_seconds': args.timeout,
        'include_maintenance': not args.no_maintenance,
        'debug_mode': args.debug,
        'debug_subscription_limit': 3,
        'parallel_processing': not args.sequential,
        'max_workers': args.max_workers
    }
    
    # Create and run crawler
    crawler = AzureAlertCrawler(config)
    success = crawler.collect_all_data()
    
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()