public without sharing class HigherLogicActivityProcessor {

    @TestVisible private static final String STATUS_REGISTERED = 'Registered';
    @TestVisible private static final String STATUS_ATTENDED   = 'Attended';

    public enum Route {
        CREATE_COMMUNITY_ACCOUNT,
        CREATE_USER_CONTACT,
        JOIN_COMMUNITY_LINK_CONTACT,
        CREATE_EVENT_CAMPAIGN,
        REGISTER_FOR_EVENT,
        ATTEND_EVENT,
        IGNORE
    }

    public static Route decideRoute(String activityCode, String objectType) {
        String code = (activityCode == null) ? '' : activityCode.toLowerCase();
        String obj  = (objectType == null) ? '' : objectType.toLowerCase();

        if (code == 'communitycreate' || (code.contains('create') && obj == 'community')) {
            return Route.CREATE_COMMUNITY_ACCOUNT;
        }
        if (code == 'contactcreate' || (code.contains('create') && obj == 'contact')) {
            return Route.CREATE_USER_CONTACT;
        }
        if (code == 'communitymemberjoin' || code == 'communityjoin'
            || (code.contains('join') && obj == 'communitymember')) {
            return Route.JOIN_COMMUNITY_LINK_CONTACT;
        }
        if (code == 'eventcreate'
            || (code.contains('create') && (obj == 'calendarevent' || obj == 'event'))) {
            return Route.CREATE_EVENT_CAMPAIGN;
        }
        if (code.contains('attend')) {
            return Route.ATTEND_EVENT;
        }
        if (code.contains('regist') || code.contains('rsvp')) {
            return Route.REGISTER_FOR_EVENT;
        }
        return Route.IGNORE;
    }

    public class Job implements Queueable {
        private Route route;
        private Map<String, Object> payload;
        public Job(Route route, Map<String, Object> payload) {
            this.route = route;
            this.payload = payload;
        }
        public void execute(QueueableContext qc) {
            System.debug(LoggingLevel.INFO, '[HL] Job start. route=' + String.valueOf(route));
            try {
                if (route == HigherLogicActivityProcessor.Route.CREATE_COMMUNITY_ACCOUNT) {
                    createOrUpsertAccountForCommunity(payload);
                } else if (route == HigherLogicActivityProcessor.Route.CREATE_USER_CONTACT) {
                    createOrUpsertContactForUser(payload);
                } else if (route == HigherLogicActivityProcessor.Route.JOIN_COMMUNITY_LINK_CONTACT) {
                    linkContactToCommunityAccount(payload);
                } else if (route == HigherLogicActivityProcessor.Route.CREATE_EVENT_CAMPAIGN) {
                    createOrUpsertCampaignForEvent(payload);
                } else if (route == HigherLogicActivityProcessor.Route.REGISTER_FOR_EVENT) {
                    setCampaignMemberStatus(payload, STATUS_REGISTERED);
                } else if (route == HigherLogicActivityProcessor.Route.ATTEND_EVENT) {
                    setCampaignMemberStatus(payload, STATUS_ATTENDED);
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR,
                    '[HL] Job failed. route=' + String.valueOf(route) +
                    ' error=' + e.getMessage() +
                    ' stack=' + e.getStackTraceString()
                );
                throw e;
            }
        }
    }

    // ------------------------------------------------
    // 1) COMMUNITY CREATE -> ACCOUNT
    // ------------------------------------------------
    private static void createOrUpsertAccountForCommunity(Map<String, Object> payload) {
        String communityId = pick(payload, new List<String>{
            'CommunityKey','CommunityId','CommunityID','CommunityGuid','CommunityGUID','Key'
        });
        String communityName = pick(payload, new List<String>{
            'CommunityName','CommunityTitle','Community','Name','Title'
        });

        if (String.isBlank(communityName)) communityName = 'Higher Logic Community';

        Account a = new Account();
        a.Name = communityName;

        Id rtId = getAccountRecordTypeId();
        if (rtId != null) a.RecordTypeId = rtId;

        if (!String.isBlank(communityId) && hasAccountField('HL_Community_ID__c')) {
            a.put('HL_Community_ID__c', communityId);
            upsert a HL_Community_ID__c;
        } else {
            insert a;
        }
        System.debug(LoggingLevel.INFO, '[HL] Account done. accountId=' + a.Id);
    }

    // ------------------------------------------------
    // 2) CONTACT CREATE -> CONTACT
    // Match priority: HL_Contact_ID__c > npe01__HomeEmail__c > Email
    // ------------------------------------------------
    private static Id createOrUpsertContactForUser(Map<String, Object> payload) {
        String externalId = pick(payload, new List<String>{
            'ContributorKey', 'ContributorMemberKey', 'ContactKey', 'AgentContactKey', 'Key'
        });
        String email = pick(payload, new List<String>{
            'pb_emailaddress','Email','email','EmailAddress'
        });
        String firstName = pick(payload, new List<String>{
            'pb_firstname','FirstName','firstName','ContributorFirstName'
        });
        String lastName  = pick(payload, new List<String>{
            'pb_lastname','LastName','lastName','ContributorLastName'
        });
        String phone = pick(payload, new List<String>{ 'pb_phone1','Phone','phone' });
        String street  = pick(payload, new List<String>{ 'pb_address1','Address1','Street','MailingStreet' });
        String city    = pick(payload, new List<String>{ 'pb_city','City','MailingCity' });
        String state   = pick(payload, new List<String>{ 'pb_state','State','StateProvince','MailingState' });
        String postal  = pick(payload, new List<String>{ 'pb_postalcode','PostalCode','Zip','MailingPostalCode' });
        String country = pick(payload, new List<String>{ 'pb_country','Country','MailingCountry' });

        if (String.isBlank(lastName)) lastName = 'HL User';

        Contact existing = findContactForUser(externalId, email);

        if (existing != null) {
            Contact upd = new Contact(Id = existing.Id);
            if (!String.isBlank(firstName)) upd.FirstName = firstName;
            if (!String.isBlank(lastName))  upd.LastName  = lastName;
            if (!String.isBlank(phone))     upd.Phone     = phone;
            if (!String.isBlank(email)) {
                upd.Email = email;
                if (hasContactField('npe01__HomeEmail__c')) {
                    upd.put('npe01__HomeEmail__c', email);
                }
            }
            if (!String.isBlank(externalId) && hasContactField('HL_Contact_ID__c')) {
                upd.put('HL_Contact_ID__c', externalId);
            }
            if (!String.isBlank(street))  upd.MailingStreet     = street;
            if (!String.isBlank(city))    upd.MailingCity       = city;
            if (!String.isBlank(state))   upd.MailingState      = state;
            if (!String.isBlank(postal))  upd.MailingPostalCode = postal;
            if (!String.isBlank(country)) upd.MailingCountry    = country;
            update upd;
            return existing.Id;
        }

        Contact c = new Contact();
        c.FirstName = firstName;
        c.LastName  = lastName;
        c.Phone     = phone;
        if (!String.isBlank(email)) {
            c.Email = email;
            if (hasContactField('npe01__HomeEmail__c')) {
                c.put('npe01__HomeEmail__c', email);
            }
        }
        if (!String.isBlank(externalId) && hasContactField('HL_Contact_ID__c')) {
            c.put('HL_Contact_ID__c', externalId);
        }
        if (!String.isBlank(street))  c.MailingStreet     = street;
        if (!String.isBlank(city))    c.MailingCity       = city;
        if (!String.isBlank(state))   c.MailingState      = state;
        if (!String.isBlank(postal))  c.MailingPostalCode = postal;
        if (!String.isBlank(country)) c.MailingCountry    = country;
        insert c;
        return c.Id;
    }

    // ------------------------------------------------
    // 3) COMMUNITY MEMBER JOIN -> AFFILIATION
    // ------------------------------------------------
    private static void linkContactToCommunityAccount(Map<String, Object> payload) {
        String communityId = pick(payload, new List<String>{
            'CommunityKey','CommunityId','CommunityID','CommunityGuid','CommunityGUID','Key'
        });
        String externalId = pick(payload, new List<String>{
            'ContributorKey', 'ContributorMemberKey'
        });
        String email = pick(payload, new List<String>{
            'pb_emailaddress','Email','email','EmailAddress'
        });

        Id accountId = findAccountIdByCommunityId(communityId);
        if (accountId == null) {
            System.debug(LoggingLevel.WARN, '[HL] No Account found for communityId=' + communityId);
            return;
        }
        Contact match = findContactForUser(externalId, email);
        Id contactId;
        if (match != null) {
            contactId = match.Id;
        } else {
            System.debug(LoggingLevel.INFO, '[HL] No Contact match; creating from join payload');
            contactId = createOrUpsertContactForUser(payload);
        }
        if (contactId == null) {
            System.debug(LoggingLevel.WARN, '[HL] Could not resolve or create Contact for join payload');
            return;
        }
        createAffiliation(contactId, accountId);
    }

    private static void createAffiliation(Id contactId, Id accountId) {
        if (contactId == null || accountId == null) return;
        List<npe5__Affiliation__c> existing = [
            SELECT Id
            FROM npe5__Affiliation__c
            WHERE npe5__Contact__c = :contactId
              AND npe5__Organization__c = :accountId
            LIMIT 1
        ];
        if (!existing.isEmpty()) return;
        npe5__Affiliation__c aff = new npe5__Affiliation__c();
        aff.npe5__Contact__c = contactId;
        aff.npe5__Organization__c = accountId;
        insert aff;
    }

    // ------------------------------------------------
    // 4) EVENT CREATE -> CAMPAIGN + EVENT PARTNER
    // ------------------------------------------------
    private static void createOrUpsertCampaignForEvent(Map<String, Object> payload) {
        String eventKey     = pick(payload, new List<String>{ 'EventKey', 'CalendarEventKey', 'Key' });
        String title        = pick(payload, new List<String>{ 'Title', 'EventTitle', 'Name' });
        String linkUrl      = pick(payload, new List<String>{ 'LinkUrl', 'URL', 'Url' });
        String description  = pick(payload, new List<String>{ 'ActivityDescription', 'Description' });
        String startIso     = pick(payload, new List<String>{ 'Date01', 'pb_eventstart', 'StartDate', 'StartDateTime' });
        String endIso       = pick(payload, new List<String>{ 'Date02', 'pb_eventend', 'EndDate', 'EndDateTime' });
        Date startDate = parseIsoToDate(startIso);
        Date endDate   = parseIsoToDate(endIso);
        String communityId = pick(payload, new List<String>{ 'CommunityKey', 'ParentKey' });

        if (String.isBlank(title)) title = 'Higher Logic Event';
        if (startDate == null) startDate = Date.today();

        Campaign c = new Campaign();
        c.Name = title;
        c.OKR_Type__c = 'fundraise';
        c.HL_Event_Type__c = 'Chapter Meeting';
        c.Host__c = 'Community Hosted';
        if (hasCampaignField('Type'))   c.Type = 'Event';
        if (hasCampaignField('Status')) c.Status = 'Planned';
        Id campRtId = getCampaignEventRecordTypeId();
        if (campRtId != null) c.RecordTypeId = campRtId;
        c.StartDate = startDate;
        if (endDate != null) c.EndDate = endDate;

        if (!String.isBlank(linkUrl) || !String.isBlank(description)) {
            String finalDesc = '';
            if (!String.isBlank(description)) finalDesc += description;
            if (!String.isBlank(linkUrl)) {
                if (!String.isBlank(finalDesc)) finalDesc += '\n\n';
                finalDesc += 'HL Link: ' + linkUrl;
            }
            c.Description = finalDesc;
        }

        Id campaignId;
        if (!String.isBlank(eventKey) && hasCampaignField('HL_Event_ID__c')) {
            c.put('HL_Event_ID__c', eventKey);
            upsert c HL_Event_ID__c;
            campaignId = c.Id;
        } else {
            insert c;
            campaignId = c.Id;
        }

        seedCampaignMemberStatuses(campaignId);

        Id accountId = findAccountIdByCommunityId(communityId);
        if (campaignId != null && accountId != null) {
            createEventPartner(campaignId, accountId);
        }
    }

    // ------------------------------------------------
    // 5) EVENT REGISTER / ATTEND -> CAMPAIGN MEMBER
    // Speculative routing: exact HL ActivityCode strings not yet observed
    // in live payloads. Uses contains('register') / contains('attend') so
    // variants like EventRegister, RegistrationCreate, EventAttend,
    // EventAttendanceCreate all route here.
    // ------------------------------------------------
    private static void setCampaignMemberStatus(Map<String, Object> payload, String status) {
        String eventKey = pick(payload, new List<String>{
            'EventKey', 'CalendarEventKey', 'ParentKey', 'Key'
        });
        if (String.isBlank(eventKey) || !hasCampaignField('HL_Event_ID__c')) {
            System.debug(LoggingLevel.WARN,
                '[HL] Cannot set CampaignMember status: missing eventKey or HL_Event_ID__c field');
            return;
        }
        List<Campaign> camps = Database.query(
            'SELECT Id FROM Campaign WHERE HL_Event_ID__c = :eventKey LIMIT 1'
        );
        if (camps.isEmpty()) {
            System.debug(LoggingLevel.WARN,
                '[HL] No Campaign found for eventKey=' + eventKey + '; cannot add member');
            return;
        }
        Id campaignId = camps[0].Id;

        String externalId = pick(payload, new List<String>{
            'ContributorKey', 'ContributorMemberKey', 'ContactKey', 'AgentContactKey', 'Key'
        });
        String email = pick(payload, new List<String>{
            'pb_emailaddress','Email','email','EmailAddress'
        });
        Contact match = findContactForUser(externalId, email);
        Id contactId = (match != null) ? match.Id : createOrUpsertContactForUser(payload);
        if (contactId == null) {
            System.debug(LoggingLevel.WARN, '[HL] Could not resolve Contact for event member');
            return;
        }

        seedCampaignMemberStatuses(campaignId);

        List<CampaignMember> existing = [
            SELECT Id, Status FROM CampaignMember
            WHERE CampaignId = :campaignId AND ContactId = :contactId
            LIMIT 1
        ];
        if (!existing.isEmpty()) {
            CampaignMember cm = existing[0];
            if (cm.Status == STATUS_ATTENDED && status == STATUS_REGISTERED) {
                System.debug(LoggingLevel.INFO,
                    '[HL] Skipping status downgrade from Attended to Registered');
                return;
            }
            if (cm.Status != status) {
                cm.Status = status;
                update cm;
            }
            return;
        }

        insert new CampaignMember(
            CampaignId = campaignId,
            ContactId = contactId,
            Status = status
        );
    }

    @TestVisible
    private static void seedCampaignMemberStatuses(Id campaignId) {
        if (campaignId == null) return;
        Set<String> existingLabels = new Set<String>();
        // SortOrder is unique per Campaign, and orgs differ in which slots
        // the auto-created statuses occupy, so take max + 1 instead of
        // assuming fixed positions.
        Integer maxSort = 0;
        for (CampaignMemberStatus cms : [
            SELECT Label, SortOrder FROM CampaignMemberStatus WHERE CampaignId = :campaignId
        ]) {
            existingLabels.add(cms.Label);
            if (cms.SortOrder != null && cms.SortOrder > maxSort) maxSort = cms.SortOrder;
        }
        Integer nextSort = maxSort + 1;
        List<CampaignMemberStatus> toInsert = new List<CampaignMemberStatus>();
        if (!existingLabels.contains('Registered')) {
            toInsert.add(new CampaignMemberStatus(
                CampaignId = campaignId,
                Label = 'Registered',
                SortOrder = nextSort,
                HasResponded = false
            ));
            nextSort++;
        }
        if (!existingLabels.contains('Attended')) {
            toInsert.add(new CampaignMemberStatus(
                CampaignId = campaignId,
                Label = 'Attended',
                SortOrder = nextSort,
                HasResponded = true
            ));
        }
        if (!toInsert.isEmpty()) insert toInsert;
    }

    private static void createEventPartner(Id campaignId, Id accountId) {
        List<conference360__Sponsor__c> existing = [
            SELECT Id
            FROM conference360__Sponsor__c
            WHERE conference360__Account__c = :accountId
              AND Event_Campaign__c = :campaignId
            LIMIT 1
        ];
        if (!existing.isEmpty()) return;
        conference360__Sponsor__c partner = new conference360__Sponsor__c();
        partner.conference360__Account__c = accountId;
        partner.Event_Campaign__c = campaignId;
        insert partner;
    }

    // ------------------------------------------------
    // Contact lookup shared by Routes 2 and 3
    // Priority: HL_Contact_ID__c > npe01__HomeEmail__c > Email
    // ------------------------------------------------
    @TestVisible
    private static Contact findContactForUser(String externalId, String email) {
        if (!String.isBlank(externalId) && hasContactField('HL_Contact_ID__c')) {
            List<Contact> hits = Database.query(
                'SELECT Id FROM Contact WHERE HL_Contact_ID__c = :externalId LIMIT 1'
            );
            if (!hits.isEmpty()) return hits[0];
        }
        if (!String.isBlank(email) && hasContactField('npe01__HomeEmail__c')) {
            List<Contact> hits = Database.query(
                'SELECT Id FROM Contact WHERE npe01__HomeEmail__c = :email LIMIT 1'
            );
            if (!hits.isEmpty()) return hits[0];
        }
        if (!String.isBlank(email)) {
            List<Contact> hits = [
                SELECT Id FROM Contact WHERE Email = :email LIMIT 1
            ];
            if (!hits.isEmpty()) return hits[0];
        }
        return null;
    }

    private static Id findAccountIdByCommunityId(String communityId) {
        if (String.isBlank(communityId) || !hasAccountField('HL_Community_ID__c')) return null;
        List<Account> hits = Database.query(
            'SELECT Id FROM Account WHERE HL_Community_ID__c = :communityId LIMIT 1'
        );
        return hits.isEmpty() ? null : hits[0].Id;
    }

    // ------------------------------------------------
    // RecordType lookup cache
    // ------------------------------------------------
    private static Id cachedAccountRecordTypeId;
    private static Boolean accountRecordTypeChecked = false;
    private static Id cachedCampaignEventRecordTypeId;
    private static Boolean campaignEventRecordTypeChecked = false;

    @TestVisible
    private static Id getAccountRecordTypeId() {
        if (accountRecordTypeChecked) return cachedAccountRecordTypeId;
        accountRecordTypeChecked = true;
        cachedAccountRecordTypeId = lookupRecordTypeId(
            Account.SObjectType, HigherLogicConfig.get().accountRecordTypeDeveloperName, 'Account');
        return cachedAccountRecordTypeId;
    }

    @TestVisible
    private static Id getCampaignEventRecordTypeId() {
        if (campaignEventRecordTypeChecked) return cachedCampaignEventRecordTypeId;
        campaignEventRecordTypeChecked = true;
        cachedCampaignEventRecordTypeId = lookupRecordTypeId(
            Campaign.SObjectType, HigherLogicConfig.get().campaignEventRecordTypeDeveloperName, 'Campaign');
        return cachedCampaignEventRecordTypeId;
    }

    private static Id lookupRecordTypeId(Schema.SObjectType sot, String devName, String label) {
        if (String.isBlank(devName)) return null;
        Schema.RecordTypeInfo rt = sot.getDescribe().getRecordTypeInfosByDeveloperName().get(devName);
        if (rt == null) {
            System.debug(LoggingLevel.WARN,
                '[HL] ' + label + ' RecordType not found for DeveloperName=' + devName);
            return null;
        }
        return rt.getRecordTypeId();
    }

    @TestVisible
    private static void resetRecordTypeCache() {
        cachedAccountRecordTypeId = null;
        accountRecordTypeChecked = false;
        cachedCampaignEventRecordTypeId = null;
        campaignEventRecordTypeChecked = false;
    }

    // ----------------------------
    // Helpers
    // ----------------------------
    public static String pick(Map<String, Object> payload, List<String> keys) {
        for (String k : keys) {
            if (payload.containsKey(k)) {
                String v = asString(payload.get(k));
                if (!String.isBlank(v)) return v;
            }
        }
        return null;
    }

    public static String asString(Object v) {
        if (v == null) return null;
        if (v instanceof String) return (String) v;
        return String.valueOf(v);
    }

    @TestVisible
    private static Date parseIsoToDate(String iso) {
        if (String.isBlank(iso)) return null;
        try {
            String s = iso;
            Integer dotIdx = s.indexOf('.');
            if (dotIdx > 0) s = s.substring(0, dotIdx);
            Integer plusIdx = s.lastIndexOf('+');
            if (plusIdx > 10) s = s.substring(0, plusIdx);
            s = s.replace('T', ' ');
            if (s.endsWith('Z')) s = s.substring(0, s.length() - 1);
            DateTime dt = DateTime.valueOfGmt(s);
            return dt.date();
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, '[HL] parseIsoToDate failed. iso=' + iso + ' err=' + e.getMessage());
            return null;
        }
    }

    private static Boolean hasContactField(String apiName) {
        return Schema.SObjectType.Contact.fields.getMap().containsKey(apiName);
    }
    private static Boolean hasAccountField(String apiName) {
        return Schema.SObjectType.Account.fields.getMap().containsKey(apiName);
    }
    private static Boolean hasCampaignField(String apiName) {
        return Schema.SObjectType.Campaign.fields.getMap().containsKey(apiName);
    }
}
