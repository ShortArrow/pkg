# 0001. A package registry for ShortArrow's projects

- Status: Draft
- Date: 2026-10-20

## Context

ShortArrow publishes several command-line tools: ivi-cli (.NET), runex
(Rust) and gitreant (TypeScript). Each builds its own release assets on
GitHub Releases. A Linux user who installs one of them from an archive
keeps whatever version was unpacked, because the system's package
manager does not know about it.

APT reads a repository, not a list of files. `apt update` fetches
`dists/<suite>/InRelease`, checks its signature against the key the
source line names, and follows the hashes in it to the `Packages`
index. Each entry in `Packages` names its `.deb` by a `Filename:` path
relative to the repository's base URL, and APT checks the file's size
and SHA-256 against that entry after downloading it. Alpine's `apk`
works the same way with a signed `APKINDEX.tar.gz`.

That rules out GitHub Releases as the repository itself. Release assets
sit in one flat directory per tag with no index, and a `Filename:` cannot
name another host or another tag's directory. The `releases/latest/download/`
URL resolves to the release marked Latest, so a repository based there
could only ever offer that one version.

Size also matters. The self-contained linux-x64 archive of ivi-cli v0.4.0
is 47.2 MB and the linux-arm64 one 45.0 MB, so ivi-cli alone adds about
90 MB of packages per release. GitHub Pages limits a site to 1 GB, which
about eleven ivi-cli releases would exceed, and Cloudflare Workers static
assets refuse any single file over 25 MiB.

One host and one set of keys for every project means one source line and
one keyring on a user's machine, however many of the tools it installs.

## Decision

### 1. What this repository holds, and what it does not

This repository is the registry behind `https://pkg.shortarrow.jp`: the
signed indexes, the repository keys, the Cloudflare Worker that serves
them, and the workflows that update them.

It builds no package of a project. Each project builds its packages,
tests that they install, and attaches them to its own GitHub Release;
the registry indexes those assets where they are. What a package
contains, its name and its `Depends` are the project's to decide and are
recorded in the project.

### 2. Where each part lives

The `shortarrow.jp` zone is on Cloudflare.

- The metadata, `dists/`, the keyring file and the keyring package are
  the static assets of a Cloudflare Worker that has no script. They are
  small and change on every release and every re-signing (§5). Requests
  for static assets are free and unlimited, and a request no asset or
  rule matches gets a 404.
- The packages are GitHub Release assets of the project that built them
  and nothing else. The repository's `pool/<repo>/<tag>/<file>` path
  answers with a 302 to
  `https://github.com/ShortArrow/<repo>/releases/download/<tag>/<file>`,
  set by one rule in the `_redirects` file at the root of the uploaded
  assets, which the Custom Domain serves at the host's root:

  ```
  /apt/pool/:repo/:tag/:file https://github.com/ShortArrow/:repo/releases/download/:tag/:file 302
  ```

  A redirect applies whether or not an asset matches, so `pool/` never
  holds a file of its own.

Cloudflare Pages would serve the same files with the same `_redirects`.
Workers static assets were chosen because Cloudflare's documentation
describes Workers as having the broader feature set and offers a
migration from Pages to Workers, not the reverse.

A package therefore has one copy, in the release that built it, and
every version stays installable without a size limit. The user's source
line names only `pkg.shortarrow.jp`, so the files behind it can move
later without asking anyone to edit it.

Trust rests on the signature alone. A file changed behind the redirect
fails APT's size or hash check against the signed `Packages`, and the
redirect target needs no trust of its own.

### 3. Layout

The standard APT layout, with one suite:

```
apt/
├── <keyring>.gpg
├── keyring/<keyring>_<date>_all.deb
├── dists/stable/
│   ├── InRelease
│   ├── Release
│   └── main/binary-{amd64,arm64}/Packages(.gz)
└── pool/<repo>/<tag>/<file>.deb   (redirected)
```

A flat repository (`Packages` and `Release` beside the files, source
line ending in `./`) would serve one package too. The standard layout
was chosen because the tools that generate repositories produce it at no
extra cost, and because it leaves room to add a component or an
architecture without changing the line every user has already written.
An APK repository, when one is added, sits beside `apt/` under the same
Worker with its own redirect rule.

### 4. What goes into the index

- Only stable releases. A version containing `-` would sort after the
  final release in Debian's ordering (`0.4.0-beta.1` > `0.4.0`), so the
  publishing job refuses one rather than relying on the release channel
  alone. A maintenance release on an older line does enter: APT picks
  the highest version.
- The index is keyed by package name and version. Re-running a release,
  or re-creating its tag, rewrites that version's entries instead of
  leaving hashes of assets that no longer exist.
