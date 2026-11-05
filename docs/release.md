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

The result is a signed, notarized DMG in `build/release`.

Or release from GitHub: merge to `main`, then push a tag such as `v0.2.0`. The Release workflow tests, signs, notarizes and publishes the DMG. It needs the secrets listed in [CONTRIBUTING.md](../CONTRIBUTING.md).

To check the steps without a certificate, run `SKIP_SIGNING=1 scripts/release.sh`.

## Checks before publishing

- Install from the DMG on a Mac that has never run QuietDeck.
- Confirm Gatekeeper opens it without a warning.
- Confirm the Bluetooth and notification prompts appear once and not again after a restart.

## Updates

Automatic updates aren't included yet. They need a hosted update feed, and checking for updates sends the user's IP address to that server, so they must be off until the user turns them on. See [privacy.md](privacy.md).
