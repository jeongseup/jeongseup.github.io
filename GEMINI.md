# Agent Instructions & Project Protocols

This document rules the development and maintenance of the `jeongseup.github.io` project. Any AI agent or developer working on this repository **MUST** strictly adhere to these guidelines to ensure consistency, stability, and maintainability.

## 1. Golden Reference: Hugo Theme Stack Starter

- **Rule**: When unsure about directory structure, configuration hierarchy, or proper feature implementation, **ALWAYS** reference the [CaiJimmy/hugo-theme-stack-starter](https://github.com/CaiJimmy/hugo-theme-stack-starter) repository first.
- **Implication**: adopt the file paths, naming conventions, and best practices defined in the starter kit. Do not invent custom folder structures unless absolutely necessary.

## 2. Mandatory Localization (English & Korean)

- **Rule**: **ALL** content actions must be bilingual.
- **Action Items**:
  - **Creation**: When creating a new post/page, **ALWAYS** create both `filename.md` (English) and `filename.ko.md` (Korean).
  - **Modification**: When updating logic, code snippets, or factual information in a post, apply the changes to **BOTH** language files immediately.
  - **Translation**: If exact Korean text is not provided, provide a high-quality translation or a clear placeholder structure for the user to fill.

## 3. Configuration Protocol

- **Rule**: Maintain configuration in `config/_default/`.
  - `config.toml`: Core Hugo settings (BaseURL, Title, Author, Services like GA).
  - `params.toml`: Theme-specific visual/functional settings (Comments, Sidebar, Widgets).
  - `menu.toml`: Navigation structure.
  - `module.toml`: Hugo Module configurations.
- **Prohibited**: Do NOT create a root `hugo.toml` or `config.yaml`. This overrides the `config/` directory and breaks the build (as seen in pervious issues).

## 4. Theme Management

- **Rule**: Use **Hugo Modules**.
  - This project relies on `go.mod` to fetch the theme.
  - **DO NOT** clone the theme into `themes/hugo-theme-stack` manually unless specifically asked for debugging references.
  - Trust `hugo mod get` and the module cache.

## 5. Development & Deployment

- **Rule**: Verify before commit.
  - Use `hugo serve` to valid local rendering.
  - Use `hugo` (build command) to verify that production builds will pass, especially when checking for missing partials or strict template errors.
  - Use `hugo.IsServer` in templates to differentiate between local dev and production (e.g., for Analytics scripts).
