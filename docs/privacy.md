# What the waitlist keeps, and for how long

| Data | Why | Kept |
|---|---|---|
| Email address | to confirm it and write when there's a place | until the person leaves, is deleted, or (unconfirmed) 7 days |
| Answers to the optional questions | to choose who gets in first | with the address |
| Signup, confirmation and approval times; where the signup came from (form or import); the consent line shown | to keep the line in order and show what was agreed | with the address |
| Licence reference (Acme, after approval) | to see who has a key | with the address; approved people are deleted 90 days after approval |
| Keyed digest of an address that left | so an import never adds them back | until they sign up again |

Not stored anywhere: IP addresses, user agents, referrers, referral data,
cookies on public pages, request logs. The rate limiter keeps an HMAC of the
address, with a key that changes on every restart, in memory for at most ten
minutes. Cloudflare still processes requests and IPs under its own terms,
and the SMTP provider handles each email it delivers.

Legal basis: consent (Art. 6(1)(a) GDPR), confirmed by email. Leaving
withdraws it and deletes the record at once. Controller: PlentyLabs UG
(haftungsbeschränkt) & Co. KG.

## Paragraph for each product's privacy notice

Replace the GetWaitlist paragraph with this (product name and sender
adjusted). For Acme, example.com/privacy:

> **Waitlist.** When you join the waitlist we keep your email address, your
> answers to the optional questions and when you signed up, confirmed and
> were invited, so we can write to you when there is a place and choose who
> gets in first. We ask you to confirm your address by email first; if you
> don't confirm within seven days, it is deleted. The waitlist runs on our
> own server at Hetzner in Nuremberg, Germany (waitlist.plenty.is); we don't
> store your IP address or use cookies there. Cloudflare passes the request
> to our server, and Amazon Web Services EMEA SARL, from Frankfurt,
> delivers the confirmation email. The legal basis is
> your consent (Art. 6(1)(a) GDPR). Every email has a link to leave the list,
> which deletes your details at once; you can also write to
> hello@plenty.is. Once you are invited, your waitlist entry is deleted 90
> days later; your licence is covered by the app's privacy notice.

For Chat with Work (privacy policy, the "getwaitlist.com for historical
signup interest records" item): remove the item once the GetWaitlist list is
deleted (docs/migration.md). It moves nothing here.

example.com/privacy is bilingual; the German text (replacing the two
GetWaitlist paragraphs in the German part):

> **Warteliste.** Wenn Sie sich auf die Warteliste setzen, speichern wir Ihre
> E-Mail-Adresse, Ihre Antworten auf die freiwilligen Fragen und wann Sie
> sich angemeldet, bestätigt und eine Einladung erhalten haben, damit wir
> Ihnen schreiben können, sobald ein Platz frei ist, und auswählen können,
> wer zuerst dabei ist. Sie bestätigen Ihre Adresse zuerst über einen Link
> per E-Mail; ohne Bestätigung wird sie nach sieben Tagen gelöscht. Die
> Warteliste läuft auf unserem eigenen Server bei Hetzner in Nürnberg
> (waitlist.plenty.is); dort speichern wir Ihre IP-Adresse nicht und setzen
> keine Cookies. Cloudflare leitet die Anfrage an unseren Server weiter, und
> Amazon Web Services EMEA SARL, aus Frankfurt, stellt
> die Bestätigungs-E-Mail zu. Rechtsgrundlage ist Ihre Einwilligung (Art. 6
> Abs. 1 lit. a DSGVO). Jede E-Mail enthält einen Link, mit dem Sie die
> Warteliste verlassen; Ihre Angaben werden dann sofort gelöscht. Sie können
> auch an hello@plenty.is schreiben. Nach Ihrer Einladung wird Ihr Eintrag
> auf der Warteliste 90 Tage später gelöscht; Ihre Lizenz ist in der
> Datenschutzerklärung der App beschrieben.

Mail goes through Amazon SES in Frankfurt (docs/deployment.md, "Mail").
Amazon Web Services EMEA SARL is the AWS contracting party for EEA
customers, and the AWS data processing addendum is part of its terms. Check
that the AWS account's company details name the KG, as for the other
processors in the privacy self-check.
