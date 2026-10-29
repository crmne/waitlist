# 0003: One optional follow-up after an invitation

Accepted, 2026-10-29. Carmine requested one follow-up about a day after the
licence email for someone who has not activated Solco. This extends ADR 0002:
the waitlist remains generic; the product decides eligibility and supplies copy.

Superseded before deployment by [ADR 0005](0005-two-spaced-approval-follow-ups.md)
on 30 October, following the owner's request for reminders after a day and a week.
The original proposal below remains as decision history.

Products opt in with `approval_follow_up` (`after_hours`, `template`,
`variables`) and `on_approve.follow_up_url`. At minute 5 each hour,
`ApprovalFollowUpsJob` queues confirmed, approved signups whose successful
invitation email is at least that old, and who have not been checked yet.
Solco uses 24 hours: normally the next hourly sweep after 24 hours, plus
queue time. Existing older invitations are included on the first sweep.
There is no sequence, reissue, key stored in a queue, or email-open tracking.

At execution the job reloads the signup and product, and checks the deadline
again. It POSTs `{"reference":"waitlist-REFERRAL_CODE"}` to the private
product service with the existing token. Only a 2xx JSON response containing
a literal boolean `send_follow_up` is accepted. False consumes the check
without a message. Errors send nothing and leave it eligible for retry.
The service returns no licence key, address, activation details or usage.

A conditional database update claims the check before SMTP. Duplicate jobs
may check twice but only one claims delivery. Neither HTTP nor SMTP holds a
database lock. Deleted signups and withdrawn approvals are checked again;
leaving the list deletes the signup and cancels pending work. A final external
activation can still race the short interval between the check and delivery.

Three nullable timestamps record the check, successful send and failed send.
All expire with the existing signup retention. SMTP errors and worker crashes
after claiming do not release the claim: a server might have accepted a message
even if its response was lost. Such attempts require operator investigation;
never clear the claim blindly or automatically resend. The follow-up includes
the usual leave link, List-Unsubscribe header and product reply-to address.

Deploy the product's status endpoint first, then migrate and deploy this
application and enable product configuration. An older service responds 404,
which sends no email. Removing `approval_follow_up` stops queued follow-ups
once configuration is synced; timestamps remain, so re-enabling never repeats
a consumed attempt. Rolling back code requires no database rollback.

Operator counts, with a local or authorised production Rails runner:

```ruby
p = Product.find_by!(slug: "solco")
puts({due: p.approval_follow_up_due.count,
  checked: p.signups.where.not(approval_follow_up_checked_at: nil).count,
  sent: p.signups.where.not(approval_follow_up_sent_at: nil).count,
  failed: p.signups.where.not(approval_follow_up_failed_at: nil).count})
```

`due` is before the service's activation check, not a predicted send count.
