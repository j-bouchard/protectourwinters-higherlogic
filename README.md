# protectourwinters-higherlogic

Higher Logic - Salesforce Integration
Route Decision Logic
The webhook reads two fields from the JSON payload (ActivityCode and ObjectType) and uses them to decide which of the four processing routes to invoke. Matching is case-insensitive. 
Route 1: Create Community Account
Triggered when:
ActivityCode exactly equals communitycreate, OR
ActivityCode contains the word create AND ObjectType equals community

Route 2: Create User Contact
Triggered when:
ActivityCode exactly equals contactcreate, OR
ActivityCode contains the word create AND ObjectType equals contact

Route 3: Join Community: Link Contact
Triggered when:
ActivityCode exactly equals communitymemberjoin or communityjoin, OR
ActivityCode contains the word join AND ObjectType equals communitymember

Route 4: Create Event Campaign
Triggered when:
ActivityCode exactly equals eventcreate, OR
ActivityCode contains the word create AND ObjectType equals calendarevent or event


Route 1: Create Community Account
This route creates or upserts a Salesforce Account to represent a Higher Logic community.

Reading the Community ID from the Payload
The code tries to find the Community ID by checking payload fields in this order: CommunityKey, CommunityId, CommunityID, CommunityGuid, CommunityGUID, Key. It uses the first one that has a non-blank value.

Reading the Community Name from the Payload
The code tries to find the Community Name by checking payload fields in this order: CommunityName, CommunityTitle, Community, Name, Title. If none of these have a value, the name defaults to Higher Logic Community.

Creating or Updating the Account
If the Account object in Salesforce has the custom field HL_Community_ID__c set up as an External ID, and the incoming Community ID is not blank, the code performs an upsert using HL_Community_ID__c as the key. This means if an Account with that community ID already exists, it will be updated rather than duplicated.

If the HL_Community_ID__c field does not exist on Account, or the community ID is blank, the code performs a plain insert. 

Note on RecordType: The Account RecordTypeId is hard-coded as 012VA000002tlOXYAY. 

Route 2: Create User Contact
This route creates or updates a Salesforce Contact based on user data sent from Higher Logic.

Reading Fields from the Payload
The code tries multiple field name variants for each piece of data, using the first non-blank value found:

HL External ID - checks: ContributorKey, ContributorMemberKey, ContactKey, AgentContactKey, Key
Email - checks: pb_emailaddress, Email, email, EmailAddress
First Name - checks: pb_firstname, FirstName, firstName, ContributorFirstName
Last Name - checks: pb_lastname, LastName, lastName, ContributorLastName. Defaults to HL User if blank.
Phone - checks: pb_phone1, Phone, phone
Address - checks pb_address1 / pb_city / pb_state / pb_postalcode / pb_country first, then falls back to MailingStreet / MailingCity / MailingState / MailingPostalCode / MailingCountry

Finding an Existing Contact
The code searches for an existing Contact using email address. It first queries on the npe01__HomeEmail__c field (NPSP personal email). If that field does not exist in the org, it falls back to querying on the standard Email field.

If a matching Contact is found, it is updated. Only fields that have a non-blank value in the incoming payload are overwritten; blank payload values do not clear existing Salesforce data.

If no matching Contact is found, a new Contact is inserted.

Fields Written to the Contact
Standard fields written: FirstName, LastName, Phone, Email, MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry.

Custom fields written (only if they exist in the org): npe01__HomeEmail__c (NPSP home email), HL_Contact_ID__c (HL external ID). The code checks for field existence before writing, so it is safe in orgs without NPSP installed.

Route 3: Join Community: Link Contact to Account
This route links an existing Contact to an existing Account using an NPSP Affiliation record. It does not create new Contacts or Accounts.

Reading Fields from the Payload
Community ID - checks: CommunityKey, CommunityId, CommunityID, CommunityGuid, CommunityGUID, Key
User ID - checks: ContributorKey, ContributorMemberKey
Email - checks: pb_emailaddress, Email, email, EmailAddress

Step 1: Find the Account
The code queries for an Account where HL_Community_ID__c matches the Community ID from the payload. If no matching Account is found, processing stops here and nothing is written.

Step 2: Find the Contact
The code searches for a Contact in this order:
First, queries where HL_Contact_ID__c matches the User ID from the payload (if that field exists in the org)
If not found, queries where npe01__HomeEmail__c matches the email (if that field exists)
If still not found, queries where the standard Email field matches

If no Contact is found after all three attempts, processing stops. This route will not create a new Contact.

Step 3: Check for Existing Affiliation
Before inserting, the code checks whether an npe5__Affiliation__c record already exists for this Contact and Account combination. If one already exists, the route skips the insert to avoid duplicates.

Step 4: Create the Affiliation
If no existing affiliation is found, a new npe5__Affiliation__c record is inserted linking the Contact to the Account.

Route 4: Create Event Campaign
This route creates or upserts a Salesforce Campaign to represent a Higher Logic event, and optionally links it to a community Account via a conference360 Event Partner record.

Reading Fields from the Payload
Event ID - checks: EventKey, CalendarEventKey, Key
Title - checks: Title, EventTitle, Name. Defaults to Higher Logic Event if blank.
Start Date - checks: Date01, pb_eventstart, StartDate, StartDateTime. Defaults to today if blank.
End Date - checks: Date02, pb_eventend, EndDate, EndDateTime
URL - checks: LinkUrl, URL, Url
Description - checks: ActivityDescription, Description
Community ID - checks: CommunityKey, ParentKey

Fields Set on the Campaign
The following fields are always hard-coded regardless of the payload:
OKR_Type__c is set to fundraise
HL_Event_Type__c is set to Chapter Meeting
Host__c is set to Community Hosted

The following fields are set if they exist in the org:
Type is set to Event
Status is set to Planned

The Description field is built by combining ActivityDescription and LinkUrl: if both are present, the description becomes the ActivityDescription text followed by a new line and HL Link: and the URL.

Creating or Updating the Campaign
If Campaign has the HL_Event_ID__c custom External ID field and the Event ID from the payload is not blank, the code upserts by HL_Event_ID__c. This prevents duplicate Campaigns if the same event fires twice.

If the field does not exist or the Event ID is blank, a plain insert is performed.

Linking the Campaign to a Community Account
After the Campaign is created, the code attempts to find an Account using the Community ID from the payload (via the CommunityKey or ParentKey field). If a matching Account is found, the code checks whether a conference360__Sponsor__c (Event Partner) record already exists linking that Campaign and Account. If none exists, a new one is inserted.

Custom Fields Required
The following custom fields must exist in the Salesforce org for full functionality. The code checks for field existence at runtime, so missing fields will not cause errors; those features will simply be skipped.

Account.HL_Community_ID__c: must be set as an External ID. Used for Account upsert in Route 1 and Account lookup in Routes 3 and 4.
Contact.HL_Contact_ID__c: must be set as an External ID. Used for Contact lookup in Route 3.
Contact.npe01__HomeEmail__c: NPSP personal email field. Used as the primary Contact match key in Routes 2 and 3.
Campaign.HL_Event_ID__c: must be set as an External ID. Used for Campaign upsert in Route 4.
npe5__Affiliation__c: NPSP object. Must exist for Route 3 (community member join) to create Contact-Account links.
conference360__Sponsor__c: Event Partner object. Must exist for Route 4 to link Campaigns to community Accounts.
