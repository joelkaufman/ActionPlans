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
@IsTest
private class ActionPlanCreationControllerTest {

	@TestSetup
	static void makeData(){
		Action_Plans_Settings__c aps = Action_Plans_Settings__c.getOrgDefaults();
		aps.Chatter_Object_Brag__c = true;
		aps.Unassigned_Task_Default__c = true;
		try{
			upsert aps;
		} catch (Exception e){
			update aps;
		}
	}

	@IsTest
	private static void singleRecordConstructor(){
		Test.StartTest();
		Test.setCurrentPage(Page.ActionPlanCreation);

		ActionPlansTestUtilities testUtil = new ActionPlansTestUtilities();
		ActionPlan__c actionPlan = testUtil.createNewActionPlan( 'contact', 2 );

		ActionPlanCreationController apCreateController = new ActionPlanCreationController( new Apexpages.StandardController( actionPlan ) );
		apCreateController.onLoad();
		System.assertNotEquals(null, apCreateController.relatedFieldName, 'should have lazy loaded relatedFieldName');

		apCreateController = new ActionPlanCreationController( new Apexpages.StandardController( actionPlan ) );
		Id recId = apCreateController.relatedObjectId();
		apCreateController.save();
		Test.stopTest();
	}

	@IsTest
	private static void constructorTests(){

		Test.StartTest();
		Test.setCurrentPage(Page.ActionPlanCreation);

		ApexPages.currentPage().getParameters().put( 'id', null );
		ActionPlanCreationController apCreateController = new ActionPlanCreationController( new Apexpages.StandardController( new ActionPlan__c() ) );
		System.assertNotEquals(null, apCreateController.relatedFieldName, 'should have lazy loaded relatedFieldName');

		ActionPlansTestUtilities testUtil = new ActionPlansTestUtilities();
		ActionPlan__c actionPlan = testUtil.createNewActionPlan( 'contact', 2 );

		apCreateController = new ActionPlanCreationController( new Apexpages.StandardController( actionPlan ) );

		ApexPages.currentPage().getParameters().put( 'id', null );
		ApexPages.currentPage().getParameters().put( 'clone', '1' );
		apCreateController = new ActionPlanCreationController( new Apexpages.StandardController( new ActionPlan__c() ) );

		ActionPlanTemplate__c apTemplate = testUtil.createNewActionPlanTemplate( 3 );

		ApexPages.currentPage().getParameters().put( 'id', null );
		ApexPages.currentPage().getParameters().put( 'clone', null );
		ApexPages.currentPage().getParameters().put( 'templateId', apTemplate.Id );
		apCreateController = new ActionPlanCreationController( new Apexpages.StandardController( new ActionPlan__c() ) );

		Contact contact = testUtil.createNewContact();

		ApexPages.currentPage().getParameters().put( 'id', null );
		ApexPages.currentPage().getParameters().put( 'refId', contact.Id );
		apCreateController = new ActionPlanCreationController( new Apexpages.StandardController( new ActionPlan__c() ) );
		String refid    = apCreateController.refId;
		String reftype  = apCreateController.refType;

		apCreateController.refreshRelatedObjectsLookUp();
		apCreateController.getTaskRTPicklistValues();
		apCreateController.getTaskTypes();
		apCreateController.getTaskPriorities();
		apCreateController.getHoursOption();
		apCreateController.getDisplayTemplateLookup();
		apCreateController.getRecordTypeName();

		apCreateController.save();

		Test.StopTest();
	}

	@IsTest
	private static void testActionPlanSave(){

		Test.setCurrentPage(Page.ActionPlanCreation);

		ActionPlansTestUtilities testUtil   = new ActionPlansTestUtilities();
		ActionPlan__c ap = testUtil.createNewActionPlan('contact', 3);
		Contact contact = [SELECT Id FROM Contact LIMIT 1];

		ApexPages.currentPage().getParameters().put( 'id', ap.Id );
		ApexPages.currentPage().getParameters().put( 'refId', contact.Id );
		ApexPages.currentPage().getParameters().put( 'refType', 'Contact' );

		Test.StartTest();

		ActionPlanCreationController apCreateController = new ActionPlanCreationController( new Apexpages.StandardController( ap ) );

		apCreateController.actionPlan.name = 'updated name';

		apCreateController.save();

		Test.setCurrentPage(Page.ActionPlanCreation);
		apCreateController = new ActionPlanCreationController( new Apexpages.StandardController( ap ) );

		apCreateController.actionPlan.SkipWeekends__c = true;
		apCreateController.actionPlan.SkipDay__c = 'End of previous week';

		apCreateController.save();

		Test.StopTest();

		List<ActionPlan__c> results = [SELECT Id, name, Contact__c FROM ActionPlan__c LIMIT 10000];
		System.debug(results);

		System.assert( !results.isEmpty(), 'Action Plan not created' );
		System.assert( results.size() == 1, 'Too many Action Plans created' );

		apCreateController.cancel();
	}

