# Release Process

This document outlines the process for releasing new versions of Blankie.

Blankie is a universal app. A release covers the Mac build (App Store, GitHub, and Homebrew) and the iOS/iPadOS build for iPhone and iPad (App Store and TestFlight, including CarPlay).

## Version Numbering

Blankie follows [Semantic Versioning](https://semver.org/):

- MAJOR version for incompatible API changes
- MINOR version for new functionality in a backwards compatible manner
- PATCH version for backwards compatible bug fixes

## Pre-Release Checklist

Before creating a release, ensure:

- [ ] All tests pass
- [ ] Version numbers are updated:
  - `MARKETING_VERSION` in `Blankie.xcodeproj/project.pbxproj` (the target editor updates every target and configuration at once)
  - `CURRENT_PROJECT_VERSION` (the build number) in `Configuration.xcconfig` — bump it for every uploaded build
- [ ] `CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/) format, with items moved from Unreleased into the new version section
- [ ] All new features are documented
- [ ] Credits are updated for any new contributors

## Scheme Selection

Pick the scheme by what you're archiving:

- **Mac** (App Store/TestFlight, GitHub, Homebrew): archive from **`Blankie (Universal)`** with the **Any Mac** destination. This uses the standard entitlements (no CarPlay).
- **iOS** (App Store/TestFlight): archive from **`Blankie (Universal with CarPlay)`** with the **Any iOS Device** destination, so the CarPlay entitlement is included. This requires the `com.apple.developer.carplay-audio` entitlement on the release bundle ID (see [CARPLAY.md](CARPLAY.md)).

On iOS the app ships animated artwork as **Apple-hosted [Background Assets](https://developer.apple.com/documentation/backgroundassets) asset packs** (one pack per variant, downloaded on demand). The videos are not bundled in the build and not stored in git. They are packaged into `.aar` archives and uploaded to App Store Connect separately from the app, so plan for an extra upload and review step. The architecture and one-time project setup (downloader extension, App Group, plist keys) are in [DEVELOPMENT.md](DEVELOPMENT.md#animated-artwork-background-assets).

Each clip ships two variants because iPhone and iPad lock screens advertise different artwork keys: a **3:4 portrait** master (`<Name>`, for iPhone's 3x4 key) and a **1:1 square** crop (`<Name>Square`, for iPad's 1x1 key). Both files live in the same `Blankie/Resources/AnimatedArtwork/<Name>/` folder, and every source `.mov` (both variants, all listed in `scripts/animated-artwork.manifest`) lives together on a single GitHub Release: [`artwork-assets-v2`](https://github.com/codybrom/blankie/releases/tag/artwork-assets-v2).

Each release, build and upload the asset packs:

```bash
scripts/package_animated_artwork.sh        # → build/AssetPacks/<Name>.aar (42 packs: 21 portrait + 21 square)
```

Then upload the `.aar` files to App Store Connect (Transporter app, `xcrun altool`, or the App Store Connect API) and submit them for review alongside the build. Apple hosts up to 200 GB of asset packs; ours are well under that.

> **Updating animated artwork:** Changes to any `.mov` require publishing a fresh, complete asset release (replace the whole set — don't split it across tags). Regenerate the square crops with `scripts/prepare_loop.sh --square`, or for an entirely new clip run `prepare_loop.sh <source> --square` to emit the portrait master, both previews, and the square loop at once. Anchor the release to an empty orphan commit so it stays out of code history:
>
> ```bash
> EMPTY_TREE=$(git hash-object -t tree /dev/null)
> ANCHOR=$(git commit-tree "$EMPTY_TREE" -m "Animated artwork binary assets (release anchor)")
> git tag artwork-assets-vN "$ANCHOR" && git push origin artwork-assets-vN
> gh release create artwork-assets-vN --title "Animated Artwork Assets vN" \
>   --notes "Binary .mov assets fetched by scripts/package_animated_artwork.sh." \
>   Blankie/Resources/AnimatedArtwork/*/*.mov
> ```
>
> Then regenerate `scripts/animated-artwork.manifest`, bump the default `TAG` in `scripts/package_animated_artwork.sh`, re-run `scripts/package_animated_artwork.sh`, and upload the new asset-pack versions to App Store Connect.

## Creating a Release

1. **Tag the Release**

   ```bash
   git tag -a v2.0.0 -m "chore: bump marketing version to v2.0.0"
   git push origin v2.0.0
   ```

2. **Archive the builds**
   - In Xcode, select the scheme and destination from [Scheme Selection](#scheme-selection) above
   - Archive the app (Product → Archive). Archive the Mac and iOS builds separately
   - The Organizer window opens when each archive completes

3. **App Store Release**
   - From the Organizer, select an archive and click "Distribute App"
   - Choose "App Store Connect" → "Upload"
   - Follow the prompts to upload to App Store Connect
   - Repeat for the other platform's archive (both platforms live under the same App Store app record)
   - In App Store Connect:
     - Add the new builds to the Mac and iOS versions
     - Update the "What's New" section with release notes from `CHANGELOG.md`
     - Submit for review
     - Once approved, release immediately or schedule the release

4. **GitHub Release**
   - From the Mac archive in the Organizer, click "Distribute App" again
   - Choose "Direct Distribution"
   - After a brief notarization check, the app can be exported
   - Export to a folder, then create a ZIP file named **`Blankie.zip`** containing only the exported `Blankie.app` at the root level

5. **Create the GitHub Release**
   - Go to the GitHub releases page
   - Create a new release from the tag
   - Copy the relevant section from `CHANGELOG.md` as the release notes
   - Upload `Blankie.zip` as the release asset

## Post-Release Tasks

### Update Homebrew Cask

After the GitHub release is published:

1. Wait for the release ZIP to be available on GitHub
2. Run the following command to update the Homebrew cask:

   ```bash
   brew bump-cask-pr --version [version] blankie
   ```

   Replace `[version]` with the new version number (e.g., `2.0.0`)

3. The command will automatically:
   - Download the new release
   - Calculate the SHA256 checksum
   - Update the cask formula
   - Create a pull request to the Homebrew cask repository

4. Monitor the pull request for any feedback from Homebrew maintainers

**Note:** You need to have Homebrew and the `homebrew/cask` tap installed to run this command.

If the `brew bump-cask-pr` command fails:

- Ensure you have the latest Homebrew: `brew update`
- Check that you have push access to your Homebrew fork
- Manually create a PR if needed, updating the version and sha256 in the cask file
