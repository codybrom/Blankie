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

   The animated artwork videos (`Blankie/Resources/AnimatedArtwork/<Name>/<Name>.mov`) are not stored in git. They are published as assets on the [`artwork-assets-v1`](https://github.com/codybrom/blankie/releases/tag/artwork-assets-v1) GitHub Release so cloning the repository stays fast. Xcode pulls them automatically on first build via the "Fetch Animated Artwork" build phase, so you usually do not need to do anything.

   To fetch them manually (or re-verify them), run:

   ```bash
   scripts/fetch_animated_artwork.sh
   ```

   It downloads only what is missing and checks every file against `scripts/animated-artwork.manifest` (SHA-256). Pass `--force` to re-download everything.

6. **Open and build the project**

   ```bash
   open Blankie.xcodeproj
   ```

   Then build and run using Xcode (⌘+R).

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
