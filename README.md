# pkg

The package registry behind `https://pkg.shortarrow.jp`, for ShortArrow's
command-line tools: [ivi-cli](https://github.com/ShortArrow/ivi-cli),
[runex](https://github.com/ShortArrow/runex) and
[gitreant](https://github.com/ShortArrow/gitreant).

Each project builds its packages and attaches them to its own GitHub
Release. This repository holds the signed indexes that point at those
assets, the repository keys, and the Cloudflare Worker that serves them.

Nothing is published yet. The design is in
[ADR 0001](docs/adr/0001-package-registry.md).
