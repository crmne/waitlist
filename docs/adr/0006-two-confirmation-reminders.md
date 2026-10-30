# 0006: Confirmation reminders after one day and one week

Accepted, 2026-10-30. Supersedes ADR 0001's seven-day retention for
products that enable confirmation reminders. ADR 0002's one-off imported
reminder and ADR 0005's invitation follow-ups remain separate.

The owner requested the same day-one and day-seven cadence for people who
have signed up but have not confirmed their email address.

## Decision

Products opt in with `confirmation_reminders: true`. There are exactly two
steps, after 24 and 168 hours from signup. A sweep at minute 10 each hour
queues eligible records. Delivery also requires at least 24 hours since the
latest requested confirmation email, and the second reminder requires a
successful first reminder at least six days earlier. Backlogs therefore
receive the first once, then wait six days; no catch-up burst is sent.

Only unconfirmed `site` and `form` signups with an original confirmation
email recorded are eligible. Existing recent signups are included without
rewriting their consent or experiment attribution. Imported contacts and
anyone with the older `reminder_sent_at` marker are excluded: their migration
email promised a single reminder. No reminder follows confirmation, approval,
deletion, expiry or disabling the product setting. A manual resend does not
reset either consumed step.

Each step stores checked, sent and failed timestamps. Render before claiming
so a broken template consumes nothing; claim with a conditional update so
duplicate jobs send once. Recheck confirmation, approval, existence and
configuration before SMTP. An SMTP error or worker crash after claiming
never automatically retries, since delivery may have succeeded. Investigate
without clearing claims blindly. As with invitation follow-ups, confirmation
can race the final check and SMTP; there is no database lock across SMTP.

The confirmation window is normally 14 days from signup. New eligible
signups store an explicit `confirm_by`; older ones without it use the
product's window. Before sending, a first reminder extends the deadline to
at least 13 days from its claim; the final reminder extends it to at least
seven days from its claim. This leaves time to act after delayed delivery.
Each email names its date. Retention deletes on the daily sweep after that
deadline, or the product's normal window when there is no explicit date.
Products without reminders retain the seven-day default; imports retain
their own existing deadlines. Disabling reminders preserves explicit dates.

Both messages have the product's existing branding, one confirmation button,
a leave link, and plain-text and HTML parts. They contain no advertising,
tracking pixels or external eligibility checks. Clicking a confirmation link
still opens the existing confirmation page; a mail scanner cannot confirm
by following a GET. No new data leaves for analytics. The initial email,
new signup consent, public notices and admin retention text explain the
enabled sequence. Invitation reminders remain day one and day seven after
the key email, independently stopped by activation.

## Rollout and operations

Publish the notice, back up both databases, deploy the additive migration
and opted-in product, then inspect due counts before an initial sweep. Keep
existing import markers and all invitation timestamps. The owner explicitly
authorised enabling this sequence for existing recent unconfirmed signups.

```ruby
product = Product.find_by!(slug: "solco")
puts [1, 2].map { |step|
  columns = Signup.confirmation_reminder_columns(step)
  {step:, due: product.confirmation_reminder_due(step).count,
   checked: product.signups.where.not(columns[:checked] => nil).count,
   sent: product.signups.where.not(columns[:sent] => nil).count,
   failed: product.signups.where.not(columns[:failed] => nil).count}
}
```

Sent means SMTP accepted the message, not that it reached the inbox. Removing
the setting and syncing stops queued sends. Preserve the timestamps on
rollback; explicit deadlines work with the earlier retention job too.
