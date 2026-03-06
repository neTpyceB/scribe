# Integration Accounts Checklist

## Purpose
Track all external accounts and OAuth apps required for full end-to-end functionality.

## Required Services
1. Google Cloud OAuth App
2. Recall.ai account and API key
3. Google Gemini API key
4. HubSpot OAuth App
5. Salesforce Connected App
6. LinkedIn OAuth App
7. Facebook App (plus page permissions)

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
6. LinkedIn: `LINKEDIN_CLIENT_ID`, `LINKEDIN_CLIENT_SECRET`, `LINKEDIN_REDIRECT_URI`
7. Facebook: `FACEBOOK_CLIENT_ID`, `FACEBOOK_CLIENT_SECRET`, `FACEBOOK_REDIRECT_URI`

## Validation Checklist
1. OAuth callback works in localhost.
2. OAuth callback works in deployed environment.
3. Tokens are stored and refreshed correctly.
4. Required API scopes are sufficient for search/read/update flows.