	@IsTest
	private static void testActionPlanSaveAndNew(){

		Test.setCurrentPage(Page.ActionPlanCreation);

		ActionPlansTestUtilities testUtil   = new ActionPlansTestUtilities();
		ActionPlan__c actionPlan            = new ActionPlan__c();

		Contact contact = testUtil.createNewContact();

		actionPlan.Name         = testUtil.createRandomWord('Name');
		actionPlan.Contact__c   = contact.Id;
		actionPlan.StartDate__c = Date.today();

		APTaskTemplate__c apTask = new APTaskTemplate__c();

		apTask.Subject__c           = testUtil.createRandomWord('subject');
		apTask.User__c              = testUtil.createTestUser().Id;
		apTask.DaysFromStart__c     = 2;
		apTask.Type__c              = 'Email';
		apTask.Priority__c          = 'High';

		ApexPages.currentPage().getParameters().put( 'id', null );
		ApexPages.currentPage().getParameters().put( 'refId', contact.Id );
		ApexPages.currentPage().getParameters().put( 'refType', 'Contact' );

		Test.StartTest();

		ActionPlanCreationController apCreateController = new ActionPlanCreationController( new Apexpages.StandardController( actionPlan ) );

		apCreateController.apTasks = new List<APTaskTemplate__c>();
		apCreateController.apTasks.add( apTask );
		apCreateController.saveAndNew();
		Test.StopTest();
		List<ActionPlan__c> results = [SELECT Id FROM ActionPlan__c LIMIT 10000];

		System.assert( !results.isEmpty(), 'Action Plan not created' );
		System.assert( results.size() == 1, 'ONE Action Plan not created' );
		System.debug(results.size() + ' action plans created');

	}

	@IsTest
	private static void testRelateToMultipleContacts(){

		final Integer CONCOUNT = 100;
		final Integer APTTASKCOUNT = 2;

		List<Contact> contacts = new List<Contact>();
		for(Integer i = 0; i < CONCOUNT; i++){
			Contact newContact 	= new Contact( LastName = 'con' + math.rint(math.random() * 100000) );
			contacts.add(newContact);
		}

		Database.DMLOptions dml = new Database.DMLOptions();
		dml.DuplicateRuleHeader.allowSave = true;
		dml.DuplicateRuleHeader.runAsCurrentUser = true;
		List<Database.SaveResult> sr = Database.insert(contacts, dml);

		List<Id> conIDs = new List<Id>();
		for(Contact c : contacts){
			conIDs.add(c.Id);
		}
		String conIdsList = String.join(conIDs,',');

		ActionPlansTestUtilities testUtil 	= new ActionPlansTestUtilities();
		ActionPlanTemplate__c apTemplate 	= testUtil.createNewActionPlanTemplate( APTTASKCOUNT );

		Test.startTest();

		Test.setCurrentPage(Page.ActionPlanCreation);

		ApexPages.currentPage().getParameters().put( 'id', null );
		ApexPages.currentPage().getParameters().put( 'templateId', apTemplate.Id);
		ApexPages.currentPage().getParameters().put( 'refId', conIDsList );
		ApexPages.currentPage().getParameters().put( 'refType', 'Contact' );
		ActionPlanCreationController apCreateController = new ActionPlanCreationController( new Apexpages.StandardController( new ActionPlan__c() ) );
		System.assert(apCreateController.inVisualforceContext, 'Test should have VF context as true');
		apCreateController.getTasks();
		System.assertEquals(APTTASKCOUNT, apCreateController.getTasks().size());

		System.assertEquals(CONCOUNT, apCreateController.getNameListSize());

		apCreateController.save();

		Test.stopTest();
		System.debug('TEST STOPPED');
		System.assertEquals(APTTASKCOUNT, [SELECT Count() FROM APTTaskTemplate__c]);
		System.assertEquals(CONCOUNT, [SELECT Count() FROM ActionPlan__c], 'Failed to make one AP per contact');
		System.debug('successfully related to ' + CONCOUNT + ' Contacts');

		System.assertNotEquals(0, [SELECT Count() FROM ActionPlan__c WHERE Contact__c != null], 'Should have linked Action Plan to contact');

		System.assertEquals( CONCOUNT * APTTASKCOUNT, [SELECT Count() FROM APTaskTemplate__c], 'Not enough Action Plan Tasks created');

		System.assertEquals( CONCOUNT * APTTASKCOUNT, [SELECT Count() FROM Task], 'Wrong number of Tasks created');
	}

