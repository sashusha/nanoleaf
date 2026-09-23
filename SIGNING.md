# Build and self-sign

A persistent self-signed certificate needs no Apple Developer membership.
Use the same certificate for updates and distribute the whole app: extracting
its binary loses the signed bundle. Self-signing does not provide Apple
notarization or eliminate Gatekeeper warnings.

## Create an identity once

1. Open **Keychain Access** through Spotlight. Choose **Keychain Access →
   Certificate Assistant → Create a Certificate**.
2. Name it `Nanoleaf Local Signing`. Choose **Self Signed Root** for Identity
   Type and **Code Signing** for Certificate Type. Select **Let me override defaults**.
3. Set a validity period suitable for ongoing builds, such as 3650 days. Use an
   RSA key of at least 2048 bits, retain the code-signing defaults, and save to
   the **login** keychain.
4. Open the certificate in Keychain Access, expand **Trust**, and set only
   **Code Signing** to **Always Trust**. Close and authenticate if requested.
5. Confirm it appears as a valid identity:

```sh
security find-identity -v -p codesigning
```

Use its name or SHA-1 identifier below. If it is missing, check that the
certificate expands to show its private key, is unexpired, and is trusted for
code signing. [Apple's certificate instructions](https://support.apple.com/guide/keychain-access/kyca8916/mac).

Keep this identity for future builds. A replacement certificate—even with the
same name—changes identity. Back up the certificate **with its private key** as
a password-protected `.p12` using Keychain Access → File → Export Items; keep it
private and outside the repository. Published apps contain the public certificate
and its name/validity information, never the private key.

## Build and install

From a [source checkout](README.md#build-from-source), with Python 3 available:

```sh
python3 Scripts/build-signed-release.py \
  --identity 'Nanoleaf Local Signing' \
  --self-signed --version 0.2.1 --output /tmp/nanoleaf-local.zip
```

Approve `codesign` access to this Keychain identity if prompted. The script runs
tests, builds, removes debug paths, signs with the required location entitlement,
verifies the signature, and creates a ZIP plus SHA-256 checksum. The output path
must not already exist.

Extract the ZIP and run `./install.sh` from the extracted directory. It installs
the intact app, enables login startup, and links `~/.local/bin/nanoleaf` to it.
Follow the [permission setup](README.md#install-or-update).

For updates, reuse the identity, choose a new version/output path, and run the
new archive's installer. Switching from an ad-hoc or someone else's build needs
new permissions. Same-certificate updates retained Accessibility and Location
on the development Mac; other Macs remain unverified. Installing these builds
elsewhere does not require sharing your private key.

## Optional Apple notarization

This separate route requires a **Developer ID Application** identity in Keychain
and a `notarytool` Keychain credential profile. Use it instead of `--self-signed`:

```sh
python3 Scripts/build-signed-release.py \
  --identity 'Developer ID Application: YOUR NAME (TEAM_ID)' \
  --version 0.2.1 --notary-profile nanoleaf-notary \
  --output /tmp/nanoleaf-notarized.zip
```

The script submits to Apple, staples the ticket, and checks Gatekeeper acceptance.
See [Apple's notarization setup](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
This route has not been tested for this project.
