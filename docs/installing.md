# Installing step by step

The [README](../README.md#installing) installs with a few commands. This
page does the same by hand, checking the keys before APT trusts them, and
says what each step leaves on the system and how to remove it. It works on
Debian and Ubuntu, amd64 and arm64.

## 1. Download the keyring

```sh
curl -fsSL https://pkg.shortarrow.jp/apt/shortarrow-archive-keyring.gpg -o shortarrow-archive-keyring.gpg
```

## 2. Check its keys

```sh
gpg --show-keys shortarrow-archive-keyring.gpg
```

It prints two keys, a signing key and a standby key. Their fingerprints
must be the two in [keyring/fingerprints](../keyring/fingerprints). That
file is served by GitHub, not by `pkg.shortarrow.jp`, so a forged keyring
would have to be forged on both. Stop here if they differ.

## 3. Install the keyring

```sh
sudo install -m 644 shortarrow-archive-keyring.gpg /usr/share/keyrings/
```

APT reads it as an unprivileged user, so it has to be readable by all.

## 4. Add the source

Create `/etc/apt/sources.list.d/shortarrow.list` with an editor, for
example `sudo nano /etc/apt/sources.list.d/shortarrow.list`, holding this
one line:

```text
deb [signed-by=/usr/share/keyrings/shortarrow-archive-keyring.gpg] https://pkg.shortarrow.jp/apt stable main
```

Or, in the deb822 format that Ubuntu 24.04 uses for its own sources,
create `/etc/apt/sources.list.d/shortarrow.sources` holding:

```text
Types: deb
URIs: https://pkg.shortarrow.jp/apt
Suites: stable
Components: main
Signed-By: /usr/share/keyrings/shortarrow-archive-keyring.gpg
```

Create one of the two files, not both, or APT lists the repository twice.

`signed-by` makes APT accept this repository only when it is signed by a
key in that keyring, and that keyring for no other repository.

## 5. Install a package

```sh
sudo apt update
sudo apt install shortarrow-archive-keyring runex
```

Replace `runex` with any package in the [README](../README.md)'s table.
`shortarrow-archive-keyring` takes over the file from step 3 and replaces
it when the keys change, for example when the standby key takes over.

## Removing

```sh
sudo apt remove shortarrow-archive-keyring runex
sudo rm -f /etc/apt/sources.list.d/shortarrow.list /etc/apt/sources.list.d/shortarrow.sources
sudo rm -f /usr/share/keyrings/shortarrow-archive-keyring.gpg
sudo apt update
```

The `rm -f` of the keyring is needed only when the keyring package was
never installed; removing the package removes the file.
