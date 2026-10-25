# Waitlist

A small self-hosted waitlist for one or more products: a form per product
(hosted, embeddable, or your own site posting JSON), double opt-in, referral
links that move people up the line, quiet spam refusal, branded emails, an
admin with counts, approval and CSV export, and an optional webhook that
runs when you approve someone. It keeps no IP addresses or cookies on public
pages. Rails 8, SQLite, Solid Queue inside Puma.

## Configure

Products live in a YAML file: `config/products.yml` is a documented
example; point `PRODUCTS_FILE` at your own. Each product sets its name,
sites, sender, optional questions, brand (logo, colours, fonts, legal
footer), and optionally:

- `notify`: who gets an email when someone confirms;
- `on_approve`: a webhook called when you approve someone, with a Bearer
  token from a file. Its JSON answer must name an id (`id_field`); its other
  fields fill the approval email and are never stored. `sent_url` is told
  once that email went out (`app/models/approval_webhook.rb`);
- `approval_email`: a template file, a `Subject:` line then a small Markdown
  body with `{{variables}}`.

Runtime settings are environment variables: `PUBLIC_HOST`,
`SECRET_KEY_BASE_FILE`, `ADMIN_PASSWORD_FILE`, `SMTP_ADDRESS`,
`SMTP_USERNAME_FILE`, `SMTP_PASSWORD_FILE` (mail is written to
`storage/mail` until all three are set), `PRODUCTS_FILE`, `ROOT_REDIRECT`.

## Endpoints

- `GET /p/PRODUCT` the hosted form (`?embed=1` to frame it, `?ref=CODE` for a
  referral); `POST /p/PRODUCT/signups` takes it, or JSON with `email`,
  `elapsed_ms` (how long your page was open), an empty `website`, and
  optional `answers` and `ref`. Without JavaScript, link to the hosted form.
- `/confirm/TOKEN`, `/leave/TOKEN` from the emails.
- `/admin` (HTTP Basic, user `admin`).
- `/brands/PRODUCT/FILE` the brand folder's png, css, woff2 and txt files.

Spam is refused quietly (a normal answer, nothing stored or sent): a
honeypot (invisible_captcha), a 3-second minimum, plus an MX check with a
clear error and an in-memory rate limit. Each confirmed referral moves the
referrer up `places_per_referral` places.

`bin/getwaitlist-pull` and `bin/rails "getwaitlist:import[PRODUCT]"` move a
list from GetWaitlist; `getwaitlist:remind` sends imported unconfirmed people
one reminder.

## Develop

```sh
bin/setup --skip-server
bin/rails test
ADMIN_PASSWORD=dev bin/rails server   # mail goes to tmp/mails
```

This repository's own deployment (PlentyLabs' products) is in `deploy/` and
`config/deploy.yml`; see [docs/deployment.md](docs/deployment.md). Why it
exists: [ADR 0001](docs/adr/0001-self-hosted-waitlist.md),
[ADR 0002](docs/adr/0002-generic-products-branded-emails.md).
