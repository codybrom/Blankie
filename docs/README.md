# Blankie Website

This is the website for [Blankie](https://blankie.rest), built with [Astro](https://astro.build) and deployed on GitHub Pages.

## Production

The live site is available at [https://blankie.rest](https://blankie.rest)

## Tech Stack

- [Astro](https://astro.build) - Static Site Generator
- [Tailwind CSS](https://tailwindcss.com) - Styling
- [astro-seo](https://github.com/jonasmerlin/astro-seo) - SEO optimization
- [@playform/compress](https://github.com/playform/compress) - Asset compression

## Performance

The website maintains a perfect 100 score across all categories in Google Lighthouse (Performance, Accessibility, Best Practices, and SEO). All contributions should ensure these scores are maintained.

## Development

You can develop either locally or using Docker Compose. Both methods will give you hot-reloading and the same development experience.

### Using Docker Compose (Recommended)

```bash
# From the `docs` directory, simply run:
docker-compose up

# Or, from the root directory:
cd docs && docker-compose up
```

The development server will be available at `http://localhost:4321`. The container will automatically:

- Mount the parent directory to access required files (FAQ.md, CONTRIBUTING.md, etc.)
- Copy necessary files from the parent directory
- Enable hot-reloading for changes in `src/` and `public/` directories
- Maintain container-based node_modules to avoid platform issues

### Local Development

- Note: Node.js 24 or later is required to run the development server.

If you prefer developing without Docker, open a terminal inside the `docs` directory, then run the following commands:

1. Install dependencies:

    ```bash
    npm install
    ```

2. Start the development server:

    ```bash
    npm run dev
    ```

3. Build for production:

    ```bash
    npm run build
    ```

4. Preview the production build:

    ```bash
    npm run preview
    ```

## Deployment

The site is automatically deployed to GitHub Pages at [https://blankie.rest](https://blankie.rest) when changes are pushed to the `main` branch that affect files in the `docs` directory or the GitHub Actions workflow file. The deployment is handled by the GitHub Actions workflow defined in `.github/workflows/pages.yml`.

## License

The documentation website is included under the project's MIT License. See the [LICENSE](../LICENSE) file for details.
