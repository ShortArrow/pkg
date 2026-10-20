# Repository keys

The repository is signed with its own Ed25519 keys, as ADR 0001 §5
describes: a signing key that expires three years after creation, and a
standby key kept offline until the signing key has to be replaced.

## Generating the keys

Run this on a machine you trust, in PowerShell 7 with GnuPG on `PATH`.
On Windows, start it from PowerShell, not from Git Bash: the `gpg` that
ships with Git cannot read Windows paths.

1. Pick a directory outside this repository for the secret material,
   such as a folder on an encrypted removable drive. The script refuses
   one inside the repository.
2. Run:

   ```powershell
   ./scripts/new-repository-keys.ps1 -SecretDirectory <that directory>
   ```

   It asks for the standby key's passphrase and prints both
   fingerprints. It works in a throwaway GnuPG home and leaves yours
   untouched.
3. Commit the two `keyring/<fingerprint>.asc` files it wrote, in a pull
   request. The keyring package is built from them.
4. Add the content of `signing.secret.asc` as the secret `SIGNING_KEY`
   of the `publish` environment of this repository.
5. Store `standby.secret.asc`, its passphrase and both
   `<fingerprint>.rev` revocation certificates offline, apart from each
   other and from any copy of the signing key.
6. Delete `signing.secret.asc` from the secret directory once the secret
   is saved; GitHub is then its only copy.

## Testing the script

```powershell
Invoke-Pester tests/new-repository-keys.Tests.ps1
```

The tests generate throwaway keys and check that the signing key's
clearsigned output verifies against the public keys alone, that the
standby key needs its passphrase, and that the caller's GnuPG home stays
empty.
