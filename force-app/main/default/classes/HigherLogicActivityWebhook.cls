@RestResource(urlMapping='/higherlogic/activity')
global without sharing class HigherLogicActivityWebhook {

    @TestVisible private static final String TOKEN_HEADER = 'X-HL-Token';

    @HttpPost
    global static void handlePost() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        HigherLogicConfig.Settings cfg = HigherLogicConfig.get();
        if (String.isBlank(cfg.sharedSecret)) {
            System.debug(LoggingLevel.ERROR, '[HL] Shared secret not configured');
            res.statusCode = 503;
            res.responseBody = Blob.valueOf('Webhook not configured');
            return;
        }

        String token = req.headers != null ? req.headers.get(TOKEN_HEADER) : null;
        if (String.isBlank(token) || token != cfg.sharedSecret) {
            System.debug(LoggingLevel.WARN, '[HL] Unauthorized webhook call. tokenPresent=' + (token != null));
            res.statusCode = 401;
            res.responseBody = Blob.valueOf('Unauthorized');
            return;
        }

        String raw = (req.requestBody == null) ? null : req.requestBody.toString();
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