	@IsTest
	private static void checkCompletedTasks(){

		Test.setCurrentPage(Page.ActionPlanCreation);

		ActionPlansTestUtilities testUtil   = new ActionPlansTestUtilities();
		ActionPlan__c actionPlan            = testUtil.createNewActionPlan( 'account', 2 );

		Test.StartTest();

		ActionPlanCreationController apCreateController = new ActionPlanCreationController( new Apexpages.StandardController( actionPlan ) );

		Integer numTasksComplete = apCreateController.getCompleted();

		System.assert( numTasksComplete == 0, 'Action plan task completed count is incorrect' );

		Test.StopTest();
	}

	@IsTest
	private static void longNameTasks(){

		Test.StartTest();

		Test.setCurrentPage(Page.ActionPlanCreation);

		ActionPlansTestUtilities testUtil   = new ActionPlansTestUtilities();
		ActionPlan__c actionPlan            = testUtil.createNewActionPlan( 'account', 2 );

		// add code for shortening long record names
		actionPlan.Name = '1234567890123456789012345678901234567890'; // 40 characters
		update actionPlan;
		List<APTaskTemplate__c> apts = [SELECT Id, Subject__c FROM APTaskTemplate__c];
		for(APTaskTemplate__c a : apts){
			a.Subject__c = 'abcdefghijabcdefghijabcdefghijabcdefghij'; // 40 characters
		}
		update apts;

		ActionPlanCreationController apCreateController = new ActionPlanCreationController( new Apexpages.StandardController( actionPlan ) );

		Integer numTasksComplete = apCreateController.getCompleted();

		System.assert( numTasksComplete == 0, 'Action plan task completed is incorrect' );

		Test.StopTest();

		for(APTaskTemplate__c a : [SELECT Id, Name FROM APTaskTemplate__c]){
			System.assertEquals(80, a.Name.length(), 'APTask Template name was not updated');
		}
	}

	@IsTest
	private static void testAddNewTask(){
		ActionPlansTestUtilities testUtil   = new ActionPlansTestUtilities();

		Test.setCurrentPage(Page.ActionPlanCreation);

		ActionPlan__c actionPlan = testUtil.createNewActionPlan( 'account', 0 );

		User ownerUser = testUtil.createTestUser();

		APTaskTemplate__c apTask = new APTaskTemplate__c();
		apTask.Action_Plan__c       = actionPlan.Id;
		apTask.Subject__c           = testUtil.createRandomWord('subject');
		apTask.User__c              = ownerUser.Id;
		apTask.DaysFromStart__c     = 2;
		apTask.Type__c              = 'Email';
		apTask.Priority__c          = 'High';
		insert apTask;

		Id defaultTaskRTId = [SELECT Id, TaskRecordTypeID__c FROM ActionPlan__c LIMIT 1].TaskRecordTypeID__c;
		System.debug('defaultTaskRTID: ' + defaultTaskRTId);

		Test.StartTest();

		ActionPlanCreationController apCreateController = new ActionPlanCreationController( new Apexpages.StandardController( actionPlan ) );
		//apCreateController.apTasks = new List<APTaskTemplate__c>();
		apCreateController.getTasks();
		System.assertEquals(1, apCreateController.getTasks().size());
		apCreateController.addTask();
		apCreateController.getTasks();
		System.assertEquals(2, apCreateController.getTasks().size());

		ActionPlanCreationController.ApTaskWrapper apt = apCreateController.getTasks()[1];

		apt.task.Subject__c = testUtil.createRandomWord('subject');
		apt.task.DaysFromStart__c = 3;
		apt.task.User__c = ownerUser.Id;
		apt.task.Priority__c = ActionPlansUtilities.getTaskRecordTypePriorityDefaultValues().get(defaultTaskRTId);
		System.debug('Priority is set to ' + ActionPlansUtilities.getTaskRecordTypePriorityDefaultValues().get(defaultTaskRTId));
		apCreateController.save();

		Test.StopTest();

		System.assertEquals(2, [SELECT Count() FROM APTaskTemplate__c]);
	}

