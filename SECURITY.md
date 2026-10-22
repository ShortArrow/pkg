# Security policy

Report a vulnerability privately through
[Report a vulnerability](https://github.com/ShortArrow/pkg/security/advisories/new)
on this repository's Security tab, not in a public issue.

This repository covers how `https://pkg.shortarrow.jp` is built and served:

- the repository keys under [keyring/](keyring/) and the keyring package
- the checks on release assets, signatures and hashes before an index is signed
- the Cloudflare Worker and its redirects
- the GitHub Actions workflows that publish, re-sign and deploy

A vulnerability in a tool itself goes to that tool's own repository:
[ivi-cli](https://github.com/ShortArrow/ivi-cli),
[runex](https://github.com/ShortArrow/runex) or
[gitreant](https://github.com/ShortArrow/gitreant).
