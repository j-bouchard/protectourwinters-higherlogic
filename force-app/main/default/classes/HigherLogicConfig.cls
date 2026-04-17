public without sharing class HigherLogicConfig {

    public class Settings {
        public String sharedSecret;
        public String accountRecordTypeDeveloperName;
    }

    @TestVisible private static Settings override;

    public static Settings get() {
        if (override != null) return override;

        Settings s = new Settings();
        List<HL_Webhook_Config__mdt> rows = [
            SELECT Shared_Secret__c, Account_RecordType_DeveloperName__c
            FROM HL_Webhook_Config__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];
        if (!rows.isEmpty()) {
            s.sharedSecret = rows[0].Shared_Secret__c;
            s.accountRecordTypeDeveloperName = rows[0].Account_RecordType_DeveloperName__c;
        }
        return s;
    }
}
