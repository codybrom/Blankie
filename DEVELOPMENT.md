# Development Setup

This guide will help you set up your development environment for contributing to Blankie.

## Prerequisites

- macOS 26 or later (required for certain Xcode 26 features used in the project)
- Xcode 26 or later
- An Apple Developer account (free or paid)

## Setup Instructions

1. **Fork and clone the repository**

   ```bash
   git clone https://github.com/YOUR_USERNAME/blankie.git
   cd blankie
   ```

2. **Configure your development environment**

   Copy the example configuration file:

   ```bash
   cp Configuration.example.xcconfig Configuration.xcconfig
   ```

   > **Important**: `Configuration.xcconfig` is ignored by git to keep Bundle IDs and Team IDs private. Never commit this file.

3. **Add your development team**

   Edit `Configuration.xcconfig` and add your Team ID:

   ```plaintext
   DEVELOPMENT_TEAM = YOUR_TEAM_ID_HERE
   ```

   **Finding your Team ID:**

   - **Apple Developer Program Members:**
     1. Open Xcode → Preferences → Accounts
     2. Sign in with your Apple ID
     3. Select your account and click "Manage Certificates"
     4. Your Team ID is listed under your account name

   - **Personal Team (Free):**
     1. Open Xcode → Preferences → Accounts
     2. Click "+" to add your Apple ID
     3. Xcode will create a Personal Team automatically
     4. Your Personal Team ID will be listed there

4. **Set a unique Bundle Identifier**

   In `Configuration.xcconfig`, set a unique identifier:

   ```plaintext
   PRODUCT_BUNDLE_IDENTIFIER = com.yournamehere.blankie
   ```

   > **Note**: You cannot use the same bundle identifier as the official Blankie app.

5. **Animated artwork assets**

   The animated artwork videos are not stored in git or bundled into the app. On iOS they ship as Apple-hosted [Background Assets](https://developer.apple.com/documentation/backgroundassets) asset packs. The source `.mov` files (both the 3:4 portrait and 1:1 square variant of each clip) live as assets on the [`artwork-assets-v2`](https://github.com/codybrom/blankie/releases/tag/artwork-assets-v2) GitHub Release so cloning the repository stays light.

   You do not need the videos to build and run the app, only to package the asset packs. To fetch the videos and/or builds the packs, run:

   ```bash
   scripts/package_animated_artwork.sh
   ```

   This script downloads any missing files, then idempotently writes one `build/AssetPacks/<Name>.aar` per variant (a portrait `<Name>` and a square `<Name>Square` for each clip). Pass `--force` to re-download, or artwork ids (e.g. `RainLoop Beach RainLoopSquare`) to limit it. Preview images and metadata are bundled in the app for instant gallery display. See [RELEASE.md](RELEASE.md) for uploading the packs to App Store Connect.

6. **Open and build the project**

   ```bash
   open Blankie.xcodeproj
   ```

   Then build and run using Xcode (⌘+R).

## Animated artwork (Background Assets)

On iOS the animated lock-screen artwork ships as Apple-hosted [Managed Background Assets](https://developer.apple.com/documentation/backgroundassets), downloaded on demand.

Each clip has two packs because iPhone and iPad lock screens advertise different artwork keys (`MPNowPlayingInfoCenter.supportedAnimatedArtworkKeys`): a 3:4 portrait pack `<id>` holding `<id>/<id>.mov` (iPhone's 3x4 key) and a 1:1 square pack `<id>Square` holding `<id>/<id>Square.mov` (iPad's 1x1 key). Both files live in the same `<id>/` folder, so `relativeVideoPath(for:)` maps a `…Square` pack back to the base folder. `NowPlayingManager+AnimatedArtwork.swift` picks the variant from the device's supported key when it publishes. `BackgroundResourceManager` (`Blankie/Managers/BackgroundResourceManager.swift`) wraps `AssetPackManager.shared`:

- `resourceURL(for:)` downloads the pack if needed and returns a playable URL.
- `availableURL(for:)` returns a URL synchronously for a pack that's already on the device (the Now Playing path uses this).
- `state(for:)` and `states` drive the gallery's download UI; progress comes from `statusUpdates(forAssetPackWithID:)`.
- `removeResource(_:)` deletes the pack and frees every byte. The video plays straight from the pack and is never copied into Documents, so "Remove Download" actually reclaims the space.

Videos stay out of the app bundle and out of git. Preview images and metadata stay bundled so the gallery loads instantly. Custom (user-imported) artwork is untouched, still in `Documents/Artwork`.

### Deployment target

We target iOS 26.4 for `ensureLocalAvailability(of:requireLatestVersion:)` and `assetPackIsAvailableLocally(withID:)`. To get an `AssetPack` from an id, we call `AssetPackManager.assetPack(withID:)`, isolated in `resolveAssetPack(id:)`. Apple's docs point that call toward `AssetPackManager.manifest`, but `manifest` is iOS 27 and isn't in the iOS 26 SDK yet. There's a `TODO(iOS 27 SDK)` marker to move the helper to the manifest API when the minimum target hits 27.

### One-time project setup

The app target is already wired up. `Blankie-Info.plist` and `Blankie-CarPlay.plist` carry `BAHasManagedAssetPacks` (true), `BAUsesAppleHosting` (true), and `BAAppGroupID` (`$(APP_GROUP_IDENTIFIER)`, which resolves to `group.com.codybrom.blankie`). Apple-hosted projects use only those three keys, so leave out `BAManifestURL`, `BAMaxInstallSize`, and the rest.

The downloader extension has to be added in Xcode, since it can't be scripted:

1. Add the extension. File → New → Target → Application Extension → Background Download. Pick **Apple-Hosted, Managed** as the type, name it (e.g. `BlankieAssetDownloader`), Finish, then Activate the scheme. Its principal type conforms to StoreKit's `StoreDownloaderExtension` and can stay empty. The system's default implementation does the scheduling, so `import StoreKit` and leave the inherited `BADownloaderExtension` methods alone.
2. Share the App Group. In Signing & Capabilities, add the extension to `group.com.codybrom.blankie`, the same group the app uses. Both targets need it.
3. Add the extension to both schemes ("Blankie (Universal)" and "Blankie (Universal with CarPlay)") so it embeds in every iOS archive.

`EMBED_ASSET_PACKS_IN_PRODUCT_BUNDLE` stays on for local testing. App Store builds pull the packs from App Store Connect, not the bundle. To try packs on device before uploading, build them with `scripts/package_animated_artwork.sh` and follow Apple's [Testing asset packs locally](https://developer.apple.com/documentation/backgroundassets/testing-asset-packs-locally).

## Code Style

- We *try* to follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/)
- Use `swift-format` with default settings
  - In Xcode: Editor → Structure → Format File with 'swift-format'
  - Or use the command line tool
- Match existing code patterns and conventions
- Write clear commit messages explaining your changes

## Testing

- Run existing unit tests: ⌘+U in Xcode
- Add tests for new functionality when possible
- Test your changes thoroughly before submitting a PR

## Important Considerations

> **⚠️ Exercise extreme caution when modifying:**
>
> - Sound configurations
> - Naming conventions
> - Preset functionality
>
> These directly affect user settings and even small changes can significantly impact the user experience.

## Submitting Changes

1. Create a feature branch
2. Make your changes following the guidelines above
3. Test thoroughly
4. Submit a pull request with:
   - Clear description of changes
   - Reference to any related issues (`Closes #123`)
   - Screenshots for UI changes

For more details, see our [Contributing Guidelines](CONTRIBUTING.md).
