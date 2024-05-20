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