	@IsTest
	private static void testRemoveActionPlanTask(){

		Test.setCurrentPage(Page.ActionPlanCreation);

		ActionPlansTestUtilities testUtil   = new ActionPlansTestUtilities();
		ActionPlan__c actionPlan            = testUtil.createNewActionPlan( 'account', 3 );

		Test.StartTest();

		ApexPages.currentPage().getParameters().put( 'id', actionPlan.Id );
		ApexPages.currentPage().getParameters().put( 'remove', '1' );
		ActionPlanCreationController apCreateController = new ActionPlanCreationController( new Apexpages.StandardController( actionPlan ) );

		apCreateController.getTasks();
		apCreateController.removeTask();
		apCreateController.save();

		Test.StopTest();

		System.assertEquals(2, [SELECT Count() FROM APTaskTemplate__c]);
	}

	@IsTest
	private static void checkActionPlanTaskList(){

		Test.StartTest();

		Test.setCurrentPage(Page.ActionPlanCreation);

		ActionPlansTestUtilities testUtil   = new ActionPlansTestUtilities();
		ActionPlan__c actionPlan            = testUtil.createNewActionPlan( 'account', 2 );

		ApexPages.currentPage().getParameters().put( 'id', actionPlan.Id );
		ActionPlanCreationController apCreateController = new ActionPlanCreationController( new Apexpages.StandardController( actionPlan ) );

		List<ActionPlanCreationController.ApTaskWrapper> apTaskList = apCreateController.getTasks();

		System.assert( !apTaskList.isEmpty(), 'Action plan task list is empty' );

		Test.StopTest();
	}

	@IsTest
	private static void checkSubjectItems(){
		Integer TASK_COUNT = 2;
		Test.StartTest();

		Test.setCurrentPage(Page.ActionPlanCreation);

		ActionPlansTestUtilities testUtil   = new ActionPlansTestUtilities();
		ActionPlan__c actionPlan            = testUtil.createNewActionPlan( 'account', TASK_COUNT );

		ApexPages.currentPage().getParameters().put( 'id', actionPlan.Id );
		ActionPlanCreationController apCreateController = new ActionPlanCreationController( new Apexpages.StandardController( actionPlan ) );
		apCreateController.apTasks = [SELECT Type__c, Subject__c, ActivityDate__c, Priority__c, Status__c, Dependent__c,
											Name, User__c, User__r.Name, Id, DaysFromStart__c, CreatedById, Controller__r.Name,
											Controller__r.Subject__c, Controller__c, Action_Plan__c, Reminder__c,
											SendEmail__c, Comments__c
											FROM APTaskTemplate__c
										WHERE Action_Plan__c = :actionPlan.Id ORDER BY createdDate asc];

		List<Selectoption> options = apCreateController.getSubjectItems();

		Test.StopTest();

		System.assert( !options.isEmpty(), 'SELECT options is empty' );
		System.assertEquals(TASK_COUNT + 1, options.size(), 'incorrect number of select options' );
	}

