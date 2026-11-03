# 0007: SES complaints and hard bounces remove people; one-click unsubscribe

Accepted, 2026-11-03.

On 3 November 2026 a Hotmail recipient reported Solco's getting-started
follow-up as spam (an SES feedback report through Microsoft JMRP). Nothing
in the waitlist heard about it: the signup stayed, and the next reminder
would have gone to someone who had told their provider they did not want
it. Every email already had a `List-Unsubscribe` link, but it opened a page,
so providers could not unsubscribe on the person's behalf.

## Decision

**Feedback.** SES publishes bounce and complaint events for the waitlist's
configuration set to an SNS topic, which posts them to `POST /hooks/ses_events`.
`SnsMessage` accepts a message only when it names the configured topic
(`SES_EVENTS_TOPIC_ARN`; any AWS account can sign messages from its own
topics), its signing certificate comes over HTTPS from
`sns.<that topic's region>.amazonaws.com`, its SignatureVersion 2 (SHA256)
signature verifies and its Timestamp is within the hour, as Chat with Work's
hooks check theirs. A repeated MessageId is dropped. The subscription is
confirmed only by fetching the `SubscribeURL`
of a verified `SubscriptionConfirmation` on that same host. Everything
else is refused with 403, so a forged complaint cannot delete anyone.

`SesEvent` acts on a complaint or a `Permanent` bounce: for each
recipient, it calls `Signup#forget!` (suppression digest, then delete), or
adds the digest when no signup is left. No email is sent to them. The
product comes from the `product` message tag set on every email when
`SES_CONFIGURATION_SET` is configured; without a known tag, every product
holding the address is affected. `Transient` and `Undetermined` bounces and
other events are only logged, never the address.

A complaint whose feedback type is `not-spam` (a provider withdrawing it) is
ignored. The SNS subscription's filter policy passes only Complaint and
Bounce events.

It is idempotent even past the in-memory MessageId check: repeating an
event finds the
digest present and the signup gone, and a signup created after the reported
email was sent (`mail.timestamp`) is a new consent that an old event never
removes. SNS retries any non-2xx answer, so only real failures (SNS
refusing the confirmation) answer 502.

**One-click unsubscribe (RFC 8058).** Every email with a leave link adds
`List-Unsubscribe-Post: List-Unsubscribe=One-Click`. The provider's POST of
`List-Unsubscribe=One-Click` to the leave link deletes the signup at once,
without a session or CSRF token (public pages have neither), and sends
nothing. GET still only shows the page, so link scanners delete nobody.

**The "you've left" email** is kept only for someone who presses the leave
page's button. It is sent to nobody who unsubscribed through their mail
provider, complained or bounced. Whether it should exist at all is the
owner's open question: removing it means deleting `SignupMailer#left`, its
views and the one line in `LeavesController#create`, and the privacy text
that mentions it.

## Consequences

- Deploy the app with `SES_EVENTS_TOPIC_ARN` before creating the SNS
  subscription, so the confirmation is answered. Set
  `SES_CONFIGURATION_SET` only after the configuration set exists and the
  sending user may use it: SES refuses mail naming an unknown set.
- Production keeps no logs, so transient bounces leave no trace here; SES's
  own reputation metrics still count them.
- A complaint about one product's email affects only that product's signup
  when the tag is present.
- SES's account-level suppression list (bounces and complaints) already
  drops later mail to these addresses from every sender in the account. The
  waitlist's configuration set keeps both reasons explicitly. Someone who
  complained and signs up again gets no confirmation email; that send comes
  back as a permanent bounce (`OnAccountSuppressionList`) and removes the
  new signup too. Clearing them from the account list is a manual step.
