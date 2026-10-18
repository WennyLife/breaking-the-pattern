# Release BTP and its in-app feed

1. Build with `bash scripts/build.sh --build-only`; run the packaging/runtime regressions and observe the UI in Portuguese and English. Test games separately in isolated apps/prefixes. Never infer playability from a successful package.
2. Increment both CFBundleShortVersionString and CFBundleVersion in src/Info.plist. Sparkle compares the build number.
3. Run `python3 -I scripts/publish-release.py --app 'build/Breaking the Pattern.app' --project .` only after verification. It creates current ZIP/DMG installers, verifies them, installs BTP, and backs up the central archive.
4. Copy the verified ZIP to a public filename such as `Breaking-the-Pattern-0.2.0.zip` in build/release/. Do not rebuild or modify the app after signing the update archive.
5. Generate updates/appcast.xml with scripts/make-appcast.py, passing --app, --archive, and --sign-tool (the pinned Sparkle bin/sign_update). This verifies the local app and signs/verifies the exact archive.
6. Commit only source, documentation, and the feed. Create the matching vVERSION GitHub release and upload the exact signed ZIP plus the current DMG and checksums. Verify the public download against the feed hash/signature and open the production update checker.

The update-signing key is stored in this Mac's login Keychain under Sparkle account `org.lendaii.btp.updates`. Its **private key must never be printed, committed, attached to a release, or placed in Obsidian**. The public key is in src/Info.plist. Other maintainers need a securely transferred authorized key, or must establish their own feed/key for a separate distribution. Ad hoc code signing is separate from Sparkle's Ed25519 archive signing; Developer ID/notarization is still pending.

The update backs up only BTP.app, verifies that backup, and asks the user to install/relaunch. Games and their data are outside BTP.app. A failure to create a verified backup prevents the offered update from proceeding. Do not publish game files, personal prefixes, saves, private diagnostic logs, or unsupported performance promises.

Local end-to-end update test: an isolated app with build3/version0.1.99 updated from a loopback feed to build4/version0.2.0, archive Ed25519 verified, previous app backup verified, and version0.2.0 observed after relaunch. A synchronized Documents location failed to rename; the local Application Support location succeeded. Production GitHub feed validation is a separate check.
