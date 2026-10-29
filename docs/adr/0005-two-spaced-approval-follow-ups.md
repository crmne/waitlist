# 0005: Two spaced getting-started reminders

Accepted, 2026-10-30. Supersedes [ADR 0003](0003-one-approval-follow-up.md).
Before activation of the prepared single reminder, Carmine requested one
after a day and another after a week for people who have not activated.

`approval_follow_up.steps` contains one or two ordered entries. Each names
`after_hours` (1..168, increasing), its template and optional variables.
Solco uses 24 and 168 hours from the successful original invitation email.
The sweep runs at minute 5 each hour, so delivery is after the threshold,
normally within an hour plus queue time.

The second step also requires a successful first send at least the configured
interval earlier (six days for Solco). This preserves spacing for old
invitations and queue delays: enabling a backlog never sends both at once.
A suppressed or uncertain first delivery does not advance to step two.
There is no third message. Each step has its own copy and leave link.

Every job reloads its signup and configuration and checks with the product's
private service immediately before delivery. Activated, expired, revoked,
test or unknown Solco licences are ineligible. A false decision consumes that
step; network or malformed responses send nothing and remain retryable.
Deletion or disabled configuration cancels queued work. The status check
cannot be atomic with email delivery, so activation can race that short gap.

Each step has nullable checked, sent and failed timestamps on the signup.
A conditional update claims the step before SMTP, preventing duplicate jobs
from sending twice. SMTP errors and worker crashes after claiming never
automatically resend because delivery may have succeeded. Investigate them
without clearing the claim blindly. Neither HTTP nor SMTP holds a database
lock. No keys, activation details, email opens or click tracking are added.
All six timestamps share the signup's retention and deletion.

Deploy the eligibility endpoint first, migrate the six additive columns,
then boot with the product configuration. Existing older invitations receive
the first message once, subject to the current eligibility check. Removing
`approval_follow_up` and syncing stops pending jobs. Re-enabling preserves
consumed attempts, as does changing the configured delays. Code rollback
needs no database rollback; keep the timestamps.

Operator counts, using an authorised Rails runner:

```ruby
p = Product.find_by!(slug: "solco")
puts [1, 2].map { |step|
  columns = Signup.follow_up_columns(step)
  {step:, due: p.approval_follow_up_due(step).count,
   checked: p.signups.where.not(columns[:checked] => nil).count,
   sent: p.signups.where.not(columns[:sent] => nil).count,
   failed: p.signups.where.not(columns[:failed] => nil).count}
}
```

Due counts precede the external eligibility check and are not predicted sends.
