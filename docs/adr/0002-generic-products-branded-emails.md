# 0002: Generic products, an approval webhook, branded emails

Date: 2026-10-25. Status: accepted.

## Context

Carmine wants the waitlist open-sourceable, every email branded per
product, a one-click Approve that gives a Acme licence key, and the
GetWaitlist signups who never confirmed asked once more.

## Decision

- Nothing product-specific in code. Products come from `PRODUCTS_FILE`
  (`config/products.yml` is an example); this deployment's are in
  `deploy/products.yml` with their brand folders. Deployment scripts are in
  `deploy/` too.
- Approval is a generic webhook (`on_approve`: url, token file, `id_field`,
  `sent_url`, admin labels). The app stores only the returned id. The
  answer's other fields fill the approval email (`approval_email`, a
  `Subject:` line and a small Markdown template with `{{variables}}`) and
  live only in the job's memory and the email: a licence key is never
  stored or queued. After the email is sent, `sent_url` is told. Each step
  is recorded (`approval_registered_at`, `approval_emailed_at`,
  `approval_acknowledged_at`, `approval_failed_at`) so "Try again"
  resumes where it stopped; registering again must be idempotent on the
  reference (`waitlist-REFERRALCODE`).
- Every email (confirmation, reminder, approval, leave confirmation, owner
  notification) uses one layout branded by the product: sender name, logo
  PNG (served from its brand folder, since email clients don't show SVG),
  colours, a font stack with optional web fonts (Apple Mail and iOS load
  them; Gmail falls back), and a footer with the leave link, privacy link
  and the controller's Impressum line. Each has a plain-text part. The
  layout is tables with inline styles, light only.
- Imported unconfirmed people get `confirm_by` (14 days, `reminder_days`)
  and one reminder; RetentionJob deletes them after it. They are linked to a
  referrer only if GetWaitlist gave that referrer no credit for them, so a
  confirmation never counts twice.
- Leaving sends one email confirming the deletion. Its job carries the
  address until it runs; finished jobs are cleared hourly.

## Consequences

Acme's approval email turns on when licence-server's route signs and returns
the key: add `approval_email` and `sent_url` to `deploy/products.yml`.
