/*
Action Plans v4
David Schach 2021

Action Plans v3
Force.com Labs 2011
http://appexchange.salesforce.com/listingDetail?listingId=a0N30000003HcINEA0

BSD 3-Clause License

Copyright (c) 2021, salesforce.com, inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/
global without sharing class ActionPlansTriggerHandlers {

	/**
	 * Global so that if in managed package, these methods are the only ones available
	 */
	global static void actionPlansSObjectTriggerHandler(String sObjectName){
		actionPlansSObjectTriggerHandler(Trigger.new, Trigger.old, Trigger.newMap, Trigger.oldMap, Trigger.operationType, sObjectName);
	}

    global static void actionPlansSObjectTriggerHandler(List<SObject> newRecords, List<SObject> oldRecords, Map<Id,SObject> newRecordsMap, Map<Id,SObject> oldRecordsMap, System.TriggerOperation triggerEvent, String sObjectName){

		//System.debug('In ' + sObjectName + ' ' + triggerEvent.name());

		String relationshipName = null;

		switch on triggerEvent {

			when BEFORE_DELETE {
				relationshipName = getRelationshipName((Id)oldRecordsMap.values()[0].get('Id'));
			}
			when AFTER_UNDELETE {
				relationshipName = getRelationshipName((Id)newRecordsMap.values()[0].get('Id'));
			}
			when else {
				return;
			}
		}
		if(relationshipName == null) { return; }

		//Delete related action plans
		switch on triggerEvent {

			when BEFORE_DELETE {

				Set<Id>  apIds  = new Set<Id>();
				List<ActionPlan__c> deletePermenantly_apIds= new List<ActionPlan__c>();

				// Query Action Plans to delete in recycle bin
				String deleteQueryString = 'SELECT Id, Name FROM ActionPlan__c WHERE ' +
				                           relationshipName + ' IN :oldRecords AND isDeleted = true ALL ROWS';
				deletePermenantly_apIds = Database.query(deleteQueryString);

				if ( deletePermenantly_apIds.size() >0 ){
					Database.emptyRecycleBin(deletePermenantly_apIds);
				}

				deleteQueryString = 'SELECT Id FROM ActionPlan__c WHERE ' + relationshipName + ' IN :oldRecords';
				List<ActionPlan__c> apList = Database.query(deleteQueryString);
				for( ActionPlan__c ap : apList ){
					apIds.add( ap.Id );
				}

				if ( apIds.size() > 0 ){
					ActionPlansBatchDelete aPBatch = new ActionPlansBatchDelete(apIds);
					Database.ExecuteBatch( aPBatch );
				}
			}

			//Undelete related action plans
			when AFTER_UNDELETE {
				String afterUndeleteQuery = 'SELECT Id FROM ActionPlan__c WHERE ' + relationshipName + ' IN :newRecords ALL ROWS';
				List<ActionPlan__c> aPs = Database.query(afterUndeleteQuery);

				try{
					if(ActionPlansTestUtilities.forceError){
						//throw dmlException
						insert new Contact();
					}
					Database.undelete( aPs, false);
				} catch ( Dmlexception e ){
					for (SObject c : newRecords){
						c.addError(System.Label.ap_RelObjUndeleteError);
					}
				}
			}
		}
	}

	public static void triggerHandler_ActionPlan(List<ActionPlan__c> newRecords, List<ActionPlan__c> oldRecords, Map<Id,ActionPlan__c> newRecordsMap, Map<Id,ActionPlan__c> oldRecordsMap, System.TriggerOperation triggerEvent){

		//System.debug('In ActionPlan__c ' + triggerEvent.name());

		switch on triggerEvent {

			when BEFORE_INSERT {

				Id defaultTaskRTId = ActionPlansUtilities.getDefaultTaskRecordTypeId();

				Set<Id> aptemplates = new Set<Id>();
				for(ActionPlan__c ap : newRecords){
					if(ap.Action_Plan_Template__c != null && ap.TaskRecordTypeID__c == null){
						aptemplates.add(ap.Action_Plan_Template__c);
					}
					else if(ap.Action_Plan_Template__c == null && ap.TaskRecordTypeID__c == null){
						ap.TaskRecordTypeID__c = defaultTaskRTId;
					}
				}
				if(!aptemplates.isEmpty()){
					Map<Id, ActionPlanTemplate__c> templateMap = new Map<Id, ActionPlanTemplate__c>([SELECT Id, TaskRecordTypeID__c FROM ActionPlanTemplate__c WHERE Id IN :aptemplates]);

					for(ActionPlan__c ap : newRecords){
						if(ap.TaskRecordTypeID__c == null || !(ap.TaskRecordTypeID__c instanceOf Id)){

							if(templateMap.containsKey(ap.Action_Plan_Template__c)){
								ap.TaskRecordTypeID__c = templateMap.get(ap.Action_Plan_Template__c).TaskRecordTypeID__c;
							} else {
								ap.TaskRecordTypeID__c = defaultTaskRTId;
							}
						}
					}
				}
				validateActionPlans(newRecords);
			}

			when BEFORE_UPDATE {
				validateActionPlans(newRecords);
			}

			when AFTER_UPDATE {
				Set<Id> actionPlanNewNames = new Set<Id>();
				for(ActionPlan__c ap : newRecords){
					if(ap.Name != oldRecordsMap.get(ap.Id).Name){
						actionPlanNewNames.add(ap.id);
					}
				}
				if(!actionPlanNewNames.isEmpty()){
					List<APTaskTemplate__c> templateTasks = [SELECT Id, Name FROM APTaskTemplate__c WHERE Action_Plan__c IN :actionPlanNewNames];
					for(APTaskTemplate__c a : templateTasks){
						a.Name = null;
					}
					// no permissions check because trigger handler must run in system mode
					update templateTasks;
				}
			}

			//Execution when an Action Plan is deleted: delete all asociated Tasks
			when BEFORE_DELETE {
				Set<Id> taskIds= new Set<Id>();
				if ( !System.isBatch() && !System.isFuture()){
					// if action plan is deleted, delete all tasks associated with it
					for( Task ap : [SELECT Id FROM Task WHERE IsClosed = false AND TaskAPTaskTemplate__r.Action_Plan__c IN :oldRecordsMap.keyset() ] ){
						taskIds.add( ap.Id );
					}
					if( !taskIds.isEmpty() ){
						// Run a future method
						ActionPlansTaskTriggerUtilities.deleteTasks( taskIds );
					}
				} else {
					// no permissions check because trigger handler must run in system mode
					delete [SELECT Id FROM Task WHERE IsClosed = false AND TaskAPTaskTemplate__r.Action_Plan__c IN :oldRecordsMap.keyset() ];
				}
			}

			when AFTER_UNDELETE {

				//get Id of all deleted Action Plan Task Templates
				Map<Id, APTaskTemplate__c> map_APTasks = new Map<Id, APTaskTemplate__c>([SELECT Id, Action_Plan__c
										FROM APTaskTemplate__c WHERE Action_Plan__c IN :newRecordsMap.keyset() ALL ROWS ]);

				//get all tasks asociated to this APTasks
				List<Task> taskList = [SELECT Id, TaskAPTaskTemplate__c, IsDeleted
										FROM Task
										WHERE TaskAPTaskTemplate__c IN :map_APTasks.keySet() AND IsDeleted = true ALL ROWS ];

				if (!taskList.isEmpty()){
					List<Database.UndeleteResult> unDel_results = Database.undelete( taskList, false );
				}
			}
		}
	}

	public static void triggerHandler_ActionPlanTaskTemplate(List<APTaskTemplate__c> newRecords, List<APTaskTemplate__c> oldRecords, Map<Id, APTaskTemplate__c> newRecordsMap, Map<Id, APTaskTemplate__c> oldRecordsMap, System.TriggerOperation triggerEvent){

		//System.debug('In APTaskTemplate__c ' + triggerEvent.name());

		switch on triggerEvent {

			when BEFORE_INSERT, BEFORE_UPDATE {

				for( APTaskTemplate__c a : newRecords ){
					a.IsClosed__c = ActionPlansUtilities.getClosedTaskStatuses().contains(a.Status__c);
					if(a.User__c == null){
						a.User__c = UserInfo.getUserId();
					}
				}

				Set<Id> apIDs = new Set<Id>();
				String aptPrefix = ActionPlansUtilities.getObjectKeyPrefix('APTaskTemplate__c');

				for(APTaskTemplate__c apt : newRecords){

					if(oldRecords == null || (apt.Name == null  || apt.Name.startsWithIgnoreCase(aptPrefix) || (oldRecords != null && apt.Subject__c != oldRecordsMap.get(apt.Id).Subject__c)) || !apt.Name.endsWithIgnoreCase(apt.Subject__c) ){
						apIDs.add(apt.Action_Plan__c);
					}
				}
				if(!apIDs.isEmpty()){
					Map<Id, ActionPlan__c> nameMap = new Map<Id, ActionPlan__c>([SELECT Id, Name FROM ActionPlan__c WHERE Id IN :apIDs]);

					Integer taskTemplateNameLength	= APTaskTemplate__c.Name.getDescribe().getLength();
					for(APTaskTemplate__c apt : newRecords){
						if(nameMap.containsKey(apt.Action_Plan__c)){
							String apName = nameMap.get(apt.Action_Plan__c).Name;
							String newSubject = apName + ' - ' + apt.Subject__c;
							apt.Name = ActionPlansUtilities.actionPlanSubjectToName(newSubject, taskTemplateNameLength);
						}
					}
				}

				for( APTaskTemplate__c a : newRecords ){
					if(a.Reminder__c && String.isBlank(a.Minutes_Reminder__c)){
						a.Minutes_Reminder__c = ActionPlansUtilities.getDefaultReminderMinutes();
					} else if( !a.Reminder__c ){
						a.Minutes_Reminder__c = null;
					}
				}
			}

			when BEFORE_DELETE {
				try{
					Database.delete([SELECT Id FROM Task WHERE TaskAPTaskTemplate__c IN :oldRecordsMap.keyset() AND IsClosed = false]);
				} catch (Exception e){
					System.debug('Error when deleting Tasks related to APTaskTemplate');
				}
			}

			when AFTER_UNDELETE {

				List<Task> aP_tasks = [SELECT Id FROM Task WHERE TaskAPTaskTemplate__c IN :newRecordsMap.keyset() AND isDeleted = true ALL ROWS ];

				try{
					Database.undelete (aP_tasks);
				} catch ( Dmlexception e ){
					for (APTaskTemplate__c a: newRecords){
						a.addError(System.Label.ap_Error + ' ' + Task.sObjectType.getDescribe().getLabel() + ' ' + triggerEvent + ': ' + e);
					}
				}
			}
		}
	}

	public static void triggerHandler_ActionPlanTemplate(List<ActionPlanTemplate__c> newRecords, List<ActionPlanTemplate__c> oldRecords, Map<Id,ActionPlanTemplate__c> oldRecordsMap, System.TriggerOperation triggerEvent){
		switch on triggerEvent {

			when BEFORE_INSERT {
				Id defaultTaskRTId = ActionPlansUtilities.getDefaultTaskRecordTypeId();

				for(ActionPlanTemplate__c apt : newRecords){
					if(apt.TaskRecordTypeID__c == null || !(apt.TaskRecordTypeID__c instanceOf Id)){
						apt.TaskRecordTypeID__c = defaultTaskRTId;
					}
				}
			}

			when AFTER_UPDATE {
				Set<Id> changedNames = new Set<Id>();
				for(ActionPlanTemplate__c apt : newRecords){
					if(apt.Name != oldRecordsMap.get(apt.Id).Name){
						changedNames.add(apt.Id);
					}
				}
				if(!changedNames.isEmpty()) {
					List<APTTaskTemplate__c> templateTasks = [SELECT Id, Name FROM APTTaskTemplate__c WHERE Action_Plan_Template__c IN :changedNames];
					for(APTTaskTemplate__c a : templateTasks){
						a.Name = null;
					}
					update templateTasks;
				}
			}
		}
	}

	public static void triggerHandler_ActionPlanTemplateTaskTemplate(List<APTTaskTemplate__c> newRecords, List<APTTaskTemplate__c> oldRecords, Map<Id, APTTaskTemplate__c> oldRecordsMap, System.TriggerOperation triggerEvent){

		//System.debug('In APTTaskTemplate__c ' + triggerEvent.name());

		switch on triggerEvent {

			when BEFORE_INSERT, BEFORE_UPDATE {
				Set<Id> templateIDs = new Set<Id>();
				String apttPrefix = ActionPlansUtilities.getObjectKeyPrefix('APTTaskTemplate__c');
				for(APTTaskTemplate__c aptt : newRecords){
					if( aptt.Name == null || aptt.Name.startsWithIgnoreCase(apttPrefix) || (oldRecords != null && aptt.Subject__c != oldRecordsMap.get(aptt.Id).Subject__c) || !aptt.Name.endsWithIgnoreCase(aptt.Subject__c) ){
						templateIDs.add(aptt.Action_Plan_Template__c);
					}
				}
				if(!templateIDs.isEmpty()){
					Map<Id, ActionPlanTemplate__c> nameMap = new Map<Id, ActionPlanTemplate__c>([SELECT Id, Name FROM ActionPlanTemplate__c WHERE Id IN :templateIDs]);

					for(APTTaskTemplate__c aptt : newRecords){
						if( nameMap.containsKey(aptt.Action_Plan_Template__c) ){
							String templateName = nameMap.get(aptt.Action_Plan_Template__c).Name;
							String newSubject = templateName + ' - ' + aptt.Subject__c;
							aptt.Name = ActionPlansUtilities.actionPlanSubjectToName(newSubject);
						}
					}
				}
				for( APTTaskTemplate__c a : newRecords ){
					if(a.Reminder__c && String.isBlank(a.Minutes_Reminder__c)){
						a.Minutes_Reminder__c = ActionPlansUtilities.getDefaultReminderMinutes();
					} else if( !a.Reminder__c ){
						a.Minutes_Reminder__c = null;
					}
				}
			}
		}
	}

	public static void triggerHandler_ActionPlanTask(List<Task> newRecords, List<Task> oldRecords, Map<Id, Task> newRecordsMap, Map<Id, Task> oldRecordsMap, System.TriggerOperation triggerEvent){

		//System.debug('In Task ' + triggerEvent.name());

		switch on triggerEvent {

			when AFTER_UPDATE {
				Map<Id, String> closedTasksMap = new Map<Id, String>();
				Map<Id, String> inProgressTasksMap = new Map<Id, String>();
				Set<Id> APTasksIds = new Set<Id>();

				Map<Id, Task> triggerTasksWithTemplateTaskStatus = new Map<Id, Task>();
				for(Task ta : [SELECT Id, Status, TaskAPTaskTemplate__r.Status__c, TaskAPTaskTemplate__r.Controller__c, TaskAPTaskTemplate__r.Controller__r.Status__c FROM Task WHERE Id IN :newRecords AND TaskAPTaskTemplate__c != null]){
					triggerTasksWithTemplateTaskStatus.put(ta.Id, ta);
				}

				Boolean taskHasRecordType = ActionPlansUtilities.HAS_RECORD_TYPE;

				Set<String> closedStatuses = ActionPlansUtilities.getClosedTaskStatuses();

				Set<Id> tasktemplatesToValidate = new Set<Id>();

				for( Task t : newRecords ){
					if(t.TaskAPTaskTemplate__c != null){
						tasktemplatesToValidate.add(t.TaskAPTaskTemplate__c);
					}
				}

				// Map of record ID to "true" if the related task template is OPEN
				Map<Id, Boolean> allowMap = allowChangeParentStatus(tasktemplatesToValidate);

				Map<Id, String> rtIdToDefaultStatus = ActionPlansUtilities.getTaskRecordTypeStatusDefaultValues();

				//Get all my Updated complete Task Id's.
				for( Task t : newRecords ) {

					if (t.TaskAPTaskTemplate__c != null){

						APTasksIds.add(t.TaskAPTaskTemplate__c);

						// Find default task status
						String defaultTaskStatus;

						if(!taskHasRecordType){
							defaultTaskStatus = rtIdToDefaultStatus.get(null); //(String)Task.Status.getDescribe().getDefaultValue();
						} else {
							defaultTaskStatus = rtIdToDefaultStatus.get((Id)t.get('recordtypeid'));
						}

						if( t.Status != defaultTaskStatus ){

							if(allowMap.containsKey(t.TaskAPTaskTemplate__c) && allowMap.get(t.TaskAPTaskTemplate__c)){
								if( !t.IsClosed){
									inProgressTasksMap.put( t.TaskAPTaskTemplate__c, t.Status );

								} else if (t.IsClosed) {
									closedTasksMap.put( t.TaskAPTaskTemplate__c, t.Status );

								}
							} else {
								//throw exception
								t.Status.addError(System.Label.ap_UpdateStatusError);
							}
						}
					}
				}

				//Call to ActionPlansUtilities in order to proceed with creation of dependent Task
				if( !closedTasksMap.isEmpty() ) {
					ActionPlansTaskTriggerUtilities.initDependentTaskWork( closedTasksMap );
				}
				//update status to in progress for AP Tasks
				if( !inProgressTasksMap.isEmpty() ) {
					ActionPlansTaskTriggerUtilities.updateAPTasksStatus( inProgressTasksMap );
				}

				//Query APTaskTemplate__c objects to update fields
				if ( !APTasksIds.isEmpty() ){
					Map<Id,APTaskTemplate__c> mapAPTasks = new Map<Id,APTaskTemplate__c>([SELECT Status__c, Id, Controller__r.Status__c, ActivityDate__c, Minutes_Reminder__c,
																							Action_Plan__r.Name
																							FROM APTaskTemplate__c a
																							WHERE Id IN :APTasksIds ]);
					List<APTaskTemplate__c> lUpsert = new List<APTaskTemplate__c>();

					for( Task t : newRecords ) {
						if ( mapAPTasks.containsKey(t.TaskAPTaskTemplate__c) ){
							APTaskTemplate__c tmp = mapAPTasks.get(t.TaskAPTaskTemplate__c);
							tmp.Subject__c = t.Subject;
							tmp.Name = tmp.Id;
							tmp.Comments__c = t.Description;
							tmp.Priority__c = t.Priority;
							tmp.User__c		= t.OwnerId;
							//tmp.Status__c   = t.Status;
							tmp.ActivityDate__c = t.ActivityDate;
							lUpsert.add(tmp);
						}
					}
					if (!lUpsert.isEmpty()){
						// no permission check because in trigger handler
						upsert lUpsert;
					}
				}
			}

			when BEFORE_DELETE {
				Set<Id> taskTempIds = new Set<Id>();
				for( Task t : oldRecords ){
					if( t.TaskAPTaskTemplate__c != null ){
						taskTempIds.add( t.TaskAPTaskTemplate__c );
					}
				}
				//only delete Action Plan Template Tasks that are not deleted
				//create any task depending on this one
				ActionPlansTaskTriggerUtilities.actionsOnTaskBeforeDelete(taskTempIds);
			}

			when AFTER_DELETE {
				Set<Id> taskTempIds = new Set<Id>();
				Set<Id> finalIds = new Set<Id>();
				for( Task t : oldRecords ){
					if( t.TaskAPTaskTemplate__c != null ){
						taskTempIds.add( t.TaskAPTaskTemplate__c );
					}
				}
				//only delete Action Plan Template Tasks that are not deleted

				for( APTaskTemplate__c ta : [SELECT Id, Action_Plan__c
						FROM APTaskTemplate__c
						WHERE Id IN :taskTempIds AND isDeleted = false ALL ROWS ] ){
					finalIds.add( ta.Id );
				}

				if (!finalIds.isEmpty()){
					if ( System.isBatch() || System.isFuture()){
						Database.delete([SELECT Id FROM APTaskTemplate__c WHERE Id IN :finalIds]);
					} else {
						ActionPlansTaskTriggerUtilities.deleteAPTasks( finalIds );
					}
				}
			}

			when BEFORE_INSERT {
				if(ActionPlansUtilities.HAS_RECORD_TYPE){
					Map<Id, Id> taskTemplateToIntendedRecordTypeId = new Map<Id, Id>();
					Set<Id> taskTemplateIDs = new Set<Id>();
					for(Task t : newRecords){
						if(t.TaskAPTaskTemplate__c != null){
							taskTemplateIDs.add(t.TaskAPTaskTemplate__c);
						}
					}
					for(APTaskTemplate__c aptt : [SELECT Id, Action_Plan__r.TaskRecordTypeID__c FROM APTaskTemplate__c WHERE Id IN :taskTemplateIDs]){
						taskTemplateToIntendedRecordTypeId.put(aptt.Id, aptt.Action_Plan__r.TaskRecordTypeID__c);
					}
					for(Task t : newRecords){
						if(!taskTemplateToIntendedRecordTypeId.containsKey(t.TaskAPTaskTemplate__c)){
						}
						if(!ActionPlansUtilities.getTaskRecordTypeStatusDefaultValues().containsKey(taskTemplateToIntendedRecordTypeId.get(t.TaskAPTaskTemplate__c))){
						}
						if(t.TaskAPTaskTemplate__c != null && taskTemplateToIntendedRecordTypeId.containsKey(t.TaskAPTaskTemplate__c)
						&& ActionPlansUtilities.getTaskRecordTypeStatusDefaultValues().containsKey(taskTemplateToIntendedRecordTypeId.get(t.TaskAPTaskTemplate__c))){
							t.put('RecordTypeId', taskTemplateToIntendedRecordTypeId.get(t.TaskAPTaskTemplate__c));
						} else {
							//System.debug('We did not link Task to Template');
						}
					}
				}
			}
		}
	}

	/**
	 * Handle ActionPlans related to Leads after conversion
	 */
	public static void triggerHandler_ActionPlanLead(List<Lead> newRecords, List<Lead> oldRecords, Map<Id,Lead> newRecordsMap, Map<Id,Lead> oldRecordsMap, System.TriggerOperation triggerEvent){
		switch on triggerEvent {

			when AFTER_UPDATE {
				List<ActionPlan__c> leadAPs = [SELECT Id, Lead__c, Contact__c, Account__c, Opportunity__c, Description__c FROM ActionPlan__c WHERE Lead__c IN :newRecordsMap.keySet()];

				Map<Id, ActionPlan__c> apMap = new Map<Id, ActionPlan__c>();
				List<ActionPlan__c> toUpdate = new List<ActionPlan__c>();

				for(ActionPlan__c ap : leadAPs){
					apMap.put(ap.Lead__c, ap);
				}

				Action_Plans_Settings__c mySettings = ActionPlansUtilities.getCustomSetting();
				System.debug('mySettings ' + mySettings);
				String destinationObject = mysettings.Default_Object_on_Lead_Conversion__c;
				if(destinationObject != null){
					destinationObject = destinationObject.toLowerCase();
				}

				for(Lead l : newRecords){
					if(l.IsConverted && !oldRecordsMap.get(l.Id).IsConverted){
						ActionPlan__c ap = apMap.get(l.Id);

						switch on destinationObject {
							when 'account' {
								ap.Account__c = l.ConvertedAccountId;
							}
							when 'opportunity' {
								ap.Opportunity__c = l.ConvertedOpportunityId;
							} when else {
								ap.Contact__c = l.ConvertedContactId;
							}
						}
						ap.Lead__c = null;
						toUpdate.add(ap);
					}
				}
				System.debug('APs to Update pre-update: ' + toUpdate);
				update toUpdate;
			}
		}
	}

	public static void triggerHandler_ActionPlanAccount(List<Account> newRecords, List<Account> oldRecords, Map<Id,Account> newRecordsMap, Map<Id,Account> oldRecordsMap, System.TriggerOperation triggerEvent){


		//Delete related action plans
		switch on triggerEvent {

			when BEFORE_DELETE {

				Set<Id> oldRecordIDs = oldRecordsMap.keyset();

				// GET Action Plans to delete in recycle bin
				List<ActionPlan__c>  deletePermenantly_apIds = [SELECT Id FROM ActionPlan__c WHERE (Contact__r.AccountId IN :oldRecordIDs OR Case__r.AccountId IN :oldRecordIDs OR Contract__r.AccountId IN :oldRecordIDs OR Opportunity__r.AccountId IN :oldRecordIDs) AND isDeleted = true ALL ROWS];

				if ( deletePermenantly_apIds.size() >0 ){
					Database.emptyRecycleBin(deletePermenantly_apIds);
				}

				Set<Id>  apIds  = new Set<Id>();
				for( ActionPlan__c ap : [SELECT Id FROM ActionPlan__c WHERE (Contact__r.AccountId IN :oldRecordIDs OR Case__r.AccountId IN :oldRecordIDs OR Contract__r.AccountId IN :oldRecordIDs OR Opportunity__r.AccountId IN :oldRecordIDs)] ){
					apIds.add( ap.Id );
				}

				if ( apIds.size() > 0 ){
					ActionPlansBatchDelete aPBatch = new ActionPlansBatchDelete(apIds);
					Database.executeBatch( aPBatch );
				}
			}

			//Undelete related action plans
			when AFTER_UNDELETE {

				Set<Id> relatedIDs = new Set<Id>();
				for(Contact c : [SELECT Id FROM Contact WHERE AccountId IN :newRecordsMap.keyset()]){
					relatedIDs.add(c.Id);
				}
				for(Contract c : [SELECT Id FROM Contract WHERE AccountId IN :newRecordsMap.keySet()]){
					relatedIDs.add(c.Id);
				}
				for(Case c : [SELECT Id FROM Case WHERE AccountId IN :newRecordsMap.keySet()]){
					relatedIDs.add(c.Id);
				}
				for(Opportunity c : [SELECT Id FROM Opportunity WHERE AccountId IN :newRecordsMap.keySet()]){
					relatedIDs.add(c.Id);
				}

				List<ActionPlan__c> aPs = [SELECT Id FROM ActionPlan__c WHERE Contact__c IN :relatedIDs OR Contract__c IN :relatedIDs OR Case__c IN :relatedIDs OR Opportunity__c IN :relatedIDs ALL ROWS];

				try{
					if(ActionPlansTestUtilities.forceError){
						//throw dmlException
						insert new Contact();
					}
					//undelete aPs;
					Database.undelete( aPs, false);
				} catch ( Dmlexception e ){
					for (Account c : newRecords){
						c.addError(System.Label.ap_RelObjUndeleteError);
					}
				}
			}
		}
	}

	private static void validateActionPlans(List<ActionPlan__c> actionPlans){

		List<String> actionPlanReferenceFields = ActionPlansUtilities.getCustomRelationshipFields();

		// Validate that 1 and only 1 custom reference field is filled

		for(ActionPlan__c ap : actionPlans){
			Integer filledReferences = 0;

			for(String s : actionPlanReferenceFields){
				if(ap.get(s) != null){
					filledReferences++;
				}
			}
			if(filledReferences != 1){
				ap.addError(System.Label.ap_RelatedCount);
			}
		}
	}

	private static String getRelationshipName(Id recordId) {
		Schema.SObjectType token = recordId.getSObjectType();
		String sObjectName = token.getDescribe().getName().toLowerCase();

		Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.ActionPlan__c.fields.getMap();

		for(String s : fieldMap.keyset()){
			Schema.DescribeFieldResult dfr = fieldMap.get(s).getDescribe();
			Schema.DisplayType dt = dfr.getType();
			if(dt.name().equalsIgnoreCase('Reference') && s.endsWithIgnoreCase('__c')){
				String relationshipObjectName = dfr.getReferenceTo()[0].getDescribe().getName();
				if( sObjectName.equalsIgnoreCase(relationshipObjectName) ){
					return s;
				}
			}
		}
		return null;
	}

	/**
	* Validates if the given tasks can change status to in progress or completed.
	* If the task : depends on another that is open, returns false
	* This bulkified method avoids SOQL queries in a loop
	* @param apTaskTemplateIds - bulkified set of task IDs to consider
	* @return dependsOnInProgressTask
	*/
	private static Map<Id, Boolean> allowChangeParentStatus(Set<Id> apTaskTemplateIds){
		Map<Id, Boolean> allowTasksMap = new Map<Id, Boolean>();
		Set<String> openStatuses = ActionPlansUtilities.getOpenTaskStatuses();

		for(APTaskTemplate__c apt : [SELECT Status__c, Controller__c, Controller__r.Status__c
											FROM APTaskTemplate__c
											WHERE Id IN :apTaskTemplateIds]){

				allowTasksMap.put(apt.Id, apt.Controller__c == null || !openStatuses.contains(apt.Controller__r.Status__c) );

		}

		return allowTasksMap;
	}
}