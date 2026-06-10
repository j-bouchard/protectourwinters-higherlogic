# protectourwinters-higherlogic

Higher Logic - Salesforce Integration

## Setup

1. Deploy with SFDX: `sf project deploy start -d force-app`.
2. Populate the `HL_Webhook_Config.Default` custom metadata record:
   - `Account_RecordType_DeveloperName__c` - defaults to `Higher_Logic_Community`; change if the RecordType uses a different DeveloperName.
   - `Campaign_Event_RecordType_DeveloperName__c` - defaults to `Event`; Campaign RecordType to assign to events created from Higher Logic.
   - `Shared_Secret__c` is present but unused; reserved for future header-based auth if/when HL exposes header config.
3. In Higher Logic, configure the outbound webhook to POST to the Site endpoint (something like `https://<site>.my.salesforce-sites.com/<site-prefix>/services/apexrest/higherlogic/activity`).

## Webhook Responses

The endpoint is unauthenticated by design; it's on a Salesforce Site served by a Guest User, matching the contractor's original setup. Status codes:
- `400 Missing body` / `400 Invalid JSON` - body validation.
- `200 Ignored` - route resolved to IGNORE.
- `200 OK: queued <Route>` - job enqueued successfully.

## Route Decision Logic
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

Route 5: Register for Event / Attend Event
Triggered when:
ActivityCode contains `attend` (routes to Attend Event), OR
ActivityCode contains `register` or `rsvp` (routes to Register for Event)

Note: The exact HL ActivityCode strings for these two activities were not yet observable when this code was written (HL site not fully live). Matching uses `contains(...)` so variants like `EventRegister`, `RegistrationCreate`, `EventAttend`, `EventAttendanceCreate`, etc. all route correctly. Once live payloads are captured, the matching can be tightened.


Route 1: Create Community Account
This route creates or upserts a Salesforce Account to represent a Higher Logic community.

Reading the Community ID from the Payload
The code tries to find the Community ID by checking payload fields in this order: CommunityKey, CommunityId, CommunityID, CommunityGuid, CommunityGUID, Key. It uses the first one that has a non-blank value.

Reading the Community Name from the Payload
The code tries to find the Community Name by checking payload fields in this order: CommunityName, CommunityTitle, Community, Name, Title. If none of these have a value, the name defaults to Higher Logic Community.

Creating or Updating the Account
If the Account object in Salesforce has the custom field HL_Community_ID__c set up as an External ID, and the incoming Community ID is not blank, the code performs an upsert using HL_Community_ID__c as the key. This means if an Account with that community ID already exists, it will be updated rather than duplicated.

If the HL_Community_ID__c field does not exist on Account, or the community ID is blank, the code performs a plain insert. 

Note on RecordType: The Account RecordType is resolved at runtime by DeveloperName from `HL_Webhook_Config.Default.Account_RecordType_DeveloperName__c` (defaults to `Higher_Logic_Community`). If the RecordType is not found in the org, the field is left unset and Salesforce will apply the user's default.

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
The code searches for an existing Contact in the following priority order:
1. If HL_Contact_ID__c exists in the org and the payload has a `ContributorKey` (or equivalent), query by `HL_Contact_ID__c`. This is the most reliable match and survives email changes.
2. Otherwise, if npe01__HomeEmail__c exists and the payload has an email, query by `npe01__HomeEmail__c`.
3. As a final fallback, query by standard `Email`. This fallback runs even when npe01__HomeEmail__c exists but did not yield a match.

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

Step 2: Find or Create the Contact
The code searches for a Contact using the same three-step priority as Route 2:
1. By `HL_Contact_ID__c` (if field present and payload has User ID).
2. By `npe01__HomeEmail__c` (if field present and payload has email).
3. By standard `Email` as the final fallback.

If no Contact is found after all three attempts, the route creates a new Contact from the join payload (same logic as Route 2, including defaulting LastName to `HL User` when blank).

Step 3: Check for Existing Affiliation
Before inserting, the code checks whether an npe5__Affiliation__c record already exists for this Contact and Account combination. If one already exists, the route skips the insert to avoid duplicates.

Step 4: Create the Affiliation
If no existing affiliation is found, a new npe5__Affiliation__c record is inserted linking the Contact to the Account.

Route 5: Register for Event / Attend Event
This route adds a Contact as a CampaignMember on the Event Campaign, with Status reflecting the HL action.

Reading Fields from the Payload
Event ID - checks: EventKey, CalendarEventKey, ParentKey, Key
HL External ID - checks: ContributorKey, ContributorMemberKey, ContactKey, AgentContactKey, Key
Email - checks: pb_emailaddress, Email, email, EmailAddress

Step 1: Find the Campaign
The code queries for a Campaign where HL_Event_ID__c matches the Event ID. If no matching Campaign is found, processing stops and nothing is written. No placeholder Campaign is created.

Step 2: Find or Create the Contact
Uses the same three-step priority as Routes 2 and 3: HL_Contact_ID__c -> npe01__HomeEmail__c -> standard Email. If still not found, creates a new Contact from the payload.

Step 3: Ensure CampaignMemberStatus values exist
Calls the same idempotent seed helper used by Route 4 to guarantee `Registered` and `Attended` are valid statuses on the Campaign, even if the Campaign was created outside this integration.

Step 4: Upsert the CampaignMember
Looks up an existing CampaignMember by (CampaignId, ContactId). If found, updates Status; if not, inserts. Never creates duplicates for the same Contact on the same Campaign.

Status mapping
- Register for Event -> `Registered`
- Attend Event -> `Attended`

Downgrade guard: if an existing CampaignMember already has Status `Attended` and a late Register webhook arrives, the status is NOT downgraded to `Registered`. All other transitions (Registered -> Attended, insert with any status) are applied.

Cancellations are not handled - HL does not appear to emit a webhook for cancelled/no-show status changes, so those must be managed manually in Salesforce.

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

RecordType: The Campaign RecordType is resolved at runtime by DeveloperName from `HL_Webhook_Config.Default.Campaign_Event_RecordType_DeveloperName__c` (defaults to `Event`). If the RecordType is not found in the org, RecordTypeId is left unset.

Campaign Member Statuses
When a Campaign is created or upserted by this route, the code seeds two CampaignMemberStatus records on the Campaign if they aren't already present:
- `Registered` (HasResponded = false)
- `Attended` (HasResponded = true)

The auto-created `Sent` and `Responded` statuses are left in place. Seeding is idempotent, so re-firing the webhook will not create duplicates.

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
