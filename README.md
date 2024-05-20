# Service Territory Grouping for Salesforce Field Service Optimization 

This repository contains Apex code to extract the Service Territory groupings to be update a Scheduled Optimization Job for the Enhanced Scheduling & Optimization Engine.

## Disclaimer
IMPORTANT: This code is not intended to be deployed directly to a Salesforce production environment, but to be used as an example. This is not a Salesforce product and is not officially supported by Salesforce.

## How To Use

With the Apex Class ServiceTerritoryGrouping you can create groups of service territories that have to be combined in a single Optimization Request so that all the availability and non-availability of the service resources is included. If you have a dynamic territory set up and a lot of changes in territory memberships you can automate setting the right service territory groups for scheduled optimization jobs using the new ```FSL.ScheduleJobsApi.GetJob``` method.

Example (also available in scripts/apex):
```
Integer horizonInDays = 31;                                     // Max values: LS = 21 days, ES&O = 31 days
Datetime start = System.now();                                  // Start of the optimization horizon
Datetime finish = start.addDays(horizonInDays);                 // End of the optimization horizon

// Group STs accordingto ST membership
ServiceTerritoryGrouping g = new ServiceTerritoryGrouping(start, finish);
Map<Integer, Map<Id, String>> groupNameToSTs = g.createServiceTerritoryGroups();

// Debug groups for validation
System.debug(JSON.serializePretty(groupNameToSTs));

// Get the Scheduling Policy to be used for the groups
Id spId = [select Id from FSL__Scheduling_Policy__c where Name = 'Customer First'].Id;

// Update optimizaiton scheduled job with the new groups
g.updateServiceTerritoryGroupsOnOptimizationJob('ESO', spId, groupNameToSTs);
```

Additionally you can set the maximum number of service territories in a single group and/or restrict the selection by a list of Service Territory Ids. This is recommended when processing larger amounts of data, and for example whereby the optimization jobs are restricted to specific areas.