- Every package asset is checked against the `SHA256SUMS` asset of the
  release it came from before it is indexed.

### 5. Signing keys and freshness

- The repository has its own Ed25519 keys, not the maintainer's personal
  key, so the key that signs every update can be replaced without
  touching anything else. There are two: a signing key, which expires
  after three years, and a standby key, kept offline and never used
  until it is needed.
- A keyring package, `Architecture: all` and built from the public keys
  under `keyring/` in this repository, installs the keyring file under
  `/usr/share/keyrings/` with the public half of every current key,
  standby included, the way Debian's own `debian-archive-keyring` does.
  It is versioned by the date it was built with a counter
  (`2026.10.20.1`, then `2026.10.20.2` for a second change that day),
  independently of any project, and rebuilt only when its keys change.
  It is a package of its own so that removing a project's package leaves
  the keyring, and with it the source, working. Being a few kilobytes,
  it is served from the site itself under `keyring/`, not through the
  redirect, and appears in both architectures' `Packages`.
- The install guide of each project downloads the same keyring to the
  same path as its first step, and installs the keyring package by name
  along with the project's package, so APT marks the keyring as
  installed by hand. Pulled in only as a dependency, it would be marked
  automatic, and `apt autoremove` after removing the project's package
  would delete it. Installing the keyring package takes the file over,
  and every upgrade replaces it. Keys change on users' machines through
  `apt upgrade`, never by hand after the first step.
- Rotation: a keyring that adds the next signing key ships at least a
  year before the current one expires, and `InRelease` is signed by both
  until it does. A machine that never upgrades in that year stops
  verifying when the old key expires.
- Compromise: the standby key becomes the signing key at once, its
  private half moving into the environment below, and the next keyring
  drops the compromised key and adds a newly generated standby. The
  published index may have been altered with the compromised key, so the
  repository is rebuilt from the GitHub Releases (§6) rather than
  updated. Clients already trust the standby key, so the replacement
  reaches them through an ordinary upgrade. Until a machine takes that
  upgrade, the compromised key still verifies there, and a package the
  attacker signed in that window, with a keyring of their choosing and
  maintainer scripts that run as root, cannot be undone by the standby
  key. A machine that holds or pins the keyring package never receives
  a new key.
- The keys and a Cloudflare API token limited to editing Workers
  scripts on the one account, with that account's ID, are secrets of a
  GitHub Actions environment, `publish`, in this repository. Only the
  workflows of this repository reach them, so pushing a tag or changing
  a workflow in a project's repository does not.
- `Release` carries `Date` and `Valid-Until`, 90 days after signing. A
  scheduled workflow re-signs the metadata weekly. Without an expiry, an
  attacker or a stale mirror could keep serving an old, validly signed
  index and hide a fix; with it, a client refuses metadata that has not
  been re-signed for 90 days. If re-signing stops, users see an expired
  repository rather than a silently stale one.

### 6. Publishing

A project's stable release triggers one publishing run for that project
and version:

1. Refuse a version containing `-`.
2. Fetch the published site: `InRelease`, `Packages`, and every file the
   site serves itself, the keyring and its packages. Verify `InRelease`
   against the keys under `keyring/`, and every fetched file against its
   hash in `Packages`. Any failure stops the job; it never signs what it
   could not verify.
3. Download the release's package assets and its `SHA256SUMS`, check
   each package against it, and replace that package's entries for this
   version with entries computed from those files, for every
   architecture.
4. If the keys under `keyring/` differ from those in the newest published
   keyring package, in either direction, build a new keyring package and
   add it.
5. Write `Release` with `Date` and `Valid-Until`, sign `InRelease`, and
   deploy the fetched site with these changes as one new version of the
   Worker, with `wrangler deploy`. Each version serves the files its
   upload manifest lists and no others, so a file the job did not carry
   forward would disappear.

A rebuild replaces steps 2 and 3: the job builds the index from the
package assets of every stable release of every project the registry
lists, each checked against its release's `SHA256SUMS`, and the keyring
package from `keyring/`, trusting nothing on the live site. It creates
the repository the first time, and recovers it after a compromise or a
failed verification.

A failed run is retried by running it again; the GitHub Release it
reads is already in place. The weekly re-signing also runs step 4, so a
keyring change merged to `main` ships within a week, or at once when the
workflow is run by hand. A manual withdrawal removes one package
version's entries and re-signs; machines that installed a withdrawn
version keep it, and `apt` offers the highest remaining version. All of
these share one concurrency group with `queue: max`, so no two of them
read and deploy the site at the same time, and none waiting behind
another is cancelled. Without `queue: max`, GitHub keeps one pending run
per group and cancels the older one.