	@IsTest
	private static void testCyclicDependencyTaskSuccess(){

		Test.StartTest();

		Test.setCurrentPage(Page.ActionPlanCreation);

		ActionPlansTestUtilities testUtil = new ActionPlansTestUtilities();

		ActionPlan__c actionPlan = testUtil.createNewActionPlan( 'account', 0 );

		APTaskTemplate__c newAPTask1 = new APTaskTemplate__c();
		APTaskTemplate__c newAPTask2 = new APTaskTemplate__c();
		APTaskTemplate__c newAPTask3 = new APTaskTemplate__c();

		newAPTask1.Subject__c           = testUtil.createRandomWord('subject');
		newAPTask1.DaysFromStart__c     = 2;
		newAPTask1.Dependent__c         = '2';
		newAPTask1.Type__c              = 'Email';
		newAPTask1.Priority__c          = 'High';
		newAPTask1.Action_Plan__c       = actionPlan.Id;
		upsert newAPTask1;

		newAPTask2.Subject__c           = testUtil.createRandomWord('subject');
		newAPTask2.DaysFromStart__c     = 2;
		newAPTask2.Dependent__c         = 'None';
		newAPTask2.Type__c              = 'Email';
		newAPTask2.Priority__c          = 'High';
		newAPTask2.Action_Plan__c       = actionPlan.Id;
		upsert newAPTask2;

		newAPTask3.Subject__c           = testUtil.createRandomWord('subject');
		newAPTask3.DaysFromStart__c     = 2;
		newAPTask3.Dependent__c         = '1';
		newAPTask3.Type__c              = 'Email';
		newAPTask3.Priority__c          = 'High';
		newAPTask3.Action_Plan__c       = actionPlan.Id;
		upsert newAPTask3;

		ActionPlanCreationController apCreateController = new ActionPlanCreationController( new Apexpages.StandardController( actionPlan ) );

		apCreateController.apTasks = new List<APTaskTemplate__c>();
		apCreateController.apTasks.add( newAPTask1 );
		apCreateController.apTasks.add( newAPTask2 );
		apCreateController.apTasks.add( newAPTask3 );

		apCreateController.save();

		System.assert( apCreateController.getErrorMsg() == ''  || String.isBlank(apCreateController.getErrorMsg()) );

		Test.StopTest();
	}

	@IsTest
	private static void testCyclicDependencyTasksFail(){

		Test.StartTest();

		Test.setCurrentPage(Page.ActionPlanCreation);

		ActionPlansTestUtilities testUtil = new ActionPlansTestUtilities();

		ActionPlan__c actionPlan = testUtil.createNewActionPlan( 'account', 0 );

		APTaskTemplate__c newAPTask1 = new APTaskTemplate__c();
		APTaskTemplate__c newAPTask2 = new APTaskTemplate__c();
		APTaskTemplate__c newAPTask3 = new APTaskTemplate__c();

		newAPTask1.Subject__c           = testUtil.createRandomWord('subject');
		newAPTask1.DaysFromStart__c     = 2;
		newAPTask1.Dependent__c         = '2';
		newAPTask1.Type__c              = 'Email';
		newAPTask1.Priority__c          = 'High';

		newAPTask2.Subject__c           = testUtil.createRandomWord('subject');
		newAPTask2.DaysFromStart__c     = 2;
		newAPTask2.Dependent__c         = '0';
		newAPTask2.Type__c              = 'Email';
		newAPTask2.Priority__c          = 'High';

		newAPTask3.Subject__c           = testUtil.createRandomWord('subject');
		newAPTask3.DaysFromStart__c     = 2;
		newAPTask3.Dependent__c         = '1';
		newAPTask3.Type__c              = 'Email';
		newAPTask3.Priority__c          = 'High';

		ApexPages.currentPage().getParameters().put( 'id', actionPlan.Id );
		ActionPlanCreationController apCreateController = new ActionPlanCreationController( new Apexpages.StandardController( actionPlan ) );

		apCreateController.apTasks = new List<APTaskTemplate__c>();
		apCreateController.apTasks.add( newAPTask1 );
		apCreateController.apTasks.add( newAPTask2 );
		apCreateController.apTasks.add( newAPTask3 );

		apCreateController.save();

		System.assertNotEquals( null, apCreateController.getErrorMsg() );

		Test.StopTest();
	}

