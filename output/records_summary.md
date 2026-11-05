# Output records — summary

Full records with all fields: `records.json` (one object per message). REQ-0001..0005 are the assessment samples; REQ-0006/0007 are extra edge cases added to exercise the low-confidence fallback and the billing-escalation rule.

| ID | Source | Category | Priority | Conf. | Routed to | Escalated | Reasons | Core issue |
|---|---|---|---|---|---|---|---|---|
| REQ-0001 | email | Bug Report | High | 0.85 | **engineering** | no | — | Customer cannot log in and receives a 403 error since a platform update last Tuesday. |
| REQ-0002 | web_form | Feature Request | Low | 0.93 | **product** | no | — | Customer requests a bulk export feature for audit logs to reduce monthly compliance work. |
| REQ-0003 | support_portal | Billing Issue | Medium | 0.95 | **billing** | no | — | Customer disputes invoice #8821 charge of $1,240, stating the contract rate is $980/month, and asks for review. |
| REQ-0004 | email | Technical Question | Low | 0.85 | **it-security** | no | — | Customer asks whether SSO can be set up with Okta while evaluating a switch of their auth provider. |
| REQ-0005 | web_form | Incident/Outage | High | 0.9 | **escalation** | YES | category:incident_outage, keyword:multiple users, scope:multiple_users | Customer reports the ArcVault dashboard stopped loading around 2pm EST for multiple users, which they attribute to ArcVault's side. |
| REQ-0006 | email | Technical Question | Medium | 0.2 | **escalation** | YES | low_confidence:0.20<0.7 | Customer reports that something is not working and requests urgent help, without specifying the product or problem. |
| REQ-0007 | support_portal | Billing Issue (+Bug Report) | High | 0.8 | **escalation** | YES | billing_dispute_usd:2100>500 | Customer reports being charged twice this month, with $2,100 extra, and the CSV export button not working since yesterday. |
