# Contributing

## Branches

- `staging` takes all new work.
- `main` holds what's ready for release. Nothing is pushed to it directly.

Work reaches `main` like this:

1. Commit to `staging`, or to a feature branch merged into it.
2. Push `staging`. CI runs lint, tests and a build.
3. Open a pull request from `staging` to `main`.
4. Merge when CI is green.

A pre-push hook blocks direct pushes to `main` on your machine. Enable it once per clone:

```sh
git config core.hooksPath .githooks
```

## Protecting main on GitHub

In the repository, open Settings > Rules > Rulesets > New branch ruleset:

- **Name:** Protect main
- **Enforcement status:** Active
- **Target branches:** Include default branch
- **Rules:** Restrict deletions, Block force pushes, Require a pull request before merging, Require status checks to pass with `Lint, test and build`

A status check can only be selected after CI has run once.

## Commits

Use English and [Conventional Commits](https://www.conventionalcommits.org): `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`. Make one focused commit per logical change.

## CI

| Workflow | Runs on | Does |
|---|---|---|
| CI | Pushes to `staging`, pull requests to `main` | Lint, tests and a Debug build |
| Release | Tags like `v0.2.0` on `main` | Tests, signs, notarizes and publishes a DMG |

macOS runners use GitHub's included minutes at a higher rate than Linux runners.

The Release workflow needs these repository secrets:

| Secret | Content |
|---|---|
| `DEVELOPER_ID_P12_BASE64` | The exported certificate, from `base64 -i certificate.p12` |
| `DEVELOPER_ID_P12_PASSWORD` | Its export password |
| `NOTARY_APPLE_ID` | The Apple ID for notarization |
| `NOTARY_PASSWORD` | An app-specific password |
| `TEAM_ID` | The Apple Developer team ID |

## Testing on hardware

Debug builds have launch arguments for hardware checks. They're listed in `App/QuietDeck/TransportDiagnostics.swift`.
