# Integration Accounts Checklist

## Purpose
Track external accounts and OAuth apps needed to pass the challenge without ambiguity.

## Hard-Required Integrations For This Challenge
1. Google Cloud OAuth App
2. Recall.ai account and API key
3. Google Gemini API key
4. HubSpot OAuth App
5. Salesforce Connected App

## Optional Integrations (Not Required To Pass This Challenge)
1. LinkedIn OAuth App
2. Facebook App (plus page permissions)

## Why HubSpot Is Still In Hard-Required
1. The challenge states HubSpot suggestions already work in existing functionality.
2. Submission should not regress existing required behavior.
3. Minimum expectation is a smoke test confirming HubSpot flow still works.

## Required Outputs Per Integration
1. Client ID
2. Client Secret
3. Redirect URI(s)
4. Required scopes
5. Test account access (if applicable)

## Environment Variables (Planned/Current)
1. Google: `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_REDIRECT_URI`
2. Recall: `RECALL_API_KEY`, `RECALL_REGION`
3. Gemini: `GEMINI_API_KEY`
4. HubSpot: `HUBSPOT_CLIENT_ID`, `HUBSPOT_CLIENT_SECRET`, `HUBSPOT_REDIRECT_URI`
5. Salesforce: `SALESFORCE_CLIENT_ID`, `SALESFORCE_CLIENT_SECRET`, `SALESFORCE_REDIRECT_URI`
   - Optional: `SALESFORCE_SITE` (default `https://login.salesforce.com`)
6. LinkedIn: `LINKEDIN_CLIENT_ID`, `LINKEDIN_CLIENT_SECRET`, `LINKEDIN_REDIRECT_URI`
7. Facebook: `FACEBOOK_CLIENT_ID`, `FACEBOOK_CLIENT_SECRET`, `FACEBOOK_REDIRECT_URI`

## Validation Checklist (Hard-Required Path)
1. OAuth callback works in localhost.
2. OAuth callback works in deployed environment.
3. Tokens are stored and refreshed correctly.
4. Required API scopes are sufficient for challenge flows (calendar sync, recording, transcript AI, HubSpot suggestions, Salesforce search/read/update).

## Final Submission Smoke Checklist (Hard Requirements)
1. Google login works.
2. Upcoming events are visible.
3. Meeting toggle schedules Recall bot.
4. Completed meeting appears in past meetings.
5. Transcript view loads.
6. AI follow-up email loads.
7. HubSpot suggestion flow still works.
8. Salesforce connect works.
9. Salesforce contact search/select works.
10. Salesforce suggestions generate from transcript.
11. Salesforce updates apply and are visible in Salesforce.

## HubSpot OAuth Quick Troubleshooting
1. Symptom: HubSpot shows `Unable to load app information`.
2. Most common cause: invalid or missing `HUBSPOT_CLIENT_ID` in deployed env.
3. Verify HubSpot app exists and is enabled in your HubSpot Developer account.
4. Verify app redirect URLs include:
   - `http://localhost:4100/auth/hubspot/callback`
   - `https://scribe.adlerclub.tech/auth/hubspot/callback` (or your production domain)
5. Verify Railway env vars are set and non-empty:
   - `HUBSPOT_CLIENT_ID`
   - `HUBSPOT_CLIENT_SECRET`
6. Redeploy after env changes.

## Optional OAuth Troubleshooting (LinkedIn/Facebook)
1. LinkedIn symptom: `You need to pass the "client_id" parameter`.
2. LinkedIn likely cause: missing or empty `LINKEDIN_CLIENT_ID` in runtime env.
3. Facebook symptom: `Invalid App ID`.
4. Facebook likely cause: missing/invalid `FACEBOOK_CLIENT_ID` or wrong app configured.
5. For both providers, verify redirect URLs in provider app settings:
   - local: `http://localhost:4100/auth/<provider>/callback`
   - prod: `https://scribe.adlerclub.tech/auth/<provider>/callback`
6. Verify Railway env vars are set:
   - LinkedIn: `LINKEDIN_CLIENT_ID`, `LINKEDIN_CLIENT_SECRET`
   - Facebook: `FACEBOOK_CLIENT_ID`, `FACEBOOK_CLIENT_SECRET`
