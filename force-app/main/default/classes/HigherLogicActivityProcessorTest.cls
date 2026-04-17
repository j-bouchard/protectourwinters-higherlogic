@IsTest
private class HigherLogicActivityProcessorTest {

    private static HigherLogicConfig.Settings buildCfg(String secret) {
        HigherLogicConfig.Settings s = new HigherLogicConfig.Settings();
        s.sharedSecret = secret;
        s.accountRecordTypeDeveloperName = 'Higher_Logic_Community';
        s.campaignEventRecordTypeDeveloperName = 'Event';
        return s;
    }

    // ===================================================
    // decideRoute
    // ===================================================
    @IsTest static void decideRoute_communityCreate() {
        System.assertEquals(
            HigherLogicActivityProcessor.Route.CREATE_COMMUNITY_ACCOUNT,
            HigherLogicActivityProcessor.decideRoute('CommunityCreate', null));
        System.assertEquals(
            HigherLogicActivityProcessor.Route.CREATE_COMMUNITY_ACCOUNT,
            HigherLogicActivityProcessor.decideRoute('somecreate', 'Community'));
    }
    @IsTest static void decideRoute_contactCreate() {
        System.assertEquals(
            HigherLogicActivityProcessor.Route.CREATE_USER_CONTACT,
            HigherLogicActivityProcessor.decideRoute('contactcreate', null));
        System.assertEquals(
            HigherLogicActivityProcessor.Route.CREATE_USER_CONTACT,
            HigherLogicActivityProcessor.decideRoute('xcreatey', 'contact'));
    }
    @IsTest static void decideRoute_communityMemberJoin() {
        System.assertEquals(
            HigherLogicActivityProcessor.Route.JOIN_COMMUNITY_LINK_CONTACT,
            HigherLogicActivityProcessor.decideRoute('communitymemberjoin', null));
        System.assertEquals(
            HigherLogicActivityProcessor.Route.JOIN_COMMUNITY_LINK_CONTACT,
            HigherLogicActivityProcessor.decideRoute('communityjoin', null));
        System.assertEquals(
            HigherLogicActivityProcessor.Route.JOIN_COMMUNITY_LINK_CONTACT,
            HigherLogicActivityProcessor.decideRoute('xjoiny', 'communitymember'));
    }
    @IsTest static void decideRoute_eventCreate() {
        System.assertEquals(
            HigherLogicActivityProcessor.Route.CREATE_EVENT_CAMPAIGN,
            HigherLogicActivityProcessor.decideRoute('eventcreate', null));
        System.assertEquals(
            HigherLogicActivityProcessor.Route.CREATE_EVENT_CAMPAIGN,
            HigherLogicActivityProcessor.decideRoute('create', 'calendarevent'));
        System.assertEquals(
            HigherLogicActivityProcessor.Route.CREATE_EVENT_CAMPAIGN,
            HigherLogicActivityProcessor.decideRoute('create', 'Event'));
    }
    @IsTest static void decideRoute_registerForEvent() {
        System.assertEquals(
            HigherLogicActivityProcessor.Route.REGISTER_FOR_EVENT,
            HigherLogicActivityProcessor.decideRoute('EventRegister', 'Event'));
        System.assertEquals(
            HigherLogicActivityProcessor.Route.REGISTER_FOR_EVENT,
            HigherLogicActivityProcessor.decideRoute('RegistrationCreate', null));
        System.assertEquals(
            HigherLogicActivityProcessor.Route.REGISTER_FOR_EVENT,
            HigherLogicActivityProcessor.decideRoute('EventRSVP', 'CalendarEvent'));
    }
    @IsTest static void decideRoute_attendEvent() {
        System.assertEquals(
            HigherLogicActivityProcessor.Route.ATTEND_EVENT,
            HigherLogicActivityProcessor.decideRoute('EventAttend', 'Event'));
        System.assertEquals(
            HigherLogicActivityProcessor.Route.ATTEND_EVENT,
            HigherLogicActivityProcessor.decideRoute('EventAttendanceCreate', 'EventAttendee'));
    }

