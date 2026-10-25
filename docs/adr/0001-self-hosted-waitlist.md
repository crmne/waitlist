# 0001: One small self-hosted Rails waitlist for several products

Date: 2026-10-25. Status: accepted.

## Context

The products used a hosted waitlist service in the USA with no data
processing agreement and no transfer safeguard. Every waitlist moves to one
self-hosted service, run on the same host and stack as the products' own
Rails apps. One product's alpha is private with per-person licence keys, so
its waitlist is how people ask for a key, and approving someone must lead to
a key.

Requirements: several products, each with its own form (embeddable or a
plain HTML form endpoint) and confirmation email (double opt-in); data on
our server with no IP addresses stored; a protected admin with counts and
export; leaving and deletion; and a hook that runs when someone is approved.

## Options

**Existing self-hosted projects**, checked 2026-10-25:

- listmonk (AGPL-3.0, Go, actively maintained) is the strongest: lists,
  double opt-in, public subscription forms, admin, export, unsubscribe, and
  opt-in IP recording that can be turned off. But it needs PostgreSQL (one
  more database container on a small shared host), it is a newsletter tool
  with campaigns we don't want, one opt-in template serves every list, and
  it has no approval step: issuing a licence would mean polling its API from
  another service.
- Keila (AGPL, Elixir) and Mautic (PHP, heavy) are newsletter or marketing
  suites with the same gaps and more weight.
- Projects that call themselves waitlists (Launchlist, Chirp, Waiting
  Lists, Queuecraft) are a Node and Postgres template, Railway templates, a
  Cloudflare Workers app and a paid product: none offers double opt-in,
  admin, export and Docker together under a clear open-source licence.

**A small Rails 8 app**: SQLite, Solid Queue inside Puma, Kamal with no
shared proxy, a Cloudflare Tunnel, secrets on tmpfs. Three tables, five
public routes and an admin. It stores exactly what we choose (no IP), the
approval hook is a method call, and it runs in one small container.

## Decision

Build the small Rails app. Products come from a products file (synced on
boot, never deleted by a sync). Each has a hosted form (frameable by its own
sites) and a JSON endpoint; the answer is the same whether or not the
address was already there. Double opt-in: the confirmation email links to a
page with a button, so a mail scanner following links confirms nobody.
Tokens are signed, never stored. Unconfirmed signups are deleted after seven
days. Every email has a leave link that deletes the person; a keyed digest
of the address is kept so an import can't add them back. The admin (HTTP
Basic, password from tmpfs) shows counts, lists people in line, approves,
deletes after a confirmation page, and exports CSV.

Approval runs a product's webhook (see ADR 0002).

## Consequences

- One small container and its tunnel on the host.
- Mail needs an SMTP account; until its credentials are installed, mail is
  written to the storage volume and nobody is emailed.
- Signups move from the hosted service with `bin/getwaitlist-pull` and
  `getwaitlist:import`: verified people as confirmed, without an email.
