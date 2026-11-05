# Releasing QuietDeck

## One-time setup

One Developer ID certificate covers all apps of a team, so an existing one can be reused. Creating one needs the Account Holder role. If the certificate exists but shows as "Not in Keychain", export it as a `.p12` from the Mac that has its private key, and import it into the login keychain.

1. **Certificate.** In Xcode, open Settings > Accounts, select your team, choose Manage Certificates, and add a Developer ID Application certificate.
2. **Team ID.** It's listed under Membership at https://developer.apple.com/account.
3. **Notary credentials.** Create an app-specific password at https://account.apple.com, then store it in the Keychain. The tool asks for the password itself:

   ```sh
   xcrun notarytool store-credentials quietdeck-notary --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
   ```

## Making a release

1. Set `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the Xcode project.
2. Run the tests with `scripts/test.sh`.
3. Build:

   ```sh
   TEAM_ID=YOUR_TEAM_ID scripts/release.sh
   ```

The result is a signed, notarized DMG in `build/release`. To add the update feed, run `SPARKLE_ED_PRIVATE_KEY=... scripts/make-appcast.sh`.

Or release from GitHub: merge to `main`, then push a tag such as `v0.2.0`. The Release workflow tests, signs, notarizes and publishes the DMG with its update feed. It needs the secrets listed in [CONTRIBUTING.md](../CONTRIBUTING.md).

To check the steps without a certificate, run `SKIP_SIGNING=1 scripts/release.sh`.

## Checks before publishing

- Install from the DMG on a Mac that has never run QuietDeck.
- Confirm Gatekeeper opens it without a warning.
- Confirm the Bluetooth and notification prompts appear once and not again after a restart.
- Update from the previous version with Check for Updates, and confirm the app restarts and keeps its Bluetooth permission.

## Updates

QuietDeck updates itself with [Sparkle](https://sparkle-project.org). Each release carries an `appcast.xml` next to the DMG, and the app reads the one from the latest release. Sparkle only installs a DMG whose signature matches the public key in the app.

Automatic checks stay off until the user turns them on, see [privacy.md](privacy.md).

`CURRENT_PROJECT_VERSION` must grow with every release, because Sparkle compares it to decide what is newer. A tag must match the app version, such as `v0.2.0` for 0.2.0.

### Update key

Create the key once, after a build has downloaded Sparkle. It lands in your login keychain, and the tool prints the public key:

```sh
build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
```

Put the public key into `SPARKLE_PUBLIC_KEY` in the Xcode project. Then store the private key as a repository secret, and delete the export:

```sh
build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle-private-key
gh secret set SPARKLE_ED_PRIVATE_KEY < sparkle-private-key
rm sparkle-private-key
```

Back up the keychain item. **If the private key is lost, installed copies can't update any more,** and users have to download the next version by hand.

### Dry run

The Release workflow can also be started by hand from `main`. It does everything except publish:

```sh
gh workflow run Release --ref main
```
