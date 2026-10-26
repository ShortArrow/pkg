# 0001. A package registry for ShortArrow's projects

- Status: Accepted

## Context

ShortArrow publishes several command-line tools: ivi-cli (.NET), runex
(Rust) and gitreant (Rust, with its frontend embedded in one binary).
Each builds its own release assets on GitHub Releases. A Linux user who
installs one of them from an archive keeps whatever version was
unpacked, because the system's package manager does not know about it.

APT reads a repository, not a list of files. `apt update` fetches
`dists/<suite>/InRelease`, checks its signature against the key the
source line names, and follows the hashes in it to the `Packages`
index. Each entry in `Packages` names its `.deb` by a `Filename:` path
relative to the repository's base URL, and APT checks the file's size
and SHA-256 against that entry after downloading it. Alpine's `apk`
works the same way with a signed `APKINDEX.tar.gz`.

Packages are large. The self-contained linux-x64 archive of ivi-cli
v0.4.0 is 47.2 MB and the linux-arm64 one 45.0 MB, so ivi-cli alone adds
about 90 MB of packages per release.

One host and one set of keys for every project means one source line and
one keyring on a user's machine, however many of the tools it installs.

## Decision

This repository is the registry behind `https://pkg.shortarrow.jp`: the
signed indexes, the repository keys, the Cloudflare Worker that serves
them, and the workflows that update them.

It builds no package of a project. Each project builds its packages,
tests that they install, and attaches them to its own GitHub Release;
the registry indexes those assets where they are. What a package
contains, its name and its `Depends` are the project's to decide and are
recorded in the project.

The `shortarrow.jp` zone is on Cloudflare.

- The metadata, `dists/`, the keyring file and the keyring package are
  the static assets of a Cloudflare Worker that has no script. They are
  small and change on every release and every re-signing. Requests for
  static assets are free and unlimited, and a request no asset or rule
  matches gets a 404. The root of the host serves the page of
  [ADR 0003](0003-repository-keys.md) that names the keys.
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
- The Worker's `wrangler` configuration lives in this repository, with
  its assets directory and `pkg.shortarrow.jp` as its Custom Domain, so
  every deploy, the first and a rebuild included, attaches the hostname;
  Cloudflare creates the DNS record and the certificate for it. The
  hostname must not already have a CNAME record, and every path on it
  goes to this Worker. Attaching a Custom Domain needs only the Workers
  Scripts Write permission the deploy token already has.

A package therefore has one copy, in the release that built it, and
every version stays installable without a size limit. The user's source
line names only `pkg.shortarrow.jp`, so the files behind it can move
later without asking anyone to edit it.

Trust rests on the signature alone. A file changed behind the redirect
fails APT's size or hash check against the signed `Packages`, and the
redirect target needs no trust of its own.

The layout is the standard APT one, with one suite:

```
apt/
├── shortarrow-archive-keyring.gpg
├── keyring/shortarrow-archive-keyring_<version>_all.deb
├── dists/stable/
│   ├── InRelease
│   ├── Release
│   └── main/binary-{amd64,arm64}/Packages(.gz)
└── pool/<repo>/<tag>/<file>.deb   (redirected)
```

An APK repository, when one is added, sits beside `apt/` under the same
Worker with its own redirect rule. Whether `apk` follows the redirect to
GitHub's asset host, and how its keys reach `/etc/apk/keys/` and rotate,
are left to the record that adds it (ivi-cli #247).

## Alternatives

- **GitHub Releases as the repository itself.** Release assets sit in
  one flat directory per tag with no index, and a `Filename:` cannot name
  another host or another tag's directory. The `releases/latest/download/`
  URL resolves to the release marked Latest, so a repository based there
  could only ever offer that one version.
- **Copying the packages to the site.** GitHub Pages limits a site to
  1 GB, which about eleven ivi-cli releases would exceed, and Cloudflare
  Workers static assets refuse any single file over 25 MiB.
- **Cloudflare Pages.** It would serve the same files with the same
  `_redirects`. Cloudflare's documentation describes Workers as having
  the broader feature set and offers a migration from Pages to Workers,
  not the reverse.
- **A flat repository** (`Packages` and `Release` beside the files,
  source line ending in `./`). It would serve one package too, but the
  tools that generate repositories produce the standard layout at no
  extra cost, and only the standard layout leaves room to add a
  component or an architecture without changing the line every user has
  already written.
- **The maintainer attaches the Custom Domain by hand in the
  dashboard.** A rebuild into a new account or Worker would then depend
  on someone remembering the step.

## Consequences

- Every install depends on both Cloudflare and GitHub being reachable.
- A project's package reaches APT only through its GitHub Release, and
  stays installable for as long as that release keeps the asset.

## Verification

Measured in `debian:bookworm` (apt 2.6.1) and `ubuntu:24.04` (apt 2.8.3)
containers, against a signed repository in the standard layout served
over HTTPS, unless a fact names other conditions.

- `apt update` and `apt install` succeed through two chained 302
  redirects from `pool/`, the shape of a GitHub asset URL.
- With `pool/` redirected to a real release asset, ivi-cli v0.4.0's,
  `apt-get download` follows GitHub's redirects and saves a file whose
  SHA-256 matches the asset.
- A package changed behind the redirect is refused: by size when its
  length changes, by hash when one byte is flipped at the same length.
  A `Packages.gz` changed without re-signing is refused by `apt update`.
- With wrangler 4.151.2 and the assets-only Worker this repository
  configures, `_redirects` is read only at the root of the assets
  directory. Under `wrangler dev`, a request for
  `/apt/pool/ivi-cli/v0.4.0/SHA256SUMS` that does not follow redirects
  answers 404 with `_redirects` under `public/apt/` or with none, and 302
  to
  `https://github.com/ShortArrow/ivi-cli/releases/download/v0.4.0/SHA256SUMS`
  with it at the root. `https://pkg.shortarrow.jp` answers the same 302
  over HTTPS, and following it saves a file whose SHA-256 matches the
  release asset.
