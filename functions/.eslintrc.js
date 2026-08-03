module.exports = {
  root: true,
  env: {
    es6: true,
    node: true,
  },
  extends: [
    "eslint:recommended",
    "plugin:import/errors",
    "plugin:import/warnings",
    "plugin:import/typescript",
    "google",
    "plugin:@typescript-eslint/recommended",
  ],
  parser: "@typescript-eslint/parser",
  parserOptions: {
    project: ["tsconfig.json", "tsconfig.dev.json"],
    sourceType: "module",
  },
  ignorePatterns: [
    "/lib/**/*", // Ignore built files.
    "/generated/**/*", // Ignore generated files.
  ],
  plugins: [
    "@typescript-eslint",
    "import",
  ],
  rules: {
    "quotes": ["error", "double"],
    "import/no-unresolved": 0,
    // `SwitchCase: 1` matches Prettier, which indents `case` inside `switch`;
    // the google preset expects it flush with the `switch`. Surfaced by the
    // first switch statement in functions/ (notify.ts, P3-04) — the same
    // Prettier-vs-preset disagreement as the rules below, found later only
    // because nothing here had a switch until now.
    "indent": ["error", 2, { SwitchCase: 1 }],

    // --- Deviations from the `google` preset, and why ---
    //
    // This config is `firebase init` scaffolding and had never actually run:
    // the emulator does not execute predeploy hooks, so the first time it
    // fired was the first real deploy (P2-16), against a codebase written in
    // a different style throughout. 234 of the 248 errors were these three
    // rules disagreeing with every file rather than finding a defect. The
    // genuine ten — over-length lines, backtick strings with no
    // interpolation, two undocumented helpers — were fixed in source.
    //
    // `object-curly-spacing`: google wants `{foo}`, every file here is
    // Prettier-formatted `{ foo }`. 160 errors, no behaviour.
    "object-curly-spacing": ["error", "always"],

    // `operator-linebreak`: Prettier trails binary operators (`+`, `||`, `&&`)
    // but LEADS the ternary `?`/`:`. Encoded exactly, rather than picking one
    // side for everything — the ternaries in streak.ts and the mapper carry a
    // comment above each branch, which only reads if the operator leads.
    "operator-linebreak": [
      "error",
      "after",
      { overrides: { "?": "before", ":": "before" } },
    ],

    // `valid-jsdoc` is deprecated in ESLint and demands @param/@return tags on
    // every documented function. The doc comments in this codebase are prose
    // explaining *why*, which is the house convention and worth more than tag
    // coverage. `require-jsdoc` stays on, so new helpers still need a comment
    // — it just does not dictate the shape.
    "valid-jsdoc": "off",
  },
};
