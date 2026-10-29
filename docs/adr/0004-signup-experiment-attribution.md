# 0004: Save fixed experiment labels with a new signup

Status: accepted. Date: 2026-10-29.

## Context

A product's headline test recorded no browser conversion for a signup that
was present in the waitlist database. Browser analytics can be unavailable,
blocked or interrupted. The cause of this particular missing event could
not be established, and the original variant cannot be recovered. An
accepted form response also does not establish a new person: repeats and
quietly refused spam receive the same response.

## Decision

Products may configure experiment names, start times and allowed variants.
Only a configured pair of fixed string labels, each at most 64 characters,
is accepted. Store it on a newly created signup, alongside the existing
source field. Missing, malformed or unknown labels do not block signup and
are not stored. Repeat submissions never replace or backfill attribution.
Clients must omit labels for preview traffic; legacy and preview entries
remain unattributed. Do not infer historic assignments.

The admin counts retained signup records created since the configured start
by variant, with signed-up, confirmed and pending totals and an unattributed
row. Other experiments and products are excluded; list filters do not change
the summary. CSV exports include the labels. Removing an experiment from
configuration hides its report, so retain historic definitions when needed.

Confirmation reads the saved labels and adds them only to the existing
browser `Waitlist: Confirmed` event. It does not label confirmation
pageviews, send personal identifiers or send server-side analytics events.
The database is authoritative for retained records; browser counts remain
partial when analytics is unavailable. Neither proves sales or activation.

## Consequences

No cookies, local storage, cross-visit identifier, IP, user agent or referrer
is added. The labels share the signup's deletion and retention policy,
including deletion of unconfirmed entries after seven days. Therefore the
admin summary is not a permanent cumulative event counter. Product privacy
notices must describe saving these labels and their purpose before clients
send them. The additive migration leaves existing records unattributed.