	@IsTest
	private static void checkReferredObject(){

		Test.StartTest();

		Test.setCurrentPage(Page.ActionPlanCreation);

		ActionPlansTestUtilities testUtil = new ActionPlansTestUtilities();

		Contact contact         = testUtil.createNewContact();
		Account account         = testUtil.createNewAccount();
		Account account2        = testUtil.createNewAccount();
		Lead lead               = testUtil.createNewLead();
		Opportunity opportunity = testUtil.createNewOpportunity();
		Case testCase           = testUtil.createNewCase();
		Contract contract       = testUtil.createNewContract();

		ApexPages.currentPage().getParameters().put( 'id', null );
		ApexPages.currentPage().getParameters().put( 'refId', contact.id );
		ApexPages.currentPage().getParameters().put( 'refType', 'Contact' );

		ActionPlanCreationController apCreateController = new ActionPlanCreationController( new Apexpages.StandardController( new ActionPlan__c() ) );
		apCreateController.referedObjectInit();
		System.assertEquals('Contact', apCreateController.refType);
		String contactName = [SELECT Name FROM Contact LIMIT 1].Name;

		System.assert( apCreateController.relatedObjNameList.size() == 1 );
		System.assert( apCreateController.relatedObjNameList[0].containsIgnoreCase(contactName));

		ApexPages.currentPage().getParameters().put( 'id', null );
		ApexPages.currentPage().getParameters().put( 'refId', account.Id + ',' + account2.Id );
		ApexPages.currentPage().getParameters().put( 'refType', null );

		apCreateController = new ActionPlanCreationController( new Apexpages.StandardController( new ActionPlan__c() ) );
		apCreateController.referedObjectInit();
		System.assertEquals('Account', apCreateController.refType);

		System.assert( apCreateController.relatedObjNameList.size() == 2 );

		ApexPages.currentPage().getParameters().put( 'id', null );
		ApexPages.currentPage().getParameters().put( 'refId', lead.Id );
		ApexPages.currentPage().getParameters().put( 'refType', 'Lead' );

		apCreateController = new ActionPlanCreationController( new Apexpages.StandardController( new ActionPlan__c() ) );
		apCreateController.referedObjectInit();

		System.assert( apCreateController.relatedObjNameList.size() == 1 );

		ApexPages.currentPage().getParameters().put( 'id', null );
		ApexPages.currentPage().getParameters().put( 'refId', opportunity.Id );
		ApexPages.currentPage().getParameters().put( 'refType', 'Opportunity' );

		apCreateController = new ActionPlanCreationController( new Apexpages.StandardController( new ActionPlan__c() ) );
		apCreateController.referedObjectInit();

		ApexPages.currentPage().getParameters().put( 'id', null );
		ApexPages.currentPage().getParameters().put( 'refId', testCase.Id );
		ApexPages.currentPage().getParameters().put( 'refType', 'Case' );

		apCreateController = new ActionPlanCreationController( new Apexpages.StandardController( new ActionPlan__c() ) );
		apCreateController.referedObjectInit();

		System.assertEquals( 1, apCreateController.relatedObjNameList.size() );

		ApexPages.currentPage().getParameters().put( 'id', null );
		ApexPages.currentPage().getParameters().put( 'refId', contract.Id );
		ApexPages.currentPage().getParameters().put( 'refType', 'Contract' );

		apCreateController = new ActionPlanCreationController( new Apexpages.StandardController( new ActionPlan__c() ) );
		apCreateController.referedObjectInit();

		Test.StopTest();

		System.assertEquals( 1, apCreateController.relatedObjNameList.size() );

	}

	@IsTest
	private static void testCustomMessage(){

		try{
			Account c = new Account();
			insert c;
		}
		catch( DmlException e1 ) {
			try{
				throw new ActionPlanCreationController.FieldCustomValidationException( e1 );
			}
			catch( ActionPlanCreationController.FieldCustomValidationException e2 ){
				System.assert( e2.getCustomMessage() != '' );
			}

		}
	}

