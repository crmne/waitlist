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
- `signup_experiments`: fixed experiment names, each with an ISO 8601
  `started_at`, an optional exclusive `ended_at`, and a list of `variants`.
  Set an end when replacing a test so later unattributed signups do not
  also enter its historical report. A new signup may submit an
  `experiment`/`variant` pair from that allowlist. It is saved with the
  signup, never changed by a repeat submission, included in CSV exports,
  and added to its browser's `Waitlist: Confirmed` event. The admin shows
  signed-up, confirmed and pending counts since the experiment started,
  plus unattributed entries. These are retained records across all statuses,
  independent of browser analytics and the people-list filters. Deletion and
  retention remove them from the report too. Update the product's privacy
  notice before enabling this;
- `on_approve`: a webhook called when you approve someone, with a Bearer
  token from a file. Its JSON answer must name an id (`id_field`); its other
  fields fill the approval email and are never stored. `sent_url` is told
  once that email went out (`app/models/approval_webhook.rb`);
- `approval_email`: a template file, a `Subject:` line then a small Markdown
  body with `{{variables}}`.
- `confirmation_reminders: true`: two confirmation reminders after one day
  and one week, cancelled on confirmation or leaving. The second is at least
  six days after the first. The confirmation window is normally 14 days,
  extended for late reminders; imported contacts retain their one-off email.
  See [the confirmation reminder contract](docs/adr/0006-two-confirmation-reminders.md).
- `approval_follow_up`: one or two ordered `steps`, each with `after_hours`
  (1..168), `template` and optional `variables`. Requires
  `on_approve.follow_up_url`. Each step checks eligibility before sending;
  a late first email preserves the configured gap before the second.
  See [the follow-up contract](docs/adr/0005-two-spaced-approval-follow-ups.md).
- `analytics`: cookieless counting with Plausible on the public pages
  (`plausible_script`, `page_url`). Events are reported under
  `page_url/form`, `/thanks` and `/confirmed`, never the page's own address
  or referrer, so no token or referral code leaves: a referral visit, a
  hosted-form signup, a confirmation (and whether a referral brought it),
  and the referral link copied. Nothing is counted in a frame.

Runtime settings are environment variables: `PUBLIC_HOST`,
`SECRET_KEY_BASE_FILE`, `ADMIN_PASSWORD_FILE`, `SMTP_ADDRESS`,
`SMTP_USERNAME_FILE`, `SMTP_PASSWORD_FILE` (mail is written to
`storage/mail` until all three are set), `PRODUCTS_FILE`, `ROOT_REDIRECT`.

Counts to a log server (optional): with `OTEL_EXPORTER_OTLP_ENDPOINT` (an
OTLP/HTTP base such as `https://logs.example/ingest/otlp`) and
`SEQ_API_KEY_FILE` (sent as Seq's `X-Seq-ApiKey`), `MetricsJob` sends each
product's counts every ten minutes as OpenTelemetry gauges
(`app/models/metrics_report.rb`): people by status, source and referral,
signups and confirmations today, and invitations by state. Only counts and
fixed words leave, never an address, answer, code or time.
`OTEL_RESOURCE_ATTRIBUTES` names the service, environment and host.

## Endpoints

- `GET /p/PRODUCT` the hosted form (`?embed=1` to frame it, `?ref=CODE` for a
  referral); `POST /p/PRODUCT/signups` takes it, or JSON with `email`,
  `elapsed_ms` (how long your page was open), an empty `website`, and
  optional `answers`, `ref`, `experiment` and `variant`. Unknown or malformed
  experiment pairs are ignored. Without JavaScript, link to the hosted form.
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

A deployment keeps its products file, brand folders and Kamal config in its
own repository and layers them onto this image (`COPY` into `/rails/deploy`,
`PRODUCTS_FILE=/rails/deploy/products.yml`). Why it exists: [ADR 0001](docs/adr/0001-self-hosted-waitlist.md),
[ADR 0002](docs/adr/0002-generic-products-branded-emails.md),
[ADR 0004](docs/adr/0004-signup-experiment-attribution.md).
