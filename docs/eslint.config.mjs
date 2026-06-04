import { defineConfig, globalIgnores } from "eslint/config";
import js from "@eslint/js";
import tseslint from "typescript-eslint";
import astro from "eslint-plugin-astro";
import react from "eslint-plugin-react";
import reactHooks from "eslint-plugin-react-hooks";
import jsxA11y from "eslint-plugin-jsx-a11y";
import betterTailwind from "eslint-plugin-better-tailwindcss";
import prettier from "eslint-config-prettier";
import globals from "globals";

// `recommended` minus unknown-classes (false positives here) and rules Prettier handles
const tailwindRules = {
  ...betterTailwind.configs.recommended.rules,
  "better-tailwindcss/no-unknown-classes": "off",
  "better-tailwindcss/enforce-consistent-line-wrapping": "off",
  "better-tailwindcss/enforce-consistent-class-order": "off",
  "better-tailwindcss/enforce-canonical-classes": ["warn", { rootFontSize: 16 }],
};

const tailwindSettings = {
  "better-tailwindcss": {
    entryPoint: "src/styles/global.css",
  },
};

export default defineConfig([
  globalIgnores([
    "**/dist/**",
    "**/node_modules/**",
    ".astro/**",
    "public/**",
    "*.min.js",
  ]),

  js.configs.recommended,
  tseslint.configs.recommended,

  {
    languageOptions: {
      ecmaVersion: "latest",
      sourceType: "module",
      globals: {
        ...globals.browser,
        ...globals.node,
      },
    },
  },

  {
    files: ["**/*.{ts,tsx,mts,cts}"],
    rules: {
      "@typescript-eslint/no-unused-vars": [
        "warn",
        { argsIgnorePattern: "^_", varsIgnorePattern: "^_", caughtErrorsIgnorePattern: "^_" },
      ],
      "@typescript-eslint/no-explicit-any": "warn",
      "@typescript-eslint/consistent-type-imports": [
        "warn",
        { prefer: "type-imports", fixStyle: "inline-type-imports" },
      ],
    },
  },

  {
    files: ["**/*.{jsx,tsx}"],
    extends: [react.configs.flat.recommended, react.configs.flat["jsx-runtime"]],
    settings: { react: { version: "detect" } },
  },
  {
    files: ["**/*.{jsx,tsx}"],
    plugins: { "react-hooks": reactHooks },
    rules: {
      ...reactHooks.configs.recommended.rules,
      "react/prop-types": "off",
    },
  },
  {
    files: ["**/*.{jsx,tsx}"],
    extends: [jsxA11y.flatConfigs.recommended],
  },

  astro.configs.recommended,

  {
    files: ["**/*.{js,mjs,cjs}"],
    extends: [tseslint.configs.disableTypeChecked],
  },

  // Tailwind lints need separate blocks per parser to scan class lists.
  {
    files: ["**/*.{jsx,tsx}"],
    plugins: { "better-tailwindcss": betterTailwind },
    settings: tailwindSettings,
    rules: tailwindRules,
  },
  {
    files: ["**/*.astro"],
    plugins: { "better-tailwindcss": betterTailwind },
    settings: tailwindSettings,
    rules: tailwindRules,
  },

  prettier,
]);
