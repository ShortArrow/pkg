# 0002. What enters the index

- Status: Accepted

## Context

APT installs the highest version the index offers, by Debian's version
ordering. Each project tags its releases `v<version>`, marks some as
pre-releases, and attaches a `SHA256SUMS` asset beside its packages.

## Decision

- Only stable releases enter. A release that GitHub marks as a
  pre-release, or whose tag carries a `-` after its version
  (`v0.5.0-beta.1`), is refused. The check is on the tag; a package's own
  `Version` carries the Debian revision (`0.5.0-1`) and is not refused
  for it. A maintenance release on an older line does enter: APT picks
  the highest version.
- The index is keyed by package name and version. Re-running a release,
  or re-creating its tag, rewrites that version's entries instead of
  leaving hashes of assets that no longer exist.
- Every package asset is checked against the `SHA256SUMS` asset of the
  release it came from before it is indexed. A release with no `.deb`
  asset, such as one made before its project built packages, is skipped
  and never retried; one with `.deb` assets but no `SHA256SUMS` fails.

## Alternatives

- **Relying on the pre-release flag alone.** A version containing `-`
  sorts after the final release in Debian's ordering
  (`0.4.0-beta.1` > `0.4.0`), so a beta published by mistake without the
  flag would stay the highest version after the final release ships.

## Verification

`dpkg --compare-versions` in `debian:bookworm` gives `0.4.0-beta.1` >
`0.4.0`, `0.4.0~beta.1` < `0.4.0` and `0.3.3` < `0.4.0`.
