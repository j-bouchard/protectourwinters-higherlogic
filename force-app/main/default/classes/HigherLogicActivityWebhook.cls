@RestResource(urlMapping='/higherlogic/activity')
global without sharing class HigherLogicActivityWebhook {

    @HttpPost
    global static void handlePost() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        String raw = (req.requestBody == null) ? null : req.requestBody.toString();
        System.debug(LoggingLevel.INFO, '[HL] Incoming request. rawBody=' + raw);

        if (String.isBlank(raw)) {
            System.debug(LoggingLevel.WARN, '[HL] Missing body');
            res.statusCode = 400;
            res.responseBody = Blob.valueOf('Missing body');
            return;
        }

        Map<String, Object> payload;
        try {
            payload = (Map<String, Object>) JSON.deserializeUntyped(raw);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, '[HL] Invalid JSON. err=' + e.getMessage());
            res.statusCode = 400;
            res.responseBody = Blob.valueOf('Invalid JSON');
            return;
        }

        String activityCode = HigherLogicActivityProcessor.asString(payload.get('ActivityCode'));
        String objectType   = HigherLogicActivityProcessor.asString(payload.get('ObjectType'));

        System.debug(LoggingLevel.INFO, '[HL] ActivityCode=' + activityCode + ', ObjectType=' + objectType);

        HigherLogicActivityProcessor.Route route =
            HigherLogicActivityProcessor.decideRoute(activityCode, objectType);

        if (route == HigherLogicActivityProcessor.Route.IGNORE) {
            res.statusCode = 200;
            res.responseBody = Blob.valueOf('Ignored');
            return;
        }

        System.enqueueJob(new HigherLogicActivityProcessor.Job(route, payload));
        System.debug(LoggingLevel.INFO, '[HL] Enqueued job. route=' + String.valueOf(route));

        res.statusCode = 200;
        res.responseBody = Blob.valueOf('OK: queued ' + String.valueOf(route));
    }
}
