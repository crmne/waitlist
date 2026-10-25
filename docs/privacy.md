# What the waitlist keeps, and for how long

| Data | Why | Kept |
|---|---|---|
| Email address | to confirm it and write when there's a place | until the person leaves, is deleted, or (unconfirmed) 7 days; someone imported unconfirmed from GetWaitlist and sent one reminder, 14 days from that reminder |
| Answers to the optional questions | to choose who gets in first | with the address |
| Signup, confirmation and approval times; where the signup came from (form or import); the consent line shown | to keep the line in order and show what was agreed | with the address |
| Personal referral code; who referred them (if anyone); how many people they referred confirmed | to move people up the line for referrals | with the address. Nobody is told who joined through their link; deleting the referrer drops the link between them |
| Approval reference (after approval, from the product's webhook) | to see who has a key | with the address; approved people are deleted 90 days after approval |
| Keyed digest of an address that left | so an import never adds them back | until they sign up again |

Not stored anywhere: IP addresses, user agents, the page someone came from,
cookies on public pages, request logs. The rate limiter keeps an HMAC of the
address, with a key that changes on every restart, in memory for at most ten
minutes. The spam checks keep nothing: a honeypot field, a signed start time
in the hosted form (or the time the product site's page was open), and a DNS
lookup of the address's domain, cached in memory for at most an hour.
Leaving sends one email confirming the deletion; its queued job holds the
address until it runs, and finished jobs are cleared within the hour. An
approval email may carry a licence key from the approval webhook; the key is
never stored or queued here. The owner gets an email for each confirmed signup (the address, answers,
place and referral count), sent through the same SES account. Cloudflare still processes requests and IPs under its own terms,
and the SMTP provider handles each email it delivers.

Legal basis: consent (Art. 6(1)(a) GDPR), confirmed by email. Leaving
withdraws it and deletes the record at once. Controller: PlentyLabs UG
(haftungsbeschränkt) & Co. KG.

A product's privacy notice should say the same in its own words: what is
kept and why, the confirmation and 7-day deletion, the leave link, referrals
(counted, never shown), that no IP is stored, and who delivers the email.
