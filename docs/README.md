# Blankie Website

This is the website for [Blankie](https://blankie.rest), built with [Astro](https://astro.build) and deployed on Cloudflare Workers.

## Production

The live site is available at [https://blankie.rest](https://blankie.rest)

## Tech Stack

- [Astro](https://astro.build) - Static site generator
- [React](https://react.dev) - Interactive island components
- [TypeScript](https://www.typescriptlang.org) - Type safety
- [Tailwind CSS](https://tailwindcss.com) - Styling
- [shadcn/ui](https://ui.shadcn.com) on [Base UI](https://base-ui.com) - Component primitives
- [Lucide](https://lucide.dev) - Icons
- [marked](https://marked.js.org) - Markdown rendering
- [astro-seo](https://github.com/jonasmerlin/astro-seo) - SEO metadata

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

### Checks

Before opening a pull request, run the same checks CI expects:

- `npm run check` - Astro and TypeScript type checking
- `npm run lint` - Biome lint and format check (`npm run lint:fix` applies safe fixes)
- `npm run test` - Vitest unit tests
- `npm run format` - Biome formatting

## Deployment

The site is deployed to Cloudflare Workers at [https://blankie.rest](https://blankie.rest) by Workers Builds, Cloudflare's Git integration (configured in the Cloudflare dashboard with `docs` as the root directory). Pushes to `main` that touch the site or the files it reads run `npm run lint && npm test && npm run build`, then `npm run deploy`, which uploads the press kit zip to the `blankie-assets` R2 bucket and runs `wrangler deploy`. Other branches get a preview deploy instead.

The Worker in `worker/index.ts` serves the built site from static assets (configured in `wrangler.jsonc`). Requests with `Accept: text/markdown` get each page's Markdown version, and `www.blankie.rest` redirects to the apex domain. To try it locally, run `npm run build` and then `npx wrangler dev`.

## License

The documentation website is included under the project's MIT License. See the [LICENSE](../LICENSE) file for details.
