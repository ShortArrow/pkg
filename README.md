# pkg

The package registry behind `https://pkg.shortarrow.jp`, for ShortArrow's
command-line tools:

| Tool | APT package |
| --- | --- |
| [ivi-cli](https://github.com/ShortArrow/ivi-cli) | `ivicli` |
| [runex](https://github.com/ShortArrow/runex) | `runex` |
| [gitreant](https://github.com/ShortArrow/gitreant) | `gitreant` |

Each project builds its packages and attaches them to its own GitHub
Release. This repository holds the signed indexes that point at those
assets, the repository keys, and the Cloudflare Worker that serves them.

## Installing

On Debian or Ubuntu, amd64 or arm64:

```sh
sudo curl -fsSL https://pkg.shortarrow.jp/apt/shortarrow-archive-keyring.gpg \
  -o /usr/share/keyrings/shortarrow-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/shortarrow-archive-keyring.gpg] https://pkg.shortarrow.jp/apt stable main" \
  | sudo tee /etc/apt/sources.list.d/shortarrow.list
sudo apt update
sudo apt install shortarrow-archive-keyring runex
```

Replace `runex` with any package in the table. Installing
`shortarrow-archive-keyring` by name keeps the keyring, and the keys it
holds up to date, after the tool is removed.

The design is in [ADR 0001](docs/adr/0001-package-registry.md), and how
to run the registry in [docs/operations.md](docs/operations.md).
