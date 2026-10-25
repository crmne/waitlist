# Waitlist

One small self-hosted waitlist for all of PlentyLabs' products, at
`waitlist.plenty.is`. Each product has its own form, confirmation email
(double opt-in), leave link and admin view. No IP addresses or cookies.
Why it exists and what it replaced: [ADR 0001](docs/adr/0001-self-hosted-waitlist.md).

- Products: `config/products.yml`
- Form: `GET /p/PRODUCT` (frameable with `?embed=1`), or post a plain HTML
  form or JSON to `POST /p/PRODUCT/signups` with `email` and optional
  `answers[QUESTION]`.
- Admin: `/admin` (HTTP Basic, user `admin`)
- Acme licence keys on approval: `app/models/licence_issuers/acme_licence.rb`
  (integration point)
- [Deployment](docs/deployment.md), [privacy and retention](docs/privacy.md),
  [moving off GetWaitlist](docs/migration.md)

```sh
bin/setup --skip-server
bin/rails test
ADMIN_PASSWORD=dev bin/rails server   # mail goes to tmp/mails
```
