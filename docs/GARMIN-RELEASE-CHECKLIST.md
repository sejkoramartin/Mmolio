# Garmin release preparation

This is the release checklist for `2026.10.11-rc1`.

On 2026-10-11 the owner authorized publishing the prepared release candidate and
opening a draft upstream PR before Apple-platform and physical testing is complete.
The pending tests below remain required before claiming a validated/stable release.
The candidate is explicitly a prerelease; unchecked items are not reported as passed.

## Local build

Review and commit the exact source first, then run:

```sh
export CONNECTIQ_SDK="/absolute/path/to/connect-iq-sdk-9.2.0"
export DEVELOPER_KEY="/absolute/path/to/existing/developer_key.der"
python3 garmin/scripts/package-release.py --output /absolute/path/to/new-output-directory
```

The existing signing identity is required for compatibility with installed private
complications. The script builds all three apps for all three devices, uses an
explicit archive file allow-list, includes installation instructions/license/
disclaimers, records the source revision and PUBLIC-key fingerprint, and verifies
checksums and ZIP contents. It rejects a dirty source tree and an existing output
directory. It does not copy signing keys, debug artifacts or personal settings.
Build logs are for local review and should not be uploaded as release assets.
The installation archives omit source; publish their exact corresponding source
commit so the source links in RELEASE.json work.

## Required before publication

- [ ] Full clean-upstream xDrip build with the real SDK on macOS/Xcode.
- [ ] End-to-end installation using the exact ZIP, on a test iPhone and each watch
      model that will be advertised as physically validated. Document exact versions.
- [ ] Test Bridge/face/field, locked phone, Bluetooth reconnect, switching watches,
      disable, calibration correction and stale/future measurements.
- [ ] Check upgrade from the older Mmolio filenames and matching signing key.
- [ ] Review the test matrix in the xDrip branch; do not downgrade a personal v33 DB.
- [ ] Review English/Czech user instructions on a fresh installation.
- [ ] Set accurate verification status and update the version when source changes;
      rebuild and recheck the actual final archives. Never relabel older binaries.
- [ ] Obtain the owner's explicit approval of the exact commits/assets and PR text.

## Publication order after approval

1. Publish the reviewed Mmolio source branch/commit and installation documents.
2. Verify `/blob/main/docs/GARMIN-INSTALL.md` opens publicly (merge the documentation
   to main or revise the xDrip link before publishing xDrip).
3. Create the versioned tag/release at the exact packaged source commit and upload
   only the three ZIPs, SHA256SUMS and public release manifest. Use a prerelease
   while validation is incomplete. Explain unsupported/unverified models explicitly.
4. Confirm all archive, documentation and corresponding-source URLs work without
   signing in. Verify downloaded ZIP hashes against the locally approved artifacts.
5. Update the xDrip PR's receiver/validation section with actual results, then publish
   its branch and PR only within the owner's approval.

The installer link must work before the xDrip change is exposed to users. An empty
release page, a local source commit or a successful simulator run is not sufficient.
No Connect IQ Store listing is claimed; distribution in this plan uses GitHub Releases
and USB installation. Consider a Store release separately if desired later.
