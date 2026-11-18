# Publishing the public source edition

This tree is a separate source distribution with no selected Apple signing team or imported UHD identity. The default bundle ID is a template. Dependencies retain their attribution. A source cleanup removes direct identifiers in the files; it cannot make an existing GitHub account, reused artwork or previously shared app anonymous.

## Publish this directory, not its parent workspace

1. Review the source and documentation, then run `python3 scripts/check-public-release.py`.
2. Before creating any Git commits, configure the author display name you want published and the GitHub-provided private `noreply` email for the account you intend to use. Do not reuse private repository history. This copy intentionally includes no `.git` history.
3. Create a new GitHub repository under your chosen account and upload only this directory's source files. No repository has been created or uploaded by these scripts.
4. Preserve LICENSE.txt and NOTICE.md. They name upstream contributors, not the original private installer.
5. For a source release, run `python3 scripts/make-public-archive.py`. Upload the resulting source ZIP from `dist/` after reviewing it. This excludes local signing settings, builds, environments and Git metadata. It is not a signed installer.

Build release binaries from a clone in a temporary folder such as `/tmp`, not your home folder: Xcode records the build folder in the app executable, so a build under `/Users/<you>/` contains your account name. `check-unsigned-ipa.py` and `build-mac.sh` reject such builds.

An audited unsigned IPA may be attached as a **separate Release asset**, alongside its SHA-256 file and matching GPL source ZIP. Keep `*.ipa` excluded from source commits. Run `python3 scripts/check-unsigned-ipa.py /path/to/the/unsigned.ipa` and audit the binary for known private identifiers before upload. Include INSTALL-IPA.md in the release instructions. Never substitute a locally signed personal IPA for the unsigned asset.

Set Git's author information yourself before your first commit. GitHub explains [commit-email privacy](https://docs.github.com/en/account-and-profile/how-tos/email-preferences/setting-your-commit-email-address); changing it later does not rewrite old commits.

## Keep private

- Personal signing certificates/profiles, signed IPAs, archives, dSYMs and build logs.
- TwinVine installations/configuration, client identities, private keys, PKCS#12 packages and setup links.
- Xcode user state, local environment files and full device reports.
- Maintainer account identity, local paths and registered-device identifiers in any future generated artefacts.

The included ignore rules are a safeguard, not a guarantee. Inspect `git status` before committing. A signed binary normally contains signing identity information; source users should build/sign with their own account. Do not advertise the private development IPA as a general public download.

The release checker detects common accidental artefacts, local account paths, nonempty project signing teams, obvious key/token data and unexpected source types. It is not an exhaustive secret scanner or an anonymity guarantee. Packaging intentionally stops if those checks fail.