    @IsTest static void decideRoute_ignoreUnknown() {
        System.assertEquals(
            HigherLogicActivityProcessor.Route.IGNORE,
            HigherLogicActivityProcessor.decideRoute('unknownthing', 'something'));
        System.assertEquals(
            HigherLogicActivityProcessor.Route.IGNORE,
            HigherLogicActivityProcessor.decideRoute(null, null));
    }

    // ===================================================
    // pick / asString / parseIsoToDate
    // ===================================================
    @IsTest static void pick_returnsFirstNonBlank() {
        Map<String, Object> p = new Map<String, Object>{
            'A' => '', 'B' => null, 'C' => 'value', 'D' => 'other'
        };
        System.assertEquals('value',
            HigherLogicActivityProcessor.pick(p, new List<String>{'A','B','C','D'}));
        System.assertEquals(null,
            HigherLogicActivityProcessor.pick(p, new List<String>{'A','B'}));
    }

    @IsTest static void asString_handlesVariants() {
        System.assertEquals(null, HigherLogicActivityProcessor.asString(null));
        System.assertEquals('hi', HigherLogicActivityProcessor.asString('hi'));
        System.assertEquals('42', HigherLogicActivityProcessor.asString(42));
        System.assertEquals('true', HigherLogicActivityProcessor.asString(true));
    }

    @IsTest static void parseIso_handlesVariants() {
        System.assertEquals(Date.newInstance(2026,4,15),
            HigherLogicActivityProcessor.parseIsoToDate('2026-04-15T12:00:00Z'));
        System.assertEquals(Date.newInstance(2026,4,15),
            HigherLogicActivityProcessor.parseIsoToDate('2026-04-15T12:00:00.123Z'));
        System.assertEquals(Date.newInstance(2026,4,15),
            HigherLogicActivityProcessor.parseIsoToDate('2026-04-15T12:00:00+00:00'));
        System.assertEquals(null, HigherLogicActivityProcessor.parseIsoToDate(''));
        System.assertEquals(null, HigherLogicActivityProcessor.parseIsoToDate('not a date'));
    }