The maintainer creates the Worker and attaches `pkg.shortarrow.jp` to it
as a Custom Domain once, by hand, before the first publish; Cloudflare
creates the DNS record and the certificate for it. The hostname must not
already have a CNAME record, and every path on it goes to this Worker.
The Worker's `wrangler` configuration, with its assets directory, lives
in this repository.

### 7. Checks

- **After publishing.** Once a run deploys, a job on each architecture
  follows the project's install guide against
  `https://pkg.shortarrow.jp/apt` in fresh `debian:bookworm` and
  `ubuntu:24.04` containers. It checks that `apt-cache madison <package>`
  lists the version just published, installs that version by name and
  runs the command the project gives for checking it. It names the
  version because a maintenance release on an older line is not the
  highest one. This is the only check that goes through Cloudflare, the
  `_redirects` rule and GitHub's asset URLs together. A failure of
  Cloudflare, the redirect or the site is fixed and the run repeated. A
  defect in the package itself cannot be fixed by a repeat: the version
  is withdrawn and the fix ships with the project's next release.
- **Re-signing.** The weekly re-signing ends by fetching the live
  `InRelease` and checking that its `Date` and `Valid-Until` are the
  ones just signed, then runs `apt update` against it in a container. A
  deployment that reports success while the old index is still served
  fails here; `apt update` alone would accept that index until it
  expires. A failure of any step opens an issue, or comments on the one
  already open, and the next successful run closes it. With weekly runs
  and a 90-day `Valid-Until`, about twelve runs can fail before users
  see an expired repository.
  - A run that never starts opens no issue. GitHub disables a scheduled
    workflow in a public repository after 60 days without activity in
    the repository, so a quiet period longer than that is the one way
    re-signing stops silently. The maintainer re-enables the workflow
    and runs it by hand after such a pause.

The check that a package installs at all, before anything is
published, belongs to the project that builds it, and runs in its own
pull requests and release workflow.

## Open questions

- The keyring package's name and file name, and with them the source
  line each install guide gives.
- How a project's release starts a publishing run here, and the
  credential that lets it.
- The APK repository for Alpine (ivi-cli #247): whether `apk` follows a
  302 from this host to GitHub's asset host, and how key rotation reaches
  `/etc/apk/keys/`.

## Consequences

- `apt update` and `apt upgrade` deliver new versions, and new keys, of
  every listed project to Debian and Ubuntu machines.
- A project's release depends on this repository's workflow and keys to
  reach APT users. If either is unavailable, the GitHub Release still
  ships, and the repository lags until the run is repeated.
- The repository must be re-signed at least every 90 days, by the
  scheduled workflow, and a new signing key must ship a year before the
  current one expires.
- The standby key must be stored offline and separately from the
  signing key, or it protects nothing.
- Every install depends on both Cloudflare and GitHub being reachable.

## Verification

On 2026-09-29, for ivi-cli's ADR 0052 before this registry was split out,
in `debian:bookworm` (apt 2.6.1) and `ubuntu:24.04` (apt 2.8.3)
containers, against a signed repository in the standard layout served
over HTTPS by a local server:

- `apt update` and `apt install ivicli` succeeded through two chained
  302 redirects from `pool/`, the shape of a GitHub asset URL.
- With `pool/` redirected to the real ivi-cli v0.4.0 release asset,
  `apt-get download` followed GitHub's redirects and saved a file whose
  SHA-256 matched the asset.
- A package changed behind the redirect was refused, by size when the
  length changed and by hash when one byte was flipped at the same
  length. A `Packages.gz` changed without re-signing was refused by
  `apt update`.

`dpkg --compare-versions` in `debian:bookworm` gives `0.4.0-beta.1` >
`0.4.0`, `0.4.0~beta.1` < `0.4.0` and `0.3.3` < `0.4.0`.

In `debian:bookworm`, a keyring placed under `/usr/share/keyrings/` by
hand was taken over by a package that ships the same path: `dpkg -i`
replaced it without an error, `dpkg -S` then named the package as its
owner, and the next version of the package replaced it again. An
`InRelease` signed by two Ed25519 keys verified with a keyring holding
only one of them, in both containers, and one signed by a key that had
expired in the client's keyring failed with `EXPKEYSIG`.

Not yet verified: that the Workers static assets `_redirects` rule with
`:repo`, `:tag` and `:file` placeholders returns the 302 to an external
host as intended, that a new version stops serving a file its manifest
leaves out, that files without an extension such as `InRelease` and
`Packages` are served at their exact paths, and the repository over
Cloudflare's own certificate. All four are checked on a test site before
the first publish.
