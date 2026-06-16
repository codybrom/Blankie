# Contributing to Blankie

> Hi, @codybrom here, and I'm thrilled you're interested in contributing to Blankie! I was inspired to create Blankie because an incredible community of people came together to support its inspiration, [Blanket](https://github.com/rafaelmardojai/blanket). My hope for Blankie is that a similar community will come together to support its development and growth. I'm excited to see what we can build together!

This document outlines the guidelines, expectations, and processes for contributing to this project. Following these will ensure a smooth and efficient contribution experience for everyone.

## How Can I Contribute?

There are many ways you can contribute, including:

* **Testing & Bug Reports:** Help test features and identify issues. Find a bug? [Open an issue](https://github.com/codybrom/blankie/issues/new?assignees=&labels=bug&projects=&template=bug_report.yml&title=%5BBug%5D%3A+) using our bug report template.
* **Feature Suggestions:** Have an idea for Blankie? [Submit a feature request](https://github.com/codybrom/blankie/issues/new?assignees=&labels=enhancement&projects=&template=feature_request.yml&title=%5BFeature%5D%3A+). Design mockups, UI/UX flows, and even rough sketches are welcome! Be sure to explain your use case and be open to discussion.
* **[Code Contributions](#code-contributions):** Dive right in and help us fix bugs, add new features, improve performance, and enhance Blankie's architecture.
* **[Documentation and Website Contributions](#documentation-and-website-contributions):** Help improve core documentation (like this page), write user guides and make changes or additions to the Blankie website.
* **[Other Ways](#other-contributions):** Interested in contributing in other ways? We're open to new ideas and suggestions, but please check the guidelines below.

### Before You Start

* **Code of Conduct:** Please review our [Code of Conduct](CODE_OF_CONDUCT.md). It ensures a safe and welcoming environment for everyone.
* **Check Open / Existing Issues:** Before starting on a new feature or bug fix, check other [issues](https://github.com/codybrom/blankie/issues) to make sure it hasn't already been addressed or reported. You may find a related issue with helpful discussion.
* **Start with Small Steps**: If you’re new to the project, it’s a good idea to begin with smaller tasks to get familiar with the code, contributing, and development processes.

## Code Contributions

If you'd like to help out with the source code, follow these guidelines:

1. **Fork the Repository:** Start by forking the [Blankie repository](https://github.com/codybrom/blankie) to your GitHub account. You can then clone the forked repository to your local machine.
2. **Set Up Your Development Configuration:** Follow the [development setup instructions](DEVELOPMENT.md) to create a `Configuration.xcconfig` file with your own development team and bundle identifier (this file is ignored by git to keep your personal settings private). You may not use the same bundle identifier as the main Blankie app and you should not update these fields in configuration of the project itself. Please keep your personal settings private.
3. **Make the Changes:** Write clean and clear code following [Swift.org's guidelines](https://www.swift.org/documentation/api-design-guidelines/). Use appropriate comments and match the existing code style and conventions in the project. Blankie uses `swift-format` with default settings to keep code clean and consistent. You can run it via Xcode (Editor > Structure > Format File with ‘swift-format’) or command line to ensure consistent formatting. If you're unsure about style, feel free to ask in an issue or pull request.
    * Keep your changes focused and avoid unrelated changes in the same pull request. PRs that make unnecessary changes or are too large may be rejected or asked to be split into smaller PRs.
    * If you're adding new features, consider opening an issue first to discuss the feature and gather feedback before starting development.
4. **Test:** Ensure that your changes work correctly without causing issues in other areas. Blankie's test suite (XCTest) covers core audio playback, preset management, the `Sound` model, and the app-data migration paths (UserDefaults and SwiftData into the app group), plus a UI screenshot test across all languages. Run it in Xcode with ⌘U or via the `Blankie.xctestplan` test plan. Please run the tests before submitting, and add new unit or UI tests for any behavior you change.
5. **Commit Your Changes:** With each commit, write clear commit messages explaining the reason and context for your changes. This will help other collaborators understand the scope of your contributions.
6. **Create a Pull Request:** Submit a pull request from your branch with a clear explanation of the changes that you've made to the original project repository, along with the links to issues referenced (`Closes #123`, `Fixes #345`) .

### Code Considerations

> [!IMPORTANT]
> Please exercise extreme caution when modifying **sound configurations**, **naming conventions** or **preset functionality**.
>
>These components directly affect user settings and preferences and even small changes in these areas can significantly impact user experience and existing configurations.

Before implementing changes that might alter core functionality in serious ways:

1. **Discuss First**
   * Open an issue to propose and discuss changes and gather feedback from maintainers and the community

2. **Maintain Core Requirements**
   * Maintain consistent volume normalization across all sounds
   * Ensure smooth transitions between sound states (play/pause/volume)
   * Preserve compatibility with system media controls on every platform (macOS, iOS, and iPadOS), including CarPlay
   * Protect functionality of existing user-saved presets

3. **Implement Carefully**
   * Prioritize backwards-compatible solutions
   * Develop migration paths for existing user settings
   * Document any breaking changes thoroughly in pull requests
   * Consider phased rollouts for major changes

## Translation Contributions

Blankie aims to be accessible to users around the world, which means we need help translating the app into different languages. You don't need to be a programmer to contribute translations!

### Getting Started with Translations

1. **Check Current Status**: Visit our [translations page](https://blankie.rest/i18n) to see which languages already have translations and their status.

2. **Get the Template**: Download a English template or current translation in JSON or CSV format from the [translations page](https://blankie.rest/i18n) with all the strings that need translation.

3. **Edit the Template**: Using any text editor, translate the English strings to your target language. Keep the  structure intact - only modify the "target" content within the strings.

4. **Submit Your Translation**: There are two ways to submit translations:
   * **GitHub Issue**: Create a [translation contribution issue](https://github.com/codybrom/blankie/issues/new?assignees=&labels=translation-contribution&projects=&template=translation_contribution.yml&title=%5BTranslation%5D%3A+) and attach your JSON file
   * **Email**: Send updated translation files or general feedback to <i18n@blankie.rest>

### Translation Guidelines

* **Respect Context**: The `comment` field provides context about where each string appears in the app. Use this to guide your translation choices.
* **Consistency**: Maintain consistent terminology throughout the translation.
* **Special Characters**: Pay attention to formatting placeholders like `%@` (which represent variable content) and preserve them in your translation.
* **Testing**: If you have the ability to, you might also test your translations by building the app locally to see how they appear in context.

### Translation Review Process

Once submitted, your translations will go through this process:

1. Initial review by the maintainers
2. For languages we can't verify internally, we may reach out to other community members who speak that language
3. After review, translations will be marked as either "translated" or "needs review"
4. Approved translations will be included in a future Blankie release

### How to Submit Translations

You can submit translations in three ways:

1. **GitHub Issue**: Create a [translation contribution issue](https://github.com/codybrom/blankie/issues/new?assignees=&labels=translation-contribution&projects=&template=translation_contribution.yml&title=%5BTranslation%5D%3A+) and attach your updated JSON or CSV file

2. **Email**: Send your translation files to <i18n@blankie.rest>

3. **Direct Import**: If you're comfortable using a command line and Xcode you can use our `blanki18n` tool to import your translations directly into the app. This is the preferred method for developers and contributors who want to test their translations locally.

   ```bash
   # Make the tool executable
   chmod +x scripts/blanki18n.swift
   
   # Using interactive mode (will prompt for language code)
   ./scripts/blanki18n.swift path/to/your-translation.[csv|json]
   
   # Or specify language code directly
   ./scripts/blanki18n.swift path/to/your-translation.[csv|json] es
   ```

   The tool will update `Localizable.xcstrings` directly with your translations for you to build and then test locally. You can then create a pull request with your changes on a fork.

For general translation feedback or to report issues with existing translations, you can create a GitHub issue or email us at the address above. If you have any other questions about translations or need clarification on specific strings, please don't hesitate to reach out. We're here to help!

### Adding Support for New Languages (Technical Guide)

When adding support for a new language to Blankie, you need to update several files across the codebase. This guide outlines all the locations that must be modified:

#### Necessary File Updates (Roughly in order of importance)

1. **`Blankie/Localizable.xcstrings`**
   * This is the main translation file containing all localized strings
   * Add your new language code as a new localization
   * Use the `scripts/blanki18n` tool to import translations from a JSON or CSV file

2. **`Blankie.xcodeproj/project.pbxproj`**
   * Add the language to the project's known regions
   * **Important**: Regional language codes (e.g., `en-GB`, `zh-Hans`) must be wrapped in quotes
   * Standard language codes (e.g., `es`, `fr`) don't need quotes

3. **`FAQ.md`**
   * Add the language with its language code to the available languages list
   * Format: `Language Name (language-code)`

4. **`Blankie/credits.json`**
   * Add translator credits if provided
   * Include translator name and optional link

5. **`CHANGELOG.md`**
   * Document the addition of the new language in the appropriate version section
   * Format: `- Added [Language] translation support thanks to [Contributor Name]`

6. **`docs/src/utils/i18n-helpers.ts`**
   * Only update if adding a regional language code (e.g., `en-GB`, `zh-Hans`)
   * Add the regional code mapping to ensure proper handling

7. **`docs/src/pages/index.astro`**
   * Update the header language list (temporary location) to showcase support for the new language

8. **`.vscode/settings.json`** (for cspell)
   * Add the native language name and contributor to the words list to prevent them from being flagged as typos

#### Testing Your Changes

After updating all the files:

1. Build the project in Xcode to ensure all language files are properly recognized
2. If the language is different from your system language, you can change your system language, switch to the new language in Blankie's Preferences or create a new scheme in Xcode to verify the app displays correctly
3. Check that the translation status page reflects the new language
4. Verify all credits appear correctly on the About screen

## Credit and Attribution

It is important to give credit where credit is due. Contributors to Blankie may be credited on the [Credits](https://blankie.rest/credits) page of the Blankie website and on the app's About screen. Credits for the app and website are controlled by `Blankie/credits.json`. If you would prefer not to be credited, please let us know in your pull request.

## Documentation and Website Contributions

Blankie has a few core GitHub documentation pages that you can contribute to:

* Our [README](README.md) page
* Our [CONTRIBUTING](CONTRIBUTING.md) page

If you see a typo, error, or something that could be improved, feel free to submit a pull request with your changes. Also, if you have ideas for new documentation or sections, please open an issue to discuss your idea.

The rest of Blankie's documentation is made available via the [Blankie website](https://blankie.rest). The [Blankie website](https://blankie.rest) code is located in the `/docs` directory. For technical details, and development setup, please refer to the [website's README](docs/README.md).

Before opening a pull request related to the website, please:

1. Review the [website README](docs/README.md)
2. Follow the existing code style and organization
3. Test all changes locally
4. Test a production build using Google Lighthouse and ensure all Lighthouse scores remain at 100
    * You can do this by running `npx astro build && npx astro preview` from the `/docs` directory and then running Lighthouse tests in Chrome DevTools

The website serves as the main documentation hub for Blankie users, so clarity, accessibility, and performance are crucial. If you're unsure about any aspect of website development, feel free to open an issue for discussion.

## Sound Contributions

At this time, we're not seeking new sound contributions to Blankie. However, if you have suggestions for sound effects, you are welcomed to post in the [_"What Sounds Would You Add to Blankie?"_ discussion thread](https://github.com/codybrom/blankie/discussions/13).

## Other Contributions

There are undoubtedly other ways to contribute to Blankie that aren't covered above. If you have an idea for a new way to contribute, please open an issue to discuss it!

## Licensing

Blankie respects the rights of creators and the open source community, and we expect the same from our contributors. By contributing to Blankie, you agree that any contributions will be licensed under the same terms as Blankie itself. You also confirm that you have the right to license any code, content, or other materials you contribute. Contributors are expected to follow Blankie's [License](LICENSE) and [Code of Conduct](CODE_OF_CONDUCT.md). Any contributions that violate these terms are subject to removal.

If you're unsure about the licensability of content you wish to contribute, please ask before submitting a PR. This includes:

* Sound files, images, or other media
* Code snippets from other projects
* AI generated content
* Third-party libraries and dependencies

As part of the open source community, we take licensing and attribution seriously. Proper licensing ensures that Blankie remains free and open while respecting the work of others.

## Questions about Contributing

If you have any questions or need clarification, open a [new issue](https://github.com/codybrom/blankie/issues/new).

We appreciate your contributions, as they make Blankie better for everyone!
