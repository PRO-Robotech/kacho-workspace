---
title: User IAM guide
aliases:
  - User onboarding
  - User IAM
category: docs
audience: user
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - docs
  - kacho-iam
  - user
---

# User IAM guide (kacho.cloud)

> [!info] Audience
> End-users of kacho.cloud (your Workspace will be hosted at `https://docs.kacho.cloud/iam/`). This page = vault catalog.

## Signing up (passwordless / Passkey)

1. Browse `https://api.kacho.cloud/` → click **Sign up**.
2. Enter email → receive magic link (verification).
3. Click link → prompted to register Passkey (WebAuthn) — biometric / hardware key.
4. Done — never enter a password again.

> [!tip] Why Passkey?
> Kachō is passwordless by default. Passkeys (FIDO2 WebAuthn) protect you from phishing, credential stuffing, and password reuse. See [FIDO Alliance](https://fidoalliance.org/passkeys/).

## Creating a Project

1. After login → click **Create Project**.
2. Provide name + description.
3. Your project lives within an **Account** (billing entity). Personal account auto-created on signup.

## Inviting collaborators

1. Project page → **Members** tab → **Invite**.
2. Enter colleague's email → choose role:
   - `viewer` — read-only.
   - `editor` — create / modify resources.
   - `admin` — manage members + IAM.
3. They receive email with one-time link → set up Passkey → join.

## Role assignments

Custom Roles available — define your own permission sets (Phase 3):

1. Project Settings → **Roles** → **Create custom role**.
2. Name (e.g., `database-operator`) + select permissions из catalog.
3. Assign role to users / Groups via **Members** tab.

## Multi-factor + step-up

Kachō prompts for fresh MFA for sensitive operations:
- Deleting resources.
- Changing IAM bindings.
- Rotating secrets.

If your Passkey was used >5min ago, you'll see a step-up prompt — just re-authenticate.

## Privacy / GDPR

- **Right to erasure** (Article 17): Account Settings → **Privacy** → **Request erasure**.
  - 30-day cool-off period.
  - During cool-off you can cancel — account stays disabled.
  - After 30d → hard-delete + audit-log redaction.
- **Data export** (Article 20): Account Settings → **Privacy** → **Export data** — receive ZIP within 14 days.

## API access (developers)

See [[dev-iam-integration|developer integration guide]].

## See also

- [[admin-iam-guide]] — organization / IAM admin docs.
- [[dev-iam-integration]] — workload identity, API tokens, DPoP.
- [[../KAC/KAC-127]] — implementation milestone.

#docs #kacho-iam #user
