# 0005. Publishing a release

- Status: Accepted

## Context

A project's release is made in that project's repository. Writing to the
index needs the signing key and the deploy token, which live in this
repository ([ADR 0006](0006-workflow-secrets.md)). Someone who took over a
project's repository could replace a release, or its assets together
with its `SHA256SUMS`.

## Decision

A workflow in this repository finds new releases itself: every hour,
and when run by hand with a project and a tag, it lists the stable
GitHub Releases of the projects this repository lists, through the
public API with its own `GITHUB_TOKEN`, and starts one publishing run
for each project and version not yet in the index. A project's
repository holds no credential for this one and sends it nothing. The
hourly poll starts a run for a release only once; a run that is still
waiting, was rejected or failed is not started again by the poll, so an
unanswered approval does not pile up a new request every hour.

Every run except the weekly re-signing ([ADR 0004](0004-index-freshness.md))
first waits in an environment, `approve`, which holds no secret and
requires the maintainer's approval. A release replaced by someone who
took over a project's repository therefore reaches users only after the
maintainer has seen it. The approval is a job of its own, outside the
concurrency group below, so a run waiting for it never holds up the
re-signing. A release reaches APT within about an hour of being made, or
at once when the workflow is run by hand, as soon as the maintainer
approves it.

A publishing run:

1. Refuses a release that [ADR 0002](0002-index-contents.md) keeps out.
2. Fetches the published site: `InRelease`, `Packages`, and every file the
   site serves itself, the keyring and its packages. It verifies
   `InRelease` against the keys under `keyring/`, and every fetched file
   against its hash in `Packages`. Any failure stops the job; it never
   signs what it could not verify.
3. Downloads the release's package assets and its `SHA256SUMS`, checks
   each package against it, and replaces that package's entries for this
   version with entries computed from those files, for every
   architecture.
4. If the keys under `keyring/` differ from those in the newest published
   keyring package, in either direction, builds a new keyring package and
   adds it.
5. Writes `Release` with `Date` and `Valid-Until`, signs `InRelease`, and
   deploys the fetched site with these changes as one new version of the
   Worker, with `wrangler deploy`. Each version serves the files its
   upload manifest lists and no others, so a file the job did not carry
   forward would disappear.

A rebuild replaces steps 2 and 3: the job builds the index from the
package assets of every stable release of every project the registry
lists, each checked by the rules of [ADR 0002](0002-index-contents.md),
and the keyring package from `keyring/`, trusting nothing on the live
site. It creates the repository the first time, and recovers it after a
compromise or a failed verification.

A failed run is retried by running it again; the GitHub Release it reads
is already in place. A manual withdrawal removes one package version's
entries and re-signs; machines that installed a withdrawn version keep
it, and `apt` offers the highest remaining version. Publishing,
rebuilding, withdrawing and re-signing share one concurrency group with
`queue: max`, so no two of them read and deploy the site at the same
time, and none waiting behind another is cancelled.

## Alternatives

- **A project's release sends `repository_dispatch` to this
  repository.** A release would reach APT at once, but sending the event
  needs a token with Contents write on this repository, the permission
  that also pushes commits and edits files here. Held by every project,
  one leaked token could add a key under `keyring/`, which the next
  re-signing would ship to every user as trusted.
- **Publishing without approval.** A release would reach APT within an
  hour with no one watching, but so would a release, or its
  `SHA256SUMS` with its assets, replaced by someone who took over a
  project's repository; the registry checks assets against that file,
  not against who made it.
- **Approval for every run, the re-signing included.** Every week would
  need the maintainer, and a maintainer away for 90 days would leave
  users with an expired repository.
- **The keys in two environments, one requiring approval for publishing
  and one without for re-signing.** The signing key would be stored
  twice, and the approval would rest on whether GitHub lets a job
  waiting for it hold the concurrency group, which its documentation
  does not say.
- **A concurrency group without `queue: max`.** GitHub keeps one pending
  run per group and cancels the older one, so a release waiting behind
  the re-signing could be dropped.

## Consequences

- `apt update` and `apt upgrade` deliver new versions of every listed
  project to Debian and Ubuntu machines.
- A project's release depends on this repository's workflow and keys to
  reach APT users. If either is unavailable, the GitHub Release still
  ships, and the repository lags until the run is repeated.
- Every release waits for the maintainer.

## Verification

On `https://pkg.shortarrow.jp`, with throwaway files deployed from
outside the repository with wrangler 4.151.2:

- A version whose assets held `apt/InRelease` and `apt/probe.txt` served
  both with status 200 and their exact contents, the file without an
  extension included.
- The next version, which left `apt/probe.txt` out, answered 404 for it
  within 10 seconds of the deploy and kept serving `apt/InRelease`.
