# 0004. Keeping the index fresh

- Status: Accepted

## Context

A signature proves who wrote an index, not when. A validly signed index
stays valid forever unless it says otherwise.

## Decision

- `Release` carries `Date` and `Valid-Until`, 90 days after signing. A
  client refuses metadata that has not been re-signed for 90 days.
- A scheduled workflow re-signs the index weekly, without waiting for
  anyone, and also rebuilds the keyring package when the keys under
  `keyring/` changed, so a keyring change merged to `main` ships within a
  week, or at once when the workflow is run by hand.

## Alternatives

- **No `Valid-Until`.** An attacker or a stale mirror could keep serving
  an old, validly signed index and hide a fix. With it, if re-signing
  stops, users see an expired repository rather than a silently stale
  one.
- **Re-signing only when something is published.** A quiet period of 90
  days would expire the repository.

## Consequences

- The repository must be re-signed at least every 90 days. With weekly
  runs, about twelve can fail before users see an expired repository;
  [ADR 0007](0007-checks.md) says how a failure is noticed.
