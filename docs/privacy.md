# What the waitlist keeps, and for how long

| Data | Why | Kept |
|---|---|---|
| Email address | to confirm it and write when there's a place | until the person leaves, is deleted, or the confirmation deadline passes: normally 14 days with confirmation reminders (extended for late reminders), otherwise 7 days; imported unconfirmed contacts keep their existing 14-day deadline |
| Answers to the optional questions | to choose who gets in first | with the address |
| Fixed experiment and variant labels, when configured and submitted with a new signup | to compare which version leads to signups and confirmations, even if browser analytics is unavailable | with the address; repeats never change the original assignment |
| Signup, confirmation and approval times; where the signup came from (the hosted form, the product site's own form, or an import); the consent line shown | to keep the line in order and show what was agreed | with the address |
| Personal referral code; who referred them (if anyone); how many people they referred confirmed | to move people up the line for referrals | with the address. Nobody is told who joined through their link; deleting the referrer drops the link between them |
| Approval reference (after approval, from the product's webhook) | to see who has a key | with the address; approved people are deleted 90 days after approval |
| Optional follow-up check, send and failure times for each of two steps | to send at most two getting-started follow-ups after an invitation | with the address, under the same retention |
| Optional confirmation reminder check, send and failure times for each of two steps | to send at most two reminders before confirmation | with the address, under the same retention |
| Keyed digest of an address that left | so an import never adds them back | until they sign up again |

Not stored anywhere: IP addresses, user agents, the page someone came from,
cookies on public pages, request logs. The rate limiter keeps an HMAC of the
address, with a key that changes on every restart, in memory for at most ten
minutes. The spam checks keep nothing: a honeypot field, a signed start time
in the hosted form (or the time the product site's page was open), and a DNS
lookup of the address's domain, cached in memory for at most an hour.
Counts leave, never people: every ten minutes the waitlist sends each
product's totals (people by status, by source and by whether a referral
brought them, signups and confirmations that day, invitations by state) to
our own log server, Seq on our own hardware (`MetricsJob`). They are
numbers with fixed labels, never an address, answer, referral code,
reference or time, so they describe no one.
Leaving sends one email confirming the deletion; its queued job holds the
address until it runs, and finished jobs are cleared within the hour. An
approval email may carry a licence key from the approval webhook; the key is
never stored or queued here. The owner gets an email for each confirmed signup (the address, answers,
place and referral count), sent through the same SES account. Cloudflare still processes requests and IPs under its own terms,
and the SMTP provider handles each email it delivers.

An opted-in product sends confirmation reminders after one day and one week
from signup, at least six days apart, only while the address is unconfirmed.
These stop on confirmation, leaving or expiry. Imports that received the
one-off migration reminder are excluded. The confirmation window is normally
14 days; late reminders extend it to leave seven days after the final reminder.
Each email states its deadline. Retention runs daily after that deadline.

An opted-in product can send up to two getting-started follow-ups after its invitation.
The waitlist asks the product's private service for a yes/no eligibility decision
using the existing signup reference immediately before sending. It stores no
activation or usage details and tracks no email opens. Each follow-up has a
leave link. Existing consent records are never rewritten; new forms disclose
the follow-ups when the product enables them.

Legal basis: consent (Art. 6(1)(a) GDPR), confirmed by email. Leaving
withdraws it and deletes the record at once. Controller: PlentyLabs UG
(haftungsbeschränkt) & Co. KG.

A configured experiment's fixed labels also accompany its browser's
`Waitlist: Confirmed` event. No email, token or referral code is sent to
analytics. No browser event is sent by the server. Existing entries without
labels remain unattributed; no browsing history is reconstructed.

A product's privacy notice should say the same in its own words: what is
kept and why, its confirmation reminders and deletion window, the leave link, referrals
(counted, never shown), that no IP is stored, and who delivers the email.
