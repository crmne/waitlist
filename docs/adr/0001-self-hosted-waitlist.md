# 0001: One small self-hosted Rails waitlist for every product

Date: 2026-10-25. Status: accepted, not yet deployed.

## Context

Carmine decided on 2026-10-25 to stop using GetWaitlist (Waitlist LLC,
USA): it offers no data processing agreement and no transfer safeguard
(Acme privacy self-check, finding 1). Every waitlist he runs moves to one
self-hosted service. Acme's alpha is private with per-person licence keys,
so the Acme waitlist is how people ask for a key, and approving someone
must lead to a key.

GetWaitlist held five waitlists on 2026-10-25 (counts only):

| Waitlist | Signups | Verified | Form today |
|---|---|---|---|
| Acme (33098) | 50 | 30 | live on example.com |
| Chat with Work (18565) | 313 | 3 (verification was off) | retired: `/waitlist` redirects to sign-up |
| Lineup (26073) | 24 | 1 | closed; lineup.website redirects to plenty.is |
| FlareHub (26074) | 3 | 0 | none; flarehub.app redirects to plenty.is |
| Vettr (22859) | 2 | 1 | vettr.ai no longer uses it and is not in our DNS |

Requirements: several products, each with its own form (embeddable or a
plain HTML form endpoint) and confirmation email (double opt-in); data on
our server with no IP addresses stored; a protected admin with counts and
export; leaving and deletion; and for Acme a hook that issues a licence
key when Carmine approves someone.

## Options

**Existing self-hosted projects**, checked 2026-10-25:

- listmonk (AGPL-3.0, Go, actively maintained) is the strongest: lists,
  double opt-in, public subscription forms, admin, export, unsubscribe, and
  opt-in IP recording that can be turned off. But it needs PostgreSQL (one
  more database container on a host with about 2.5 GB available), it is a
  newsletter tool with campaigns we don't want, one opt-in template serves
  every list, and it has no approval step: issuing a Acme licence would
  mean polling its API from another service.
- Keila (AGPL, Elixir) and Mautic (PHP, heavy) are newsletter or marketing
  suites with the same gaps and more weight.
- Projects that call themselves waitlists (Launchlist, Chirp, Waiting
  Lists, Queuecraft) are a Node and Postgres template, Railway templates, a
  Cloudflare Workers app and a paid product: none offers double opt-in,
  admin, export and Docker together under a clear open-source licence.

**A small Rails 8 app** on the stack and host licence-server already uses:
SQLite, Solid Queue inside Puma, Kamal with no shared proxy, a Cloudflare
Tunnel, secrets on tmpfs. The whole thing is three tables, five public
routes and an admin, under 900 lines plus tests. It stores exactly what we
choose (no IP, no referral data), the approval hook is a method call, and
it runs in one 256 MB container plus a 64 MB tunnel.

## Decision

Build the small Rails app (`crmne/waitlist`), served at
`waitlist.plenty.is`, because it is less to run than listmonk with
PostgreSQL, matches the existing deployment exactly, and does the one thing
no candidate does: approval that issues a licence. Its parts:

- Products come from `config/products.yml` (synced on boot, never deleted
  by a sync): name, sites allowed to post and frame, sender, privacy link,
  optional questions, optional approval step, how long approved people are
  kept.
- `GET /p/:product` is a hosted form (frameable by the product's sites);
  `POST /p/:product/signups` takes a plain HTML form post or JSON (CORS for
  the product's sites). The answer is the same whether or not the address
  was already there. A honeypot field and a per-address rate limit (on an
  HMAC of the address, in memory only) stop casual abuse.
- Double opt-in: the confirmation email links to a page with a button, so
  a mail scanner following links confirms nobody. Tokens are signed, never
  stored. Unconfirmed signups are deleted after seven days.
- Every email and page has a leave link that deletes the person. A keyed
  digest of the address is kept so an import can't add them back.
- The admin (HTTP Basic, password from tmpfs) shows counts per product,
  lists people in line with their answers, approves, deletes (after a
  confirmation page naming the address) and exports CSV.
- No referral positions: places in line follow signup time, and Carmine
  chooses who gets in. The Acme site's "share your link to move up" goes.

## Licence keys

Approving a Acme signup enqueues `ApprovalJob`, which calls
`LicenceIssuers::AcmeLicence#issue`. It is a marked integration point that
issues nothing yet. The licence-key work in licence-server fills it in:
call licence-server on the internal Docker network with a shared token from
tmpfs, idempotent per signup; licence-server delivers the key and owns
revocation; this app stores only the reference it returns and never the
key.

## Consequences

- One more small container and tunnel on prod, both capped.
- Mail needs a sending account: SES in Frankfurt (what Chat with Work
  already uses) with example.com added as a verified identity, or Forward
  Email's SMTP for example.com. Until its credentials are on the host,
  nothing is sent.
- GetWaitlist signups move with `bin/getwaitlist-pull` and
  `getwaitlist:import` (docs/migration.md): only verified people, as
  confirmed, without an email.
