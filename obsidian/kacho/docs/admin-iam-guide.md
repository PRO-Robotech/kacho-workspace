---
title: Admin IAM guide
aliases:
  - Admin guide
  - SSO admin
category: docs
audience: admin
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - docs
  - kacho-iam
  - admin
---

# Admin IAM guide (Organization tier)

> [!info] Audience
> Enterprise Organization administrators (SCIM provisioning, SAML SSO, audit reports). Public URL `https://docs.kacho.cloud/admin/iam/`. This page = vault catalog.

## Organization setup

1. Sign up as user → personal Account auto-created.
2. Account → **Upgrade to Organization** → choose Enterprise tier.
3. Verify domain ownership (DNS TXT record) → Organization status `verified`.
4. All future users with `@yourdomain.com` email JIT-provision as Organization members ([[../resources/iam-organization]]).

## SSO — SAML 2.0

Recommended for legacy IdP. Use SCIM (below) for modern provisioning.

1. Organization Settings → **SSO** → **SAML 2.0**.
2. Upload IdP metadata XML or paste metadata URL.
3. Configure attribute mapping (email, name, groups).
4. Copy SP metadata → configure in your IdP.
5. Test SSO with admin account → enable Organization-wide.

Tech details: [[../rpc/iam-saml-sp]], [[../edges/iam-to-jackson-saml]].

## SSO — SCIM 2.0 (recommended)

For Okta / Azure AD (Entra ID) / Google Workspace / OneLogin / JumpCloud.

1. Organization Settings → **SCIM** → **Generate token**.
2. Copy:
   - Endpoint: `https://api.kacho.cloud/scim/v2/{org_id}/`
   - Bearer token (shown ONCE).
3. In your IdP:
   - Okta → [[../edges/iam-to-scim-okta]] для setup.
   - Azure AD (Microsoft Entra) → [[../edges/iam-to-scim-azure]].
   - Google Workspace → [[../edges/iam-to-scim-google]].
4. Users auto-provision (JIT) + groups sync to kacho.

## Custom Roles

Define organization-wide custom roles:
1. Organization Settings → **Roles** → **Create**.
2. Choose scope: `organization` / `account` / `project`.
3. Pick permissions из catalog.
4. Inherit from system roles (e.g., extend `viewer` с extra delete-permission).
5. Apply via AccessBinding to user / Group.

## PIM / JIT activation

Standing admin = anti-pattern. Set up Eligibility:

1. Organization Settings → **PIM / JIT** → **New eligibility**.
2. Select user + role + max-duration (default 8h cap).
3. Optional: require approval (configurable 1-of-N or 2-of-N).
4. User can request activation from CLI / UI:
   ```
   kacho-cli iam jit activate --eligibility=jite_xxx --duration=4h --justification="Production database migration"
   ```
5. Approval flow (if required) → notify approvers.

## Break-glass

Emergency cluster-admin (production downtime):

1. Initiator opens request с justification ≥50 chars ("EMERGENCY: ...").
2. **Different** admin approves → ACTIVE with 2h TTL.
3. PagerDuty / Slack alerts fire immediately ([[../runbooks/README|runbooks/break-glass-procedure]]).
4. Auto-revoked after 2h or manual revoke any time.

See [[../runbooks/README|runbooks/break-glass-procedure]] для full procedure.

## Access Reviews

Quarterly recertification:
1. Organization Settings → **Access Reviews** → **Schedule**.
2. Choose scope (account / project / role) + cadence (quarterly default) + reviewer.
3. Reviewer receives 14d window to approve / revoke each binding.
4. Auto-revoke unresponded items if configured.
5. Download PDF report для SOC 2 / ISO 27001 evidence.

## Audit reports

- Real-time query: Organization Settings → **Audit** → search events.
- Historical (90d hot, 7y cold): contact support для S3 archive export.
- Integrity verification: each event signed (Merkle batch); UI shows ✓ / ⚠ tamper indicator.

## CAEP — propagating revocation to downstream apps

Subscribe external apps to kacho IAM events:
1. Organization Settings → **CAEP** → **Register subscriber**.
2. Endpoint URL + auth (mTLS / OAuth client credentials / bearer).
3. Select event types (session.revoked, iam.token.revoked, ...).
4. Test delivery → enable.

Spec: OpenID CAEP draft; payload format RFC 8417 SET (signed JWT). See [[../rpc/iam-caep-subscriber-service]].

## See also

- [[user-iam-guide]] — end-user docs.
- [[dev-iam-integration]] — developer / workload integration.
- [[../KAC/KAC-127]] — implementation milestone.

#docs #kacho-iam #admin
