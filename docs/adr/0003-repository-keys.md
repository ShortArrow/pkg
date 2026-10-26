# 0003. Repository keys and the keyring package

- Status: Accepted

## Context

APT trusts a repository through the keyring its source line names with
`signed-by`. Whoever controls that keyring on a machine controls what
APT installs there as root. A user gets the keyring once, over HTTPS,
before APT can verify anything.

## Decision

- The repository has its own Ed25519 keys. There are two: a signing key,
  which expires after three years, and a standby key, kept offline and
  never used until it is needed. The standby key has no expiry until it
  becomes the signing key, so it never lapses unused in storage. The
  public half of each lives under `keyring/` as `<fingerprint>.asc`, a
  name that stays true when the standby key is promoted.
- A keyring package, `shortarrow-archive-keyring`, `Architecture: all`
  and built from the public keys under `keyring/`, installs
  `/usr/share/keyrings/shortarrow-archive-keyring.gpg` with the public
  half of every current key, standby included, the way Debian's own
  `debian-archive-keyring` does, and is named after it. It is versioned
  by the date it was built with a counter (`2026.10.20.1`, then
  `2026.10.20.2` for a second change that day), independently of any
  project, and rebuilt only when its keys change. Being a few kilobytes,
  it is served from the site itself under `keyring/`, not through the
  redirect, and appears in both architectures' `Packages`.
- The install guide of each project downloads the same keyring,
  `https://pkg.shortarrow.jp/apt/shortarrow-archive-keyring.gpg`, to the
  same path as its first step, writes the source line

  ```
  deb [signed-by=/usr/share/keyrings/shortarrow-archive-keyring.gpg] https://pkg.shortarrow.jp/apt stable main
  ```

  to `/etc/apt/sources.list.d/shortarrow.list`, one file for every
  project so that following a second project's guide rewrites it
  unchanged, and installs the keyring package by name along with the
  project's package, so APT marks the keyring as installed by hand.
  Installing the keyring package takes the file over, and every upgrade
  replaces it. Keys change on users' machines through `apt upgrade`,
  never by hand after the first step.
- The fingerprints of the keys are published in two places that a reader
  can compare the downloaded keyring with: `keyring/fingerprints` in this
  repository, served by GitHub, and the page at the root of
  `pkg.shortarrow.jp`, built from `keyring/` on every deploy so it never
  disagrees with the keyring it serves.
- Rotation: a keyring that adds the next signing key ships at least a
  year before the current one expires, and `InRelease` is signed by both
  until it does. A machine that never upgrades in that year stops
  verifying when the old key expires.
- Compromise: the standby key becomes the signing key at once, its
  private half moving into the environment of
  [ADR 0006](0006-workflow-secrets.md), and the next keyring drops the
  compromised key and adds a newly generated standby. The published
  index may have been altered with the compromised key, so the repository
  is rebuilt from the GitHub Releases ([ADR 0005](0005-publishing.md))
  rather than updated. Clients already trust the standby key, so the
  replacement reaches them through an ordinary upgrade. Until a machine
  takes that upgrade, the compromised key still verifies there, and a
  package the attacker signed in that window, with a keyring of their
  choosing and maintainer scripts that run as root, cannot be undone by
  the standby key. A machine that holds or pins the keyring package
  never receives a new key.

## Alternatives

- **Signing with the maintainer's personal key.** Replacing the key that
  signs every update would then touch everything else the personal key
  signs.
- **A single key, replaced when it expires or leaks.** Clients would
  have to fetch a new keyring by hand, over the same channel an attacker
  who took the old key may control. The standby key is already trusted
  when it is needed.
- **The keyring as a dependency of each project's package.** APT would
  mark it automatic, and `apt autoremove` after removing the project's
  package would delete it, leaving the source line without its keyring.
- **The fingerprints only on the page at the root of
  `pkg.shortarrow.jp`.** A certificate trusted for that host, such as
  one issued from a compromised intermediate, would let an attacker serve
  a forged keyring and a page listing its fingerprints together. A copy
  on GitHub has to be forged on a second host.

## Consequences

- `apt upgrade` delivers new keys to every machine that installed the
  keyring package.
- A new signing key must ship a year before the current one expires.
- The standby key must be stored offline and separately from the
  signing key, or it protects nothing.
- `keyring/fingerprints` must change with `keyring/`; a test fails when
  they differ.

## Verification

Measured in `debian:bookworm` (apt 2.6.1) and `ubuntu:24.04` (apt 2.8.3)
containers unless a fact names other conditions.

- In `debian:bookworm`, a keyring placed under `/usr/share/keyrings/` by
  hand is taken over by a package that ships the same path: `dpkg -i`
  replaces it without an error, `dpkg -S` then names the package as its
  owner, and the next version of the package replaces it again.
- An `InRelease` signed by two Ed25519 keys verifies with a keyring
  holding only one of them, and one signed by a key that has expired in
  the client's keyring fails with `EXPKEYSIG`.
