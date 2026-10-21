# Operating the registry

The workflows in `.github/workflows/` carry out ADR 0001 §6 and §7.
Every run that changes the site deploys it to the `pkg` Worker with
`wrangler deploy`, after building it with `scripts/update-registry.ps1`.

| Workflow | Starts | Waits for approval |
| --- | --- | --- |
| `poll` | Every hour, or by hand | No; it only starts `publish` runs |
| `publish` | By `poll`, or by hand | Yes, in the `approve` environment |
| `resign` | Every Monday at 03:17 UTC, or by hand | No |

## Approving a publishing run

A `publish` run waits in the `approve` environment until the maintainer
reviews it in the run's page on GitHub. Approve it once the release it
names is one the project's maintainer made. A rejected or forgotten run
is not started again by `poll`; start it by hand when it should go out.

## Running `publish` by hand

Run the `publish` workflow from the Actions tab with one of these
operations:

- `publish`, with a `repository` from `projects.json` and a release
  `tag`: indexes that release's packages, replacing any earlier entries
  for the same versions.
- `rebuild`: builds the whole repository from every stable release of
  every project, trusting nothing on the live site. It creates the
  repository the first time, and recovers it after a compromise or a
  failed verification.
- `withdraw`, with a `package` and a `version` such as `0.1.21-1`:
  removes that version for every architecture.

## Adding a project

Add its repository, package name and the command that prints its
version to `projects.json`. Its next stable release with `.deb` assets
and a `SHA256SUMS` is picked up by `poll`.

## When re-signing fails

A failed `resign` run opens an issue titled "Re-signing the repository
failed", and the next successful run closes it. Clients refuse the
repository 90 days after the last successful re-signing.

GitHub disables a scheduled workflow after 60 days without activity in
the repository. After such a pause, enable `resign` and `poll` again in
the Actions tab and run `resign` by hand.
