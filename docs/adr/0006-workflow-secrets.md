# 0006. Where the workflows' secrets live, and what code runs beside them

- Status: Accepted

## Context

Publishing and re-signing need the signing key and a Cloudflare token
([ADR 0005](0005-publishing.md), [ADR 0004](0004-index-freshness.md)).
Any code that runs in a job holding them can use them, including the
actions the job calls.

## Decision

- The keys and a Cloudflare API token limited to editing Workers
  scripts on the one account, with that account's ID, are secrets of a
  GitHub Actions environment, `publish`, in this repository, which
  accepts jobs from `main` only. Only the workflows of this repository
  reach them, so pushing a tag or changing a workflow in a project's
  repository does not.
- Every action the workflows use is pinned to a commit, with the tag it
  was taken from in a comment (`actions/checkout@<sha> # v7.0.1`), and
  moves only when a pull request changes that line. A test fails on a
  `uses:` line in any other form.

## Alternatives

- **Secrets of the repository rather than of an environment.** Every
  workflow on every branch could read them.
- **Actions referenced by tag (`actions/checkout@v4`).** A tag can be
  moved to other code after it is reviewed. Fixes would arrive without a
  pull request, and so would any code the tag was moved to by someone
  who took over the action's repository, run in a job holding the keys.
- **`gh-actions-lock`, which writes the commit of every action and of
  the actions they call into a lockfile and checks it in CI and on the
  runner.** Its advantage over a pinned `uses:` line is the actions an
  action calls, and the one action used, `actions/checkout`, calls none.
  It is a public preview whose lockfile format and flags may change
  before 1.0, and it needs a workflow of its own to verify the lockfile.
  Worth taking up once a workflow uses an action that calls others, such
  as a shared composite action, or once it reaches 1.0.

## Consequences

- Updating an action is a pull request that changes its commit and its
  comment together.