	@IsTest
	private static void testSetTaskRecordType() {

		Test.startTest();

		ActionPlansTestUtilities testutil =  new ActionPlansTestUtilities();

		Test.setCurrentPage(Page.ActionPlanCreation);

		ActionPlan__c ap = testutil.createNewActionPlan( 'contact',  5 );

		ApexPages.currentPage().getParameters().put( 'id', ap.Id );
		ActionPlanCreationController apCreateController = new ActionPlanCreationController( new Apexpages.StandardController( ap ) );

		apCreateController.refreshRelatedObjectsLookUp();
		apCreateController.actionPlan.TaskRecordTypeID__c = ActionPlansTestUtilities.getNonDefaultAvailableTaskRecordType();
		apCreateController.actionPlan.SkipWeekends__c = true;
		apCreateController.actionPlan.SkipDay__c = 'Start of next week';
		apCreateController.getTasks();

		System.assert( !apCreateController.getTasks().isEmpty() );

		apCreateController.save();

		Test.stopTest();

		if(ActionPlansUtilities.HAS_RECORD_TYPE){
			if(ActionPlansTestUtilities.getNonDefaultAvailableTaskRecordType() != null){
				String taskQuery = 'SELECT Id, RecordTypeId FROM Task';

				for(SObject t : Database.query(taskQuery)){
					System.debug([SELECT Id, Name FROM RecordType WHERE Id = :(Id)t.get('RecordTypeId')].Name);
					System.assertNotEquals(ActionPlansUtilities.getDefaultTaskRecordTypeId(), t.get('RecordTypeId'), 'Record Type is default');
				}
			}
			System.assertNotEquals(0, ActionPlansUtilities.getTaskRTPicklistValues().size());
		} else {
			System.assertEquals(0, ActionPlansUtilities.getTaskRTPicklistValues().size());
		}
	}

	@IsTest
	private static void testForceNoRecordTypes(){
		ActionPlansTestUtilities.forceHasRecordType = false;

		System.debug('hasrt: ' + ActionPlansUtilities.HAS_RECORD_TYPE);

		ActionPlansUtilities.getTaskRecordTypeStatusDefaultValues();
		ActionPlansUtilities.getTaskRecordTypePriorityDefaultValues();

		Test.startTest();

		ActionPlansTestUtilities testutil =  new ActionPlansTestUtilities();

		Test.setCurrentPage(Page.ActionPlanCreation);

		ActionPlan__c actionPlan = testutil.createNewActionPlan( 'contact', 2 );

		ApexPages.currentPage().getParameters().put( 'id', actionPlan.Id );
		ActionPlanCreationController apCreateController = new ActionPlanCreationController( new Apexpages.StandardController( actionPlan) );

		Test.stopTest();
		System.assertEquals( null, apCreateController.getDefaultTaskRecordTypeId() );

		System.assert(!ActionPlansUtilities.HAS_RECORD_TYPE);

	}

	@IsTest
	static void checkMaxTasks(){

		Test.StartTest();
		Test.setCurrentPage(Page.ActionPlanCreation);

		ActionPlansTestUtilities testUtil = new ActionPlansTestUtilities();
		ActionPlan__c actionPlan = testUtil.createNewActionPlan( 'account', ActionPlansUtilities.MAX_APTASKS );

		ActionPlanCreationController apCreateController = new ActionPlanCreationController( new Apexpages.StandardController( actionPlan ) );
		System.assertNotEquals(null, apCreateController.relatedFieldName, 'should have lazy loaded relatedFieldName');
		System.assertEquals('Account__c', apCreateController.relatedFieldName, 'Should relate Account to Action Plan');

		apCreateController = new ActionPlanCreationController( new Apexpages.StandardController( actionPlan ) );
		apCreateController.save();
		Test.stopTest();

	}

	@IsTest
	static void checkMaxTasksError(){

		Test.StartTest();
		Test.setCurrentPage(Page.ActionPlanCreation);

		ActionPlansTestUtilities testUtil = new ActionPlansTestUtilities();
		ActionPlan__c actionPlan = testUtil.createNewActionPlan( 'account', ActionPlansUtilities.MAX_APTASKS + 1 );

		ActionPlanCreationController apCreateController = new ActionPlanCreationController( new Apexpages.StandardController( actionPlan ) );
		System.assertNotEquals(null, apCreateController.relatedFieldName, 'should have lazy loaded relatedFieldName');
		System.assertEquals('Account__c', apCreateController.relatedFieldName, 'Should relate Account to Action Plan');

		apCreateController = new ActionPlanCreationController( new Apexpages.StandardController( actionPlan ) );
		apCreateController.getTasks();
		apCreateController.addTask();
		Test.stopTest();
		String errorMsg = apCreateController.getErrorMsg();
		System.debug(errorMsg);
		System.debug(String.valueof(ActionPlansUtilities.MAX_APTASKS));
		System.assert(errorMsg.containsIgnoreCase(String.valueOf(ActionPlansUtilities.MAX_APTASKS)));

	}

}