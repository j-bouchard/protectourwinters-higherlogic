public without sharing class HigherLogicConfig {

    public class Settings {
        public String sharedSecret;
        public String accountRecordTypeDeveloperName;
        public String campaignEventRecordTypeDeveloperName;
    }

    @TestVisible private static Settings testOverride;
    @TestVisible private static List<HL_Webhook_Config__mdt> mockRows;

    public static Settings get() {
        if (testOverride != null) return testOverride;

        List<HL_Webhook_Config__mdt> rows = (mockRows != null) ? mockRows : queryRows();

        Settings s = new Settings();
        if (!rows.isEmpty()) {
            s.sharedSecret = rows[0].Shared_Secret__c;
            s.accountRecordTypeDeveloperName = rows[0].Account_RecordType_DeveloperName__c;
            s.campaignEventRecordTypeDeveloperName = rows[0].Campaign_Event_RecordType_DeveloperName__c;
        }
        return s;
    }

    private static List<HL_Webhook_Config__mdt> queryRows() {
        return [
            SELECT Shared_Secret__c,
                   Account_RecordType_DeveloperName__c,
                   Campaign_Event_RecordType_DeveloperName__c
            FROM HL_Webhook_Config__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];
    }
}
