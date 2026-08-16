# Admin Household Data Export

## Goal

Allow a household owner or admin to download the active household's shared data
from Settings as one CSV file.

## Scope

`GET /api/household/data` returns a normalized CSV with one row per
`record_type`:

- `household`: household name, initials, and creation time
- `member`: member identity, role, avatar colour, and verification state
- `chore`: chore metadata, metrics, indicators, subjects, and ordering
- `log`: complete activity history, including notes and metrics
- `schedule`: recurrence and assignment configuration
- `day_note`: shared diary notes and update metadata
- `invite`: invite lifecycle metadata without the invite code

Rows are scoped to the authenticated user's active household and sorted for
repeatable exports. CSV cells are protected against spreadsheet formula
injection.

The export deliberately excludes passwords, sessions, authentication tokens,
push endpoints, notification contents, private UI preferences, and invite
codes. Invite codes are bearer capabilities and must not be copied into a
download that may be shared.

## Authorization

The handler delegates role verification to the household service, which reads
the current membership from the store. Only `owner` and `admin` memberships
are accepted. The endpoint does not accept a household ID, so a caller cannot
select another household by changing a query parameter.

## Client Work

- PWA Settings shows an `Export Data` card only for owners and admins.
- iOS Settings shows the same action using the native share sheet.
- The existing member-accessible log-only CSV remains unchanged.

## Verification

- Handler tests cover complete rows, formula-safe cells, role denial, and
  capability omission.
- Playwright covers the Settings affordance, admin download, and member denial.
- iOS Activity tests cover the raw CSV download path.
- Build, vet, Go tests, JS tests, parity lint, and the export E2E spec are run
  before review.