    // ===================================================
    // ===================================================
    // Webhook body handling
    // ===================================================
    private static RestRequest buildReq(String raw) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/higherlogic/activity';
        req.httpMethod = 'POST';
        if (raw != null) req.requestBody = Blob.valueOf(raw);
        return req;
    }

    @IsTest static void webhook_blankBody_returns400() {
        RestContext.request = buildReq('');
        RestContext.response = new RestResponse();
        HigherLogicActivityWebhook.handlePost();
        System.assertEquals(400, RestContext.response.statusCode);
    }

    @IsTest static void webhook_badJson_returns400() {
        RestContext.request = buildReq('not valid json');
        RestContext.response = new RestResponse();
        HigherLogicActivityWebhook.handlePost();
        System.assertEquals(400, RestContext.response.statusCode);
    }

    @IsTest static void webhook_ignoreRoute_returns200() {
        String body = JSON.serialize(new Map<String,Object>{ 'ActivityCode' => 'UnknownThing' });
        RestContext.request = buildReq(body);
        RestContext.response = new RestResponse();
        HigherLogicActivityWebhook.handlePost();
        System.assertEquals(200, RestContext.response.statusCode);
        System.assertEquals('Ignored', RestContext.response.responseBody.toString());
    }

    @IsTest static void webhook_enqueuesJob() {
        HigherLogicConfig.testOverride = buildCfg('s3cret');
        String body = JSON.serialize(new Map<String,Object>{
            'ActivityCode' => 'CommunityCreate',
            'CommunityKey' => 'C-WEBHOOK-001',
            'CommunityName' => 'Webhook Test Community'
        });
        RestContext.request = buildReq(body);
        RestContext.response = new RestResponse();
        Test.startTest();
        HigherLogicActivityWebhook.handlePost();
        Test.stopTest();
        System.assertEquals(200, RestContext.response.statusCode);
        List<Account> a = [SELECT Id, Name FROM Account WHERE HL_Community_ID__c = 'C-WEBHOOK-001'];
        System.assertEquals(1, a.size());
        System.assertEquals('Webhook Test Community', a[0].Name);
    }

    // ===================================================
    // Route 1 — Community -> Account
    // ===================================================
    @IsTest static void route1_insertsNewAccount() {
        HigherLogicConfig.testOverride = buildCfg('s');
        Map<String,Object> payload = new Map<String,Object>{
            'CommunityKey' => 'C-001',
            'CommunityName' => 'Test Community'
        };
        Test.startTest();
        System.enqueueJob(new HigherLogicActivityProcessor.Job(
            HigherLogicActivityProcessor.Route.CREATE_COMMUNITY_ACCOUNT, payload));
        Test.stopTest();
        List<Account> a = [SELECT Name FROM Account WHERE HL_Community_ID__c = 'C-001'];
        System.assertEquals(1, a.size());
        System.assertEquals('Test Community', a[0].Name);
    }

    @IsTest static void route1_upsertsExistingAccount() {
        HigherLogicConfig.testOverride = buildCfg('s');
        Account pre = new Account(Name = 'Old', HL_Community_ID__c = 'C-002');
        insert pre;
        Map<String,Object> payload = new Map<String,Object>{
            'CommunityKey' => 'C-002',
            'CommunityName' => 'New Name'
        };
        Test.startTest();
        System.enqueueJob(new HigherLogicActivityProcessor.Job(
            HigherLogicActivityProcessor.Route.CREATE_COMMUNITY_ACCOUNT, payload));
        Test.stopTest();
        Account after = [SELECT Name FROM Account WHERE Id = :pre.Id];
        System.assertEquals('New Name', after.Name);
        System.assertEquals(1, [SELECT COUNT() FROM Account WHERE HL_Community_ID__c = 'C-002']);
    }

    @IsTest static void route1_noCommunityId_plainInsert() {
        HigherLogicConfig.testOverride = buildCfg('s');
        Test.startTest();
        System.enqueueJob(new HigherLogicActivityProcessor.Job(
            HigherLogicActivityProcessor.Route.CREATE_COMMUNITY_ACCOUNT,
            new Map<String,Object>{}));
        Test.stopTest();
        System.assert(![SELECT Id FROM Account WHERE Name = 'Higher Logic Community'].isEmpty());
    }

    // ===================================================
    // Route 2 — Contact
    // ===================================================
    @IsTest static void route2_createsNewContact() {
        HigherLogicConfig.testOverride = buildCfg('s');
        Map<String,Object> payload = new Map<String,Object>{
            'ContributorKey' => 'U-001',
            'pb_emailaddress' => 'new@example.com',
            'pb_firstname' => 'New',
            'pb_lastname' => 'User',
            'pb_phone1' => '555-0001',
            'pb_city' => 'Denver'
        };
        Test.startTest();
        System.enqueueJob(new HigherLogicActivityProcessor.Job(
            HigherLogicActivityProcessor.Route.CREATE_USER_CONTACT, payload));
        Test.stopTest();
        List<Contact> c = [SELECT FirstName, Email, MailingCity
                           FROM Contact WHERE HL_Contact_ID__c = 'U-001'];
        System.assertEquals(1, c.size());
        System.assertEquals('New', c[0].FirstName);
        System.assertEquals('new@example.com', c[0].Email);
        System.assertEquals('Denver', c[0].MailingCity);
    }

    @IsTest static void route2_matchesByHLContactId_evenOnEmailChange() {
        HigherLogicConfig.testOverride = buildCfg('s');
        Contact pre = new Contact(FirstName = 'Old', LastName = 'User',
            Email = 'old@example.com', HL_Contact_ID__c = 'U-002');
        insert pre;
        Map<String,Object> payload = new Map<String,Object>{
            'ContributorKey' => 'U-002',
            'pb_emailaddress' => 'changed@example.com',
            'pb_firstname' => 'Changed'
        };
        Test.startTest();
        System.enqueueJob(new HigherLogicActivityProcessor.Job(
            HigherLogicActivityProcessor.Route.CREATE_USER_CONTACT, payload));
        Test.stopTest();
        Contact after = [SELECT Email, FirstName FROM Contact WHERE Id = :pre.Id];
        System.assertEquals('changed@example.com', after.Email);
        System.assertEquals('Changed', after.FirstName);
        System.assertEquals(1, [SELECT COUNT() FROM Contact WHERE HL_Contact_ID__c = 'U-002']);
    }

    @IsTest static void route2_fallsBackToStandardEmail() {
        HigherLogicConfig.testOverride = buildCfg('s');
        // Contact has only standard Email; no HL_Contact_ID, no HomeEmail
        Contact pre = new Contact(FirstName = 'Standard', LastName = 'Only',
            Email = 'standard@example.com');
        insert pre;
        Map<String,Object> payload = new Map<String,Object>{
            'pb_emailaddress' => 'standard@example.com',
            'pb_firstname' => 'Updated'
        };
        Test.startTest();
        System.enqueueJob(new HigherLogicActivityProcessor.Job(
            HigherLogicActivityProcessor.Route.CREATE_USER_CONTACT, payload));
        Test.stopTest();
        Contact after = [SELECT FirstName FROM Contact WHERE Id = :pre.Id];
        System.assertEquals('Updated', after.FirstName);
    }

    @IsTest static void route2_defaultsLastName() {
        HigherLogicConfig.testOverride = buildCfg('s');
        Map<String,Object> payload = new Map<String,Object>{
            'ContributorKey' => 'U-003',
            'pb_emailaddress' => 'anon@example.com'
        };
        Test.startTest();
        System.enqueueJob(new HigherLogicActivityProcessor.Job(
            HigherLogicActivityProcessor.Route.CREATE_USER_CONTACT, payload));
        Test.stopTest();
        Contact c = [SELECT LastName FROM Contact WHERE HL_Contact_ID__c = 'U-003'];
        // Some orgs auto-normalize name casing via triggers/flows; compare case-insensitive.
        System.assertEquals('hl user', c.LastName.toLowerCase());
    }

    // ===================================================
    // Route 3 — Affiliation
    // ===================================================
    @IsTest static void route3_createsAffiliation() {
        HigherLogicConfig.testOverride = buildCfg('s');
        Account a = new Account(Name = 'Community', HL_Community_ID__c = 'C-100');
        insert a;
        Contact c = new Contact(FirstName = 'J', LastName = 'One',
            Email = 'j@example.com', HL_Contact_ID__c = 'U-100');
        insert c;
        Test.startTest();
        System.enqueueJob(new HigherLogicActivityProcessor.Job(
            HigherLogicActivityProcessor.Route.JOIN_COMMUNITY_LINK_CONTACT,
            new Map<String,Object>{ 'CommunityKey' => 'C-100', 'ContributorKey' => 'U-100' }));
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM npe5__Affiliation__c
            WHERE npe5__Contact__c = :c.Id AND npe5__Organization__c = :a.Id]);
    }

    @IsTest static void route3_noAccount_noOp() {
        HigherLogicConfig.testOverride = buildCfg('s');
        Contact c = new Contact(FirstName = 'X', LastName = 'Y',
            Email = 'x@example.com', HL_Contact_ID__c = 'U-200');
        insert c;
        Test.startTest();
        System.enqueueJob(new HigherLogicActivityProcessor.Job(
            HigherLogicActivityProcessor.Route.JOIN_COMMUNITY_LINK_CONTACT,
            new Map<String,Object>{ 'CommunityKey' => 'NOPE', 'ContributorKey' => 'U-200' }));
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM npe5__Affiliation__c WHERE npe5__Contact__c = :c.Id]);
    }

    @IsTest static void route3_createsContactWhenNoMatch_thenAffiliates() {
        HigherLogicConfig.testOverride = buildCfg('s');
        Account a = new Account(Name = 'Community', HL_Community_ID__c = 'C-300');
        insert a;
        Test.startTest();
        System.enqueueJob(new HigherLogicActivityProcessor.Job(
            HigherLogicActivityProcessor.Route.JOIN_COMMUNITY_LINK_CONTACT,
            new Map<String,Object>{
                'CommunityKey' => 'C-300',
                'ContributorKey' => 'U-300-NEW',
                'pb_emailaddress' => 'joiner@example.com',
                'pb_firstname' => 'First',
                'pb_lastname' => 'Joiner'
            }));
        Test.stopTest();
        List<Contact> created = [SELECT Id, FirstName, LastName, Email
                                 FROM Contact WHERE HL_Contact_ID__c = 'U-300-NEW'];
        System.assertEquals(1, created.size());
        System.assertEquals('First', created[0].FirstName);
        System.assertEquals('joiner@example.com', created[0].Email);
        System.assertEquals(1, [SELECT COUNT() FROM npe5__Affiliation__c
            WHERE npe5__Contact__c = :created[0].Id AND npe5__Organization__c = :a.Id]);
    }

    @IsTest static void route3_createsContactWithDefaultLastName() {
        HigherLogicConfig.testOverride = buildCfg('s');
        Account a = new Account(Name = 'Community', HL_Community_ID__c = 'C-310');
        insert a;
        Test.startTest();
        System.enqueueJob(new HigherLogicActivityProcessor.Job(
            HigherLogicActivityProcessor.Route.JOIN_COMMUNITY_LINK_CONTACT,
            new Map<String,Object>{
                'CommunityKey' => 'C-310',
                'ContributorKey' => 'U-310-ANON'
            }));
        Test.stopTest();
        Contact c = [SELECT LastName FROM Contact WHERE HL_Contact_ID__c = 'U-310-ANON'];
        System.assertEquals('hl user', c.LastName.toLowerCase());
    }

    @IsTest static void route3_dedupesExistingAffiliation() {
        HigherLogicConfig.testOverride = buildCfg('s');
        Account a = new Account(Name = 'Community', HL_Community_ID__c = 'C-400');
        insert a;
        Contact c = new Contact(FirstName = 'A', LastName = 'B',
            Email = 'a@example.com', HL_Contact_ID__c = 'U-400');
        insert c;
        insert new npe5__Affiliation__c(npe5__Contact__c = c.Id, npe5__Organization__c = a.Id);
        Test.startTest();
        System.enqueueJob(new HigherLogicActivityProcessor.Job(
            HigherLogicActivityProcessor.Route.JOIN_COMMUNITY_LINK_CONTACT,
            new Map<String,Object>{ 'CommunityKey' => 'C-400', 'ContributorKey' => 'U-400' }));
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM npe5__Affiliation__c
            WHERE npe5__Contact__c = :c.Id AND npe5__Organization__c = :a.Id]);
    }

    // ===================================================
    // Route 4 — Campaign + Event Partner
    // ===================================================
    @IsTest static void route4_createsCampaignAndPartner() {
        HigherLogicConfig.testOverride = buildCfg('s');
        Account a = new Account(Name = 'Community', HL_Community_ID__c = 'C-500');
        insert a;
        Map<String,Object> payload = new Map<String,Object>{
            'EventKey' => 'E-001',
            'Title' => 'Fundraiser',
            'Date01' => '2026-05-01T12:00:00Z',
            'CommunityKey' => 'C-500',
            'ActivityDescription' => 'Join us',
            'LinkUrl' => 'https://example.com'
        };
        Test.startTest();
        System.enqueueJob(new HigherLogicActivityProcessor.Job(
            HigherLogicActivityProcessor.Route.CREATE_EVENT_CAMPAIGN, payload));
        Test.stopTest();
        List<Campaign> cs = [SELECT Id, Name, Description FROM Campaign WHERE HL_Event_ID__c = 'E-001'];
        System.assertEquals(1, cs.size());
        System.assertEquals('Fundraiser', cs[0].Name);
        System.assert(cs[0].Description.contains('HL Link:'));
        System.assertEquals(1, [SELECT COUNT() FROM conference360__Sponsor__c
            WHERE conference360__Account__c = :a.Id AND Event_Campaign__c = :cs[0].Id]);
    }

    @IsTest static void route4_noCommunity_skipsPartner() {
        HigherLogicConfig.testOverride = buildCfg('s');
        Test.startTest();
        System.enqueueJob(new HigherLogicActivityProcessor.Job(
            HigherLogicActivityProcessor.Route.CREATE_EVENT_CAMPAIGN,
            new Map<String,Object>{ 'EventKey' => 'E-002', 'Title' => 'Lonely Event' }));
        Test.stopTest();
        Campaign c = [SELECT Id FROM Campaign WHERE HL_Event_ID__c = 'E-002'];
        System.assertEquals(0, [SELECT COUNT() FROM conference360__Sponsor__c
            WHERE Event_Campaign__c = :c.Id]);
    }

    @IsTest static void route4_seedsCampaignMemberStatuses() {
        HigherLogicConfig.testOverride = buildCfg('s');
        Test.startTest();
        System.enqueueJob(new HigherLogicActivityProcessor.Job(
            HigherLogicActivityProcessor.Route.CREATE_EVENT_CAMPAIGN,
            new Map<String,Object>{ 'EventKey' => 'E-SEED-1', 'Title' => 'Seed Test' }));
        Test.stopTest();
        Campaign c = [SELECT Id FROM Campaign WHERE HL_Event_ID__c = 'E-SEED-1'];
        Map<String, CampaignMemberStatus> byLabel = new Map<String, CampaignMemberStatus>();
        for (CampaignMemberStatus cms : [
            SELECT Label, HasResponded FROM CampaignMemberStatus WHERE CampaignId = :c.Id
        ]) {
            byLabel.put(cms.Label, cms);
        }
        System.assert(byLabel.containsKey('Registered'));
        System.assert(byLabel.containsKey('Attended'));
        System.assertEquals(false, byLabel.get('Registered').HasResponded);
        System.assertEquals(true, byLabel.get('Attended').HasResponded);
    }

    @IsTest static void route4_seedsCampaignMemberStatusesIdempotent() {
        HigherLogicConfig.testOverride = buildCfg('s');
        // First fire creates Campaign and seeds statuses
        System.enqueueJob(new HigherLogicActivityProcessor.Job(
            HigherLogicActivityProcessor.Route.CREATE_EVENT_CAMPAIGN,
            new Map<String,Object>{ 'EventKey' => 'E-SEED-2', 'Title' => 'Seed Idempotent' }));
        Test.startTest();
        // Second fire should not duplicate statuses
        System.enqueueJob(new HigherLogicActivityProcessor.Job(
            HigherLogicActivityProcessor.Route.CREATE_EVENT_CAMPAIGN,
            new Map<String,Object>{ 'EventKey' => 'E-SEED-2', 'Title' => 'Seed Idempotent' }));
        Test.stopTest();
        Campaign c = [SELECT Id FROM Campaign WHERE HL_Event_ID__c = 'E-SEED-2'];
        Integer registered = [SELECT COUNT() FROM CampaignMemberStatus
            WHERE CampaignId = :c.Id AND Label = 'Registered'];
        Integer attended = [SELECT COUNT() FROM CampaignMemberStatus
            WHERE CampaignId = :c.Id AND Label = 'Attended'];
        System.assertEquals(1, registered);
        System.assertEquals(1, attended);
    }

    @IsTest static void route4_dedupesExistingPartner() {
        HigherLogicConfig.testOverride = buildCfg('s');
        Account a = new Account(Name = 'Community', HL_Community_ID__c = 'C-600');
        insert a;
        Campaign pre = new Campaign(Name = 'Pre',
            OKR_Type__c = 'fundraise', HL_Event_Type__c = 'Chapter Meeting',
            Host__c = 'Community Hosted', StartDate = Date.today(),
            HL_Event_ID__c = 'E-003');
        insert pre;
        insert new conference360__Sponsor__c(
            conference360__Account__c = a.Id, Event_Campaign__c = pre.Id);
        Test.startTest();
        System.enqueueJob(new HigherLogicActivityProcessor.Job(
            HigherLogicActivityProcessor.Route.CREATE_EVENT_CAMPAIGN,
            new Map<String,Object>{ 'EventKey' => 'E-003', 'Title' => 'Re-fire', 'CommunityKey' => 'C-600' }));
        Test.stopTest();
        System.assertEquals(1, [SELECT COUNT() FROM conference360__Sponsor__c
            WHERE conference360__Account__c = :a.Id AND Event_Campaign__c = :pre.Id]);
    }

    // ===================================================
    // Route 5 \u2014 Register / Attend \u2192 CampaignMember
    // ===================================================
    private static Campaign makeEventCampaign(String eventKey) {
        Campaign c = new Campaign(
            Name = 'Event ' + eventKey,
            OKR_Type__c = 'fundraise',
            HL_Event_Type__c = 'Chapter Meeting',
            Host__c = 'Community Hosted',
            StartDate = Date.today(),
            HL_Event_ID__c = eventKey
        );
        insert c;
        insert new CampaignMemberStatus(CampaignId = c.Id, Label = 'Registered',
            SortOrder = 3, HasResponded = false);
        insert new CampaignMemberStatus(CampaignId = c.Id, Label = 'Attended',
            SortOrder = 4, HasResponded = true);
        return c;
    }

    @IsTest static void route5_registerInsertsNewCampaignMember() {
        HigherLogicConfig.testOverride = buildCfg('s');
        Campaign camp = makeEventCampaign('E-R5-1');
        Contact c = new Contact(FirstName = 'R', LastName = 'One',
            Email = 'r1@example.com', HL_Contact_ID__c = 'U-R5-1');
        insert c;
        Test.startTest();
        System.enqueueJob(new HigherLogicActivityProcessor.Job(
            HigherLogicActivityProcessor.Route.REGISTER_FOR_EVENT,
            new Map<String,Object>{ 'EventKey' => 'E-R5-1', 'ContributorKey' => 'U-R5-1' }));
        Test.stopTest();
        List<CampaignMember> cms = [SELECT Status FROM CampaignMember
            WHERE CampaignId = :camp.Id AND ContactId = :c.Id];
        System.assertEquals(1, cms.size());
        System.assertEquals('Registered', cms[0].Status);
    }

    @IsTest static void route5_attendUpgradesExistingRegistered() {
        HigherLogicConfig.testOverride = buildCfg('s');
        Campaign camp = makeEventCampaign('E-R5-2');
        Contact c = new Contact(FirstName = 'R', LastName = 'Two',
            Email = 'r2@example.com', HL_Contact_ID__c = 'U-R5-2');
        insert c;
        insert new CampaignMember(CampaignId = camp.Id, ContactId = c.Id, Status = 'Registered');
        Test.startTest();
        System.enqueueJob(new HigherLogicActivityProcessor.Job(
            HigherLogicActivityProcessor.Route.ATTEND_EVENT,
            new Map<String,Object>{ 'EventKey' => 'E-R5-2', 'ContributorKey' => 'U-R5-2' }));
        Test.stopTest();
        CampaignMember cm = [SELECT Status FROM CampaignMember
            WHERE CampaignId = :camp.Id AND ContactId = :c.Id];
        System.assertEquals('Attended', cm.Status);
    }

    @IsTest static void route5_registerDoesNotDowngradeAttended() {
        HigherLogicConfig.testOverride = buildCfg('s');
        Campaign camp = makeEventCampaign('E-R5-3');
        Contact c = new Contact(FirstName = 'R', LastName = 'Three',
            Email = 'r3@example.com', HL_Contact_ID__c = 'U-R5-3');
        insert c;
        insert new CampaignMember(CampaignId = camp.Id, ContactId = c.Id, Status = 'Attended');
        Test.startTest();
        System.enqueueJob(new HigherLogicActivityProcessor.Job(
            HigherLogicActivityProcessor.Route.REGISTER_FOR_EVENT,
            new Map<String,Object>{ 'EventKey' => 'E-R5-3', 'ContributorKey' => 'U-R5-3' }));
        Test.stopTest();
        CampaignMember cm = [SELECT Status FROM CampaignMember
            WHERE CampaignId = :camp.Id AND ContactId = :c.Id];
        System.assertEquals('Attended', cm.Status);
    }

    @IsTest static void route5_createsContactIfMissing() {
        HigherLogicConfig.testOverride = buildCfg('s');
        Campaign camp = makeEventCampaign('E-R5-4');
        Test.startTest();
        System.enqueueJob(new HigherLogicActivityProcessor.Job(
            HigherLogicActivityProcessor.Route.REGISTER_FOR_EVENT,
            new Map<String,Object>{
                'EventKey' => 'E-R5-4',
                'ContributorKey' => 'U-R5-4',
                'pb_emailaddress' => 'brand.new@example.com',
                'pb_firstname' => 'Brand',
                'pb_lastname' => 'New'
            }));
        Test.stopTest();
        Contact created = [SELECT Id FROM Contact WHERE HL_Contact_ID__c = 'U-R5-4'];
        System.assertEquals(1, [SELECT COUNT() FROM CampaignMember
            WHERE CampaignId = :camp.Id AND ContactId = :created.Id AND Status = 'Registered']);
    }

    @IsTest static void route5_noCampaignIsNoOp() {
        HigherLogicConfig.testOverride = buildCfg('s');
        Contact c = new Contact(FirstName = 'X', LastName = 'Y',
            Email = 'xy@example.com', HL_Contact_ID__c = 'U-R5-5');
        insert c;
        Test.startTest();
        System.enqueueJob(new HigherLogicActivityProcessor.Job(
            HigherLogicActivityProcessor.Route.REGISTER_FOR_EVENT,
            new Map<String,Object>{ 'EventKey' => 'DOES-NOT-EXIST', 'ContributorKey' => 'U-R5-5' }));
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM CampaignMember WHERE ContactId = :c.Id]);
    }

    // ===================================================
    // RecordType lookup
    // ===================================================
    @IsTest static void config_getReadsFromOrgWhenNoOverride() {
        // Exercises the SOQL path of HigherLogicConfig.get() without a test override.
        HigherLogicConfig.testOverride = null;
        HigherLogicConfig.Settings s = HigherLogicConfig.get();
        System.assertNotEquals(null, s);
    }

    @IsTest static void recordType_lookupExecutes() {
        HigherLogicConfig.Settings s = buildCfg('s');
        s.campaignEventRecordTypeDeveloperName = 'Event';
        HigherLogicConfig.testOverride = s;
        HigherLogicActivityProcessor.resetRecordTypeCache();
        HigherLogicActivityProcessor.getAccountRecordTypeId();
        HigherLogicActivityProcessor.getCampaignEventRecordTypeId();
        // second calls hit cache
        HigherLogicActivityProcessor.getAccountRecordTypeId();
        HigherLogicActivityProcessor.getCampaignEventRecordTypeId();
    }
}
