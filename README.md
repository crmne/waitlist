# Waitlist

One small self-hosted waitlist for all of PlentyLabs' products, at
`waitlist.plenty.is`. Each product has its own form, confirmation email
(double opt-in), leave link and admin view. No IP addresses or cookies.
Why it exists and what it replaced: [ADR 0001](docs/adr/0001-self-hosted-waitlist.md).

- Products: `config/products.yml`
- Form: `GET /p/PRODUCT` (frameable with `?embed=1`), or post JSON to
  `POST /p/PRODUCT/signups` with `email`, `elapsed_ms`, `website` (empty),
  optional `answers` and `ref`. A static site without JavaScript should
  link to the hosted form, which carries its own spam timing.
- Referrals: each confirmed person gets `/p/PRODUCT?ref=CODE`; every
  confirmed referral moves them up `places_per_referral` places (default 5).
  `ref_id=` (GetWaitlist's links) works too.
- Spam: honeypot (invisible_captcha), a 3-second minimum (signed `started`
  field, or `elapsed_ms` from a product site's script), an MX check, and 10
  tries per 10 minutes per address, all in memory.
- Each confirmed signup emails the product's `notify` address.
- Admin: `/admin` (HTTP Basic, user `admin`)
- Acme licences on approval: `app/models/licence_issuers/acme_licence.rb`
  registers one with licence-server; Carmine signs and emails the key
- [Deployment](docs/deployment.md), [privacy and retention](docs/privacy.md),
  [moving off GetWaitlist](docs/migration.md)

```sh
bin/setup --skip-server
bin/rails test
ADMIN_PASSWORD=dev bin/rails server   # mail goes to tmp/mails
```
