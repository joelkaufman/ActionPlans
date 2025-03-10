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
public inherited sharing class ActionPlansBatchBuilderUtilities {

	//private List<SObject> relObjects                { get; set; }
	private List<APTaskTemplate__c> baseAPTaskList  { get; set; }

	private List<ActionPlan__c> relActionPlans      { get; set; }
	private List<APTaskTemplate__c> relAPTaskList   { get; set; }

	private String relatedObjectName                { get; set; }
	private Set<Id> relatedRecordIDs                { get; set; }

	//private Id newActionPlanId;

	public enum ApEditMode { MODE_EDIT_SINGLE, MODE_NEW }
	private ApEditMode mode;

	private List<Task>  myTasksWithOutEmail         { get; set; }
	private List<Task>  myOldTasksWithEmail         { get; set; }
	private List<Task>  myNewTasksWithEmail         { get; set; }

	public ActionPlansBatchBuilderUtilities (ActionPlan__c baseObj, List<APTaskTemplate__c> aPTListparam, String refType, Set<Id> oIdsLIst){

		this.baseAPTaskList = aPTListparam;
		this.relActionPlans = new List<ActionPlan__c>();
		this.relatedObjectName  = refType;
		this.relatedRecordIDs = oIdsLIst;

		// if the actionPlan has already an Id, then we are editing an AP and not creating a new one
		if (baseObj.id != null){

			mode = ApEditMode.MODE_EDIT_SINGLE;

			relActionPlans.add(baseObj);

		} else {

			List<String> apRefFields = ActionPlansUtilities.getCustomRelationshipFields();

			// If baseObjId == null, then we are inserting a single or multiple APs

			for( Id relObjId : oIdsLIst ){ // iterate over all related IDs
				ActionPlan__c ap = new ActionPlan__c();
				ap = baseObj.clone();

				for(String s : apRefFields){
					if(s.equalsIgnoreCase( refType ) || (s.removeEndIgnoreCase('__c').equalsIgnoreCase( refType ))){
						ap.put( s, relObjId);
						break;
					}
				}

				//add Action Plan to list that will be inserted later and referenced by ActionPlanTasks
				relActionPlans.add(ap);
			}

			mode = ApEditMode.MODE_NEW;
		}
	}

	/* public Id getNewActionPlanId(){
		return this.newActionPlanId;
	} */

	public Iterable<sObject> getObjects( Database.BatchableContext bc ){
		return relActionPlans;
	}

	public Id generateActionPlans() {

		List<APTaskTemplate__c> aptList         = new List<APTaskTemplate__c>();
		List<Id> aptTOTALListId                 = new List<Id>();
		Map<Id,APTaskTemplate__c> mapAP         = new Map<Id,APTaskTemplate__c>();
		Map<Id,ActionPlan__c> mapIDAP           = new Map<Id,ActionPlan__c>();
		ActionPlan__c apAux;
		Map<Id,Task> mapApTasks                 = new Map<Id,Task>();
		Integer taskTemplateNameLength          = APTaskTemplate__c.Name.getDescribe().getLength();

		this.myOldTasksWithEmail    = new List<Task>();
		this.myNewTasksWithEmail    = new List<Task>();
		this.myTasksWithOutEmail    = new List<Task>();
		this.relAPTaskList          = new List<APTaskTemplate__c>();

		Map<Id,Id> objectOwnersMap = retrieveOwnersDataRelatedObject( this.relatedRecordIDs, this.relatedObjectName );

		//insert Action Plans to DB
		upsert relActionPlans;

		//create ActionPlanTemplatetasks && tasks from base ActionPlan Task List
		if (this.mode == ApEditMode.MODE_NEW){

			// Working on multiple APs from oidsList
			for(ActionPlan__c ap : relActionPlans){
				mapIDAP.put(ap.Id, ap);

				//Now for each inserted ap we should run through tasks and create them
				for( APTaskTemplate__c t : this.baseAPTaskList ) {
					APTaskTemplate__c nt = new APTaskTemplate__c();
					nt = t.clone();

					nt.Action_Plan__c       = ap.Id;
					nt.Name                 = t.Id == null ? ActionPlansUtilities.actionPlanSubjectToName(t.Subject__c, taskTemplateNameLength) : nt.Name;
					nt.DaysFromStart__c     = ( nt.DaysFromStart__c < 0 ) ? 0 : nt.DaysFromStart__c;
					nt.User__c              = getAPTaskTemplateUser(ap, objectOwnersMap, nt.User__c); //( nt.User__c != null ) ? nt.User__c : getRelatedRecordOwnerId( ap, objectOwnersMap );
					aptList.add( nt );
				}
			}

			upsert aptList;
		}
		else {

			System.assertEquals(1, relActionPlans.size());

			for(ActionPlan__c ap : relActionPlans){

				mapIDAP.put(ap.Id, ap);

				for( APTaskTemplate__c t : this.baseAPTaskList ) {

					t.DaysFromStart__c     = ( t.DaysFromStart__c < 0 ) ? 0 : t.DaysFromStart__c;
					t.Name                 = t.Id == null ? ActionPlansUtilities.actionPlanSubjectToName(t.Subject__c, taskTemplateNameLength) : t.Name;
					t.User__c              = getAPTaskTemplateUser(ap, objectOwnersMap, t.User__c); //( nt.User__c != null ) ? nt.User__c : getRelatedRecordOwnerId( ap, objectOwnersMap );
				}
				aptList = this.baseAPTaskList;
			}
		}

		List<APTaskTemplate__c> aptsToUpsert = new List<APTaskTemplate__c>();

		for(ActionPlan__c ap : relActionPlans){

			for(APTaskTemplate__c at : aptList ){

				if(at.Action_Plan__c != null && at.Action_Plan__c != ap.Id){continue;}

				aptTOTALListId.add(at.Id);

				if(at.Action_Plan__c == null && ap.Id != null){
					at.Action_Plan__c = ap.Id;
				} // This Id can be null because we may not have set it in the controller

				if( at.Status__c == null ){
					if(!String.isBlank(at.Task_RecordTypeId__c) && at.Task_RecordTypeId__c instanceof Id && at.Task_RecordTypeId__c.startsWithIgnoreCase('012')){
						at.Status__c = ActionPlansUtilities.getTaskRecordTypeStatusDefaultValues().get(at.Task_RecordTypeId__c);
					} else {
						if(ActionPlansUtilities.HAS_RECORD_TYPE){
							at.Status__c = ActionPlansUtilities.getTaskRecordTypeStatusDefaultValues().get(ActionPlansUtilities.getDefaultTaskRecordTypeId());
						} else {
							at.Status__c = ActionPlansUtilities.getTaskRecordTypeStatusDefaultValues().get(null);
						}
					}
				}

				if( at.Dependent__c != null && at.Dependent__c != 'None' ){
					Integer tempIndex   = Integer.valueOf( at.Dependent__c );
					at.Controller__c = aptList[tempIndex].Id;
					at.ActivityDate__c = null;
				}
				else {

					at.Controller__c = null;

					//set dependency taskId to none if none was selected
					if (at.Dependent__c == null){
						at.Dependent__c = 'None';
					}

					// create due date, calculate the due date of the tasks for skip weekends feature
					if( ap.SkipWeekends__c == true && ap.SkipDay__c != null){

						at.ActivityDate__c = ActionPlansUtilities.adjustTaskDueDate(ap.StartDate__c, at.DaysFromStart__c.intValue(), ap.SkipDay__c);
					}
					else {
						at.ActivityDate__c = ap.StartDate__c.addDays( at.DaysFromStart__c.intValue() );
					}

				}

				mapAP.put(at.Id,at);
				aptsToUpsert.add(at);
			}
		}

		upsert aptsToUpsert;

		for( Task task_tmp : [SELECT Id, TaskAPTaskTemplate__c, Subject FROM Task WHERE TaskAPTaskTemplate__c IN :mapAP.keySet()] ) {
			mapApTasks.put(task_tmp.TaskAPTaskTemplate__c, task_tmp);
		}

		for( APTaskTemplate__c t_t : aptsToUpsert ) {
			// check if task exists already
			Task t = mapApTasks.get( t_t.Id);
			if (t == null){
				//Create the new task and template
				t = new Task();
			}
			t.Subject           = t_t.Subject__c;
			t.Priority          = t_t.Priority__c;
			t.OwnerId           = t_t.User__c;
			t.TaskAPTaskTemplate__c = t_t.Id;

			if( t_t.Comments__c != null ){
				t.Description = t_t.Comments__c;
			}

			//set reminder based on user's default reminder setting
			if( t_t.Reminder__c == true && t_t.ActivityDate__c != null ){

				t.isReminderSet = true;
				t.ReminderDateTime = Datetime.newInstance( t_t.ActivityDate__c.year(), t_t.ActivityDate__c.month(), t_t.ActivityDate__c.day(), 0, 0, 0 );
				t.ReminderDateTime = t.ReminderDateTime.addMinutes( Integer.valueOf( t_t.Minutes_Reminder__c ) );
			}
			else {
				t.isReminderSet = false;
			}

			APTaskTemplate__c apt = mapAP.get(t_t.Id);

			if ( apt != null ){

				apAux = mapIDAP.get(apt.Action_Plan__c);
			}

			if ( apAux == null ){
				apAux = t_t.Action_Plan__r;
			}

			//link to Action Plan's Related To Object
			for( String s : ActionPlansUtilities.getCustomRelationshipFields() ){
				String f = s;
				if(!f.equalsIgnoreCase('Contact__c') && !f.equalsIgnoreCase('Lead__c') && apAux.get(f) != null){
					t.WhatId = (Id)apAux.get(f);
					break;
				}
			}

			if( apAux.Contact__c != null ){
				t.WhoId = apAux.Contact__c;
			}
			if( apAux.Lead__c != null ){
				t.WhoId = apAux.Lead__c;
			}

			t.Type = t_t.Type__c;

			if (t.Id == null){
				t.Status        = t_t.Status__c;
			}
			t.ActivityDate  = t_t.ActivityDate__c;

			if( t_t.Dependent__c == 'None' ){
				if( t_t.SendEmail__c == true ){
					if( t.id == null )  {this.myNewTasksWithEmail.add( t );}
					else                {this.myOldTasksWithEmail.add( t ); }
				}
				else {
					this.myTasksWithOutEmail.add( t );
				}
			} else {
				//only update dependant tasks that are already created
				if( t.Id != null  ){
						this.myTasksWithOutEmail.add( t );
				}
			}

		}
		if(ActionPlansCanTheUser.ups('Task')){
			Database.DMLOptions dmlo    = new Database.DMLOptions();
			Database.DMLOptions dmlo2   = new Database.DMLOptions();

			if( this.myNewTasksWithEmail.size() > 0 ){
				dmlo.EmailHeader.triggerUserEmail = true;
				Database.insert( this.myNewTasksWithEmail, dmlo );
			}

			if( this.myOldTasksWithEmail.size() > 0 ){
				dmlo.EmailHeader.triggerUserEmail = true;
				Database.update( this.myOldTasksWithEmail, dmlo );
			}

			if( this.myTasksWithOutEmail.size() > 0 ){
				if (this.mode == ApEditMode.MODE_EDIT_SINGLE){
					Database.upsert( this.myTasksWithOutEmail );
				} else {
					dmlo2.EmailHeader.triggerUserEmail = false;
					Database.insert( this.myTasksWithOutEmail, dmlo2 );
				}
			}
		}

		//If we Only Create an Action Plan save the Id of the new object
		/* if (relActionPlans.size() == 1 ){
			this.newActionPlanId = relActionPlans[0].Id;
		} */

		if (this.mode != ApEditMode.MODE_EDIT_SINGLE){
		 //Execution When a Action Plan is created, that checks the Custom Setings in order to post a new FeedPost ( Object )
			Action_Plans_Settings__c mySettings = ActionPlansUtilities.getCustomSetting();

			Set<Id> relObjectIDs = new Set<Id>();
			for(ActionPlan__c ap : relActionPlans){
				relObjectIDs.add(ap.Id);
			}

			if(mySettings != null && mySettings.Chatter_Object_Brag__c ) {
				generateObjectFeeds(relObjectIDs);
			}
		}
		return relActionPlans[0].id;
	}

	/**
	 * Read the Action Plan and see the custom setting to determine who should own the at Template
	 * @param ActionPlan__c ap
	 * @param Map<Id, Id> relObjOwners
	 * @param Id apTaskUser current record user
	 * @return Id newOwner
	 */
	public static Id getAPTaskTemplateUser( ActionPlan__c ap, Map<Id, Id> relObjOwners, Id apTaskUser){
		if(String.isNotBlank(apTaskUser)){ return apTaskUser; }
		Action_Plans_Settings__c mySettings = ActionPlansUtilities.getCustomSetting();
		if(!mySettings.Unassigned_Task_Default__c){

			return UserInfo.getUserId();
		}
		Id relatedOwnerId = getRelatedRecordOwnerId(ap, relObjOwners);

		return relatedOwnerId;
	}

	/**
	* Read the Action Plan Object and get the Related Record Owner
	* @return rOwner
	*/
	public static Id getRelatedRecordOwnerId( ActionPlan__c ap , Map<Id, Id> relObjOwners){

		Id ownerValue;
		Id objId;

		for( String f : ActionPlansUtilities.getCustomRelationshipFields() ){

			if(ap.get(f) != null){
				objId = (Id)ap.get(f);
				break;
			}
		}

		if(relObjOwners.containsKey( objId )){
			ownerValue = relObjOwners.get( objId );

			return ownerValue;

		} else {
			return null;
		}
	}

	/**
	* Retrieve the owner list from the related object.
	* @param relatedObjIds		list of sobjects' id
	* @param relatedObjectName
	*/
	public static Map<Id, Id> retrieveOwnersDataRelatedObject ( Set<Id> relatedObjIds, String relatedObjectName ){

		Map<Id, Id> relatedObjOwners = new Map<Id, Id>();
		String queryRetrieveOwnerIds;

		if( !relatedObjIds.isEmpty() ){
			queryRetrieveOwnerIds = 'SELECT Id, OwnerId FROM ' + relatedObjectName + ' WHERE Id IN :relatedObjIds';

			for( SObject obj : Database.query(queryRetrieveOwnerIds) ){
				relatedObjOwners.put( (Id)(obj.get('Id')), (Id)(obj.get('OwnerId')));

			}
		}
		return relatedObjOwners;
	}

	/**
	* Generate New FeedPosts for multiple Action Plans
	* @parm : ap
	* @return oFeed
	*/
	public static void generateObjectFeeds( Set<Id> objIds ){

		List<SObject> chatterPosts = new List<SObject>();

		List<String> apRefFields = ActionPlansUtilities.getCustomRelationshipFields();
		String apQuery = 'SELECT Id, Name, ' + String.join(apRefFields, ', ') + ' FROM ActionPlan__c WHERE Id IN :objIds';

		for(SObject so : Database.query(apQuery)){

			ActionPlan__c ap = (ActionPlan__c)so;

			Id objId;
			String objName;
			Boolean chatter_enabled ;

			for( String f : apRefFields ){

				if(ap.get(f) != null){
					objId = (Id)ap.get(f);
					chatter_enabled = objId.getSObjectType().getDescribe().isFeedEnabled();
					break;
				}
			}

			if (chatter_enabled){

				sObjectType token = Schema.getGlobalDescribe().get('FeedItem');
				SObject objPost = token.newSObject();
				objPost.put('Type', 'TextPost');
				objPost.put('ParentId', objId);
				objPost.put('Body', getPostObjectBody( objId, (String)ap.get('Name') ));

				chatterPosts.add(objPost);

				// to use this requires @seealldata=true, and we want to avoid that.
				//ConnectApi.FeedElement feedElement = ConnectApi.ChatterFeeds.postFeedElement(Network.getNetworkId(), objId , ConnectApi.FeedElementType.FeedItem, this.getPostObjectBody( objName ));
			}
		}

		insert chatterPosts;
	}

	public static String getPostObjectBody( Id recID, String apName ){

		String objName = recID.getSObjectType().getDescribe().getLabel();
		String actionPlanName = apName;
		String runningUserName = UserInfo.getName();

		List<String> parameters = new List<String>();
		parameters.add(actionPlanName);
		parameters.add(objName);

		String chatterBody = runningUserName + ' ' + String.format(System.Label.ap_PostMessage, parameters);
		return chatterBody;
	}

}