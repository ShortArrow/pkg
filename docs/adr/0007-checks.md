# 0007. Checks after publishing and re-signing

- Status: Accepted

## Context

A deploy can report success while the site serves something else, and
an install goes through Cloudflare, the `_redirects` rule and GitHub's
asset URLs together ([ADR 0001](0001-package-registry.md)). Re-signing
runs unattended ([ADR 0004](0004-index-freshness.md)).

## Decision

- **After publishing.** Once a run deploys, a job on each architecture
  follows the project's install guide against
  `https://pkg.shortarrow.jp/apt` in fresh `debian:bookworm` and
  `ubuntu:24.04` containers. It checks that `apt-cache madison <package>`
  lists the version just published, installs that version by name and
  runs the command the project gives for checking it. It names the
  version because a maintenance release on an older line is not the
  highest one. A failure of Cloudflare, the redirect or the site is fixed
  and the run repeated. A defect in the package itself cannot be fixed by
  a repeat: the version is withdrawn and the fix ships with the
  project's next release.
- **Re-signing.** The weekly re-signing ends by fetching the live
  `InRelease` and checking that its `Date` and `Valid-Until` are the
  ones just signed, then runs `apt update` against it in a container. A
  failure of any step opens an issue, or comments on the one already
  open, and the next successful run closes it.
- The check that a package installs at all, before anything is
  published, belongs to the project that builds it, and runs in its own
  pull requests and release workflow.

## Alternatives

- **`apt update` alone after re-signing.** It would accept the old index
  until it expires, so a deployment that reports success while the old
  index is still served would pass.
- **Checking the latest version rather than the one just published.** A
  maintenance release on an older line would never be checked.

## Consequences

- A run that never starts opens no issue. GitHub disables a scheduled
  workflow in a public repository after 60 days without activity in the
  repository, so a quiet period longer than that is the one way
  re-signing stops silently. The maintainer re-enables the workflow and
  runs it by hand after such a pause.
