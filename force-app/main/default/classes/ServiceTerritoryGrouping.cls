/**
* ─────────────────────────────────────────────────────────────────────────────────────────────────┐
* Class to automatically create service territory groups based on territory memberships
* 
* ─────────────────────────────────────────────────────────────────────────────────────────────────
* @author         Patrick Brinksma   <patrick@brinksma.es>
* ─────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
public with sharing class ServiceTerritoryGrouping {

    /* Local properties */

    // Maximum number of service territories allowed in a single group
    private Integer maxNrOfSTsInGroup = 100;
    // Map of Service Territory Id to Name
    private Map<Id, String> serviceTerritoryIdToName = new Map<Id, String>();
    // Map of Service Resource Id to all the Service Territory Ids of which the resource is member of during the optimization horizon
    private Map<Id, List<Id>> srIdToSTIds = new Map<Id, List<Id>>();
    // Map of Service Territory Id to all the Service Resource Ids of its members of during the optimization horizon
    private Map<Id, List<Id>> stIdToSRIds = new Map<Id, List<Id>>();
    // Map of the groups using a counter as group key
    private Map<Integer, Map<Id, String>> groupNameToSTs = new Map<Integer, Map<Id, String>>();
    // Group key 
    private Integer groupCounter = 0;
    // Keep track of which service territories have been processed
    private Set<Id> processedSTIds = new Set<Id>();    
    // Limit the grouping to a defined list of territories
    private List<Id> limitBySTIds;
    // Start of optimization horizon
    private Datetime start;
    // End of optimization horizon
    private Datetime finish;

    /* Constructors */

    public ServiceTerritoryGrouping(Datetime start, Datetime finish) {
        this.start = start;
        this.finish = finish;
    }

    public ServiceTerritoryGrouping(Datetime start, Datetime finish, Integer maxNrOfSTsInGroup) {
        this.start = start;
        this.finish = finish;        
        this.maxNrOfSTsInGroup = maxNrOfSTsInGroup;
    }     

    public ServiceTerritoryGrouping(Datetime start, Datetime finish, List<Id> limitBySTIds) {
        this.start = start;
        this.finish = finish;        
        this.limitBySTIds = limitBySTIds;
    }

    public ServiceTerritoryGrouping(Datetime start, Datetime finish, List<Id> limitBySTIds, Integer maxNrOfSTsInGroup) {
        this.start = start;
        this.finish = finish;        
        this.limitBySTIds = limitBySTIds;
        this.maxNrOfSTsInGroup = maxNrOfSTsInGroup;
    }    

    /* methods */

    /**
     * Main logic to create the service territory groups
     */
    public Map<Integer, Map<Id, String>> createServiceTerritoryGroups(){
        // Retrieve all STMs for the optimizaton horizon
        List<ServiceTerritoryMember> stms = getServiceTerritoryMembers();
        // Get a map of the service territory Id to its name
        convertSTMListToSTIdMap(stms);
        // Create a Map of the Service Territory to its members
        createServiceTerritoryToServiceResourceMap(stms);
        // Create a Map of the Service Resource to its territories
        createServiceResourceToServiceTerritoriesMap(stms);
        // Extract the Territory Groups
        extractServiceTerritoryGroups();
        // Validate if any of the Groups is too large
        validateServiceTerritoryGroups();

        return groupNameToSTs;
    }    

    /**
     * Update Optimization Job with the Territory Groups
     */
    public Boolean updateServiceTerritoryGroupsOnOptimizationJob(String jobName, String spId, Map<Integer, Map<Id, String>> serviceTerritoryGroups){
        List<FSL.ScheduleJobsApi.GroupData> groupList = new List<FSL.ScheduleJobsApi.GroupData>();
        if (!serviceTerritoryGroups.isEmpty()){
            for (Map<Id, String> stIdToName : serviceTerritoryGroups.values()){
                groupList.add(
                    new FSL.ScheduleJobsApi.GroupData(
                        String.valueOf(spId),
                        new List<Id>(stIdToName.keySet())
                    )
                );
            }
            FSL.ScheduleJobsApi.GetJob(jobName).setTerritory(groupList);
            return true;
        } else {
            return false;
        }
    }

    /**
     * Retrieve all Service Territory Member records within the optimization horizon
     * where the Service Resource is active and the Service Territory is active
     * and optionally restrict it by the provided Service Territory Ids
     */
    private List<ServiceTerritoryMember> getServiceTerritoryMembers(){
        String query = '' +
            'select ' + 
            '    Id,' + 
            '    EffectiveStartDate,' +
            '    EffectiveEndDate,' +
            '    ServiceResourceId,' +
            '    ServiceTerritoryId,' +
            '    ServiceTerritory.Name,' +
            '    TerritoryType,' +
            '    ServiceTerritory.FSL__O2_Enabled__c ' +
            'from ' +
            '    ServiceTerritoryMember ' +
            'where ' +
            '    EffectiveStartDate <= :start and ' +
            '    (EffectiveEndDate >= :finish or EffectiveEndDate = null) and ' +
            '   ServiceResource.IsActive = true and ' + 
            '   ServiceTerritory.IsActive = true';

        Map<String, Object> bindVars = new Map<String, Object>{
            'start' => start,
            'finish' => finish
        };

        if (limitBySTIds != null && !limitBySTIds.isEmpty()){
            query += ' and ' +
                ' ServiceTerritoryId in :limitBySTIds';
            bindVars.put('limitBySTIds', limitBySTIds);
        }

        return (List<ServiceTerritoryMember>) Database.queryWithBinds(query, bindVars, accessLevel.SYSTEM_MODE);       
    }    

    /**
     * From the STM data, create the map of service resource to its territories
     */
    private void createServiceResourceToServiceTerritoriesMap(List<ServiceTerritoryMember> stms){
        srIdToSTIds = new Map<Id, List<Id>>();
        for (ServiceTerritoryMember stm : stms){
            List<Id> stIds = srIdToSTIds.get(stm.ServiceResourceId);
            if (stIds == null){
                stIds = new List<Id>();
            }
            stIds.add(stm.ServiceTerritoryId);
            srIdToSTIds.put(stm.ServiceResourceId, stIds);
        }
    }

    /**
     * From the STM data, create the map of service territory to its members
     */
    private void createServiceTerritoryToServiceResourceMap(List<ServiceTerritoryMember> stms){
        stIdToSRIds = new Map<Id, List<Id>>();
        for (ServiceTerritoryMember stm : stms){
            List<Id> srIds = stIdToSRIds.get(stm.ServiceTerritoryId);
            if (srIds == null){
                srIds = new List<Id>();
            }
            srIds.add(stm.ServiceResourceId);
            stIdToSRIds.put(stm.ServiceTerritoryId, srIds);
        }
    } 

    /**
     * Main loop through the territories to create groups
     */
    private void extractServiceTerritoryGroups(){
        // Loop through all service territories
        for (Id stId : stIdToSRIds.keySet()){
            if (!processedSTIds.contains(stId)){
                // Get all Service Resources that are member of the territory
                List<Id> srIds = stIdToSRIds.get(stId);
                Set<Id> stIdsInGroup = new Set<Id>();
                // For each Service Resource make sure all the Service Territories 
                // are added of which the Service Resource is a member
                for (Id srId : srIds){
                    List<Id> stIds = srIdToSTIds.get(srId);
                    if (stIds != null){
                        stIdsInGroup.addAll(stIds);
                    }
                }
                if (!stIdsInGroup.isEmpty()){
                    // Validate if any of the STs was already processed
                    // if so the service territories need to be added to that group
                    Boolean stInExistingGroup = false;
                    for (Id stIdInGroup : stIdsInGroup){
                        if (processedSTIds.contains(stIdInGroup)){
                            // Check to which group the ST belongs to
                            for (Integer i=0; i < groupCounter; i++){
                                Set<Id> stIdsInThisGroup = groupNameToSTs.get(i).keySet();
                                if (stIdsInThisGroup.contains(stIdInGroup)){
                                    stIdsInThisGroup.addAll(stIdsInGroup);
                                    groupNameToSTs.put(i, convertSTIdsToMapIdToName(stIdsInThisGroup));
                                    stInExistingGroup = true;
                                    break;
                                }
                            }
                        }
                    }
                    if (!stInExistingGroup){
                        groupNameToSTs.put(groupCounter, convertSTIdsToMapIdToName(stIdsInGroup));
                        groupCounter++;
                    }
                    processedSTIds.addAll(stIdsInGroup);
                }
            }
        }
    }

    /**
     * Validate if any of the groups exceed the nr of max territories
     */    
    private void validateServiceTerritoryGroups(){
        for (Map<Id, String> stIdsInGroup : groupNameToSTs.values()){
            if (stIdsInGroup.size() > maxNrOfSTsInGroup){
                throw new ServiceTerritoryGroupException(
                    'Service Territory Group has more than ' + maxNrOfSTsInGroup +' territories. The territory Ids are: ' + 
                    String.join(stIdsInGroup.keySet(), ',')
                );
            }
        }
    }

    /**
     * Creates a map of Service Territory Id to Name, which is used to 
     * provide the name of the Service Territory in the output for 
     * validation purposes
     */    
    private void convertSTMListToSTIdMap(List<ServiceTerritoryMember> stms){
        for (ServiceTerritoryMember stm : stms){
            serviceTerritoryIdToName.put(stm.ServiceTerritoryId, stm.ServiceTerritory.Name);
        }
    }

    private Map<Id, String> convertSTIdsToMapIdToName(Set<Id> stIds){
        Map<Id, String> stIdToName = new Map<Id, String>();
        for (Id stId : stIds){
            stIdToName.put(stId, serviceTerritoryIdToName.get(stId));
        }    
        return  stIdToName;   
    }

    /**
     *  Custom Exception class to throw exceptions related to this process
     */
    public class ServiceTerritoryGroupException extends Exception{}          

}