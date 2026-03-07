# End-to-End QA Notes

## Purpose
Provide a single evaluator-friendly checklist that maps challenge requirements to product behavior and records execution evidence.

## Requirement Traceability (Hard Scope)
1. Google login works.
   - Entry point: `/auth/google`
   - Evidence: successful redirect back to app + authenticated dashboard session.
2. Upcoming calendar events are visible.
   - Entry point: dashboard home (`/dashboard`)
   - Evidence: at least one future event row rendered from synced calendar events.
3. Meeting recording toggle works.
   - Entry point: dashboard event list toggle.
   - Evidence: toggle persists and corresponding Recall bot record is created.
4. Recall bot scheduling/join pipeline works.
   - Entry point: bot poller + Recall integration.
   - Evidence: bot reaches terminal status and meeting record is created.
5. Past meetings list is populated.
   - Entry point: `/dashboard/meetings`
   - Evidence: processed meeting appears with date/title/platform marker.
6. Transcript view works.
   - Entry point: `/dashboard/meetings/:id`
   - Evidence: transcript section renders data (not empty-state only).
7. AI follow-up email appears.
   - Entry point: meeting details page.
   - Evidence: follow-up email text area is populated by AI worker output.
8. HubSpot suggestion flow works.
   - Entry point: HubSpot modal from meeting details.
   - Evidence: contact search/select + suggestions + successful update.
9. Salesforce OAuth connect works.
   - Entry point: Settings page connect action.
   - Evidence: connected Salesforce account row appears.
10. Salesforce contact search/select works.
    - Entry point: Salesforce modal contact selector.
    - Evidence: search returns records and selected contact summary appears.
11. Salesforce AI suggestions render current vs suggested values.
    - Entry point: Salesforce modal suggestions section.
    - Evidence: suggestion cards with old/new values are visible.
12. Salesforce updates sync successfully.
    - Entry point: `Update Salesforce` action.
    - Evidence: success feedback in app + verified field update in Salesforce UI.

## End-to-End QA Script (Deployed)
1. Log in via Google.
2. Verify upcoming events load on dashboard.
3. Enable recording on one valid future meeting event.
4. Wait for meeting processing completion.
5. Open the new past meeting.
6. Confirm transcript section and AI follow-up email are populated.
7. Run HubSpot flow: connect (if needed), search/select, suggest, update.
8. Run Salesforce flow: connect (if needed), search/select, suggest, update.
9. Verify CRM-side data changes in HubSpot/Salesforce UI.
10. Record pass/fail and artifact links in the evidence table below.

## Evidence Capture Template
| Requirement | Status | Evidence |
| --- | --- | --- |
| Google login | PASS/FAIL | video timestamp / screenshot / log snippet |
| Upcoming events | PASS/FAIL | screenshot |
| Recording toggle | PASS/FAIL | screenshot + DB/log confirmation |
| Recall pipeline | PASS/FAIL | meeting + bot status evidence |
| Past meetings | PASS/FAIL | screenshot |
| Transcript view | PASS/FAIL | screenshot |
| AI follow-up email | PASS/FAIL | screenshot |
| HubSpot suggestions/update | PASS/FAIL | screenshot + CRM proof |
| Salesforce connect/search/select | PASS/FAIL | screenshot |
| Salesforce suggestions | PASS/FAIL | screenshot |
| Salesforce update sync | PASS/FAIL | screenshot + Salesforce proof |

## Notes
1. Optional integrations (LinkedIn/Facebook posting) are showcase scope and should not block hard-scope acceptance.
2. If any step fails, capture exact timestamp, URL, and visible error text before retrying.
