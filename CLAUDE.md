# Claude Code Instructions

## 1. Golden Reference: Hugo Theme Stack Starter

- When unsure about directory structure, configuration hierarchy, or feature implementation, **ALWAYS** reference [CaiJimmy/hugo-theme-stack-starter](https://github.com/CaiJimmy/hugo-theme-stack-starter) first.
- Adopt the file paths, naming conventions, and best practices from the starter kit. Do not invent custom folder structures unless absolutely necessary.

## 2. Configuration Protocol

- Maintain configuration in `config/_default/`:
  - `config.toml`: Core Hugo settings (BaseURL, Title, Author, Services)
  - `params.toml`: Theme-specific visual/functional settings
  - `menu.toml`: Navigation structure
  - `module.toml`: Hugo Module configurations
- **Prohibited**: Do NOT create a root `hugo.toml` or `config.yaml` — it overrides `config/` and breaks the build.

## 3. Theme Management

- Use **Hugo Modules** (`go.mod`). Do NOT clone the theme into `themes/` manually.
- Trust `hugo mod get` and the module cache.

## 4. Development & Deployment

- Verify before commit: `hugo serve` (local) and `hugo` (production build).
- Use `hugo.IsServer` in templates to differentiate local dev vs production.

## 5. Content Language

- 기본 언어는 **한국어**로 작성한다.
- 단, 업계 고유 용어(DeFi, LTV, LT, Flash Loan, PTB, APY, SDK, API 등)는 한국어로 번역하지 않고 **영어 원어 그대로** 사용한다.
- 코드 블록, 변수명, 함수명 등 기술 용어도 원어 유지.

---

## 6. Project Post Naming Convention

### Project Sub-pages (`content/project/<project-name>/`)

File naming pattern: `{type}-{slug}.md`

| Type | Usage | Example |
|------|-------|---------|
| `journal-*` | Development journal / diary | `journal-day1.md`, `journal-day2.md` |
| `preview-*` | Feature preview & technical write-up | `preview-leverage.md` |
| `demo-*` | Demo / showcase | `demo-wallet-connect.md` |
| `deep-dive-*` | In-depth technical analysis | `deep-dive-ptb-architecture.md` |
| `guide-*` | How-to guide | `guide-sdk-setup.md` |

Rules:
- Slug: lowercase kebab-case, descriptive
- `_index.md` is the project overview page (one per project)
- Sequential entries use suffix: `-day1`, `-day2`, ... (not `-1`, `-2`)

### Frontmatter Template

```yaml
---
title: "..."
date: YYYY-MM-DD
draft: false
authors: ["Jeongseup"]
description: "..."
slug: {project}-{type}-{slug}
tags: [...]
categories: [...]
series: ["{Project} Technical Journal"]  # if part of a series
math: false  # set true if using LaTeX
---
```

## 7. Thumbnail Image Generation (Gemini API)

When creating a **new project** or a post that needs a custom thumbnail, auto-generate it using the Gemini API helper script.

### Image paths

| Scope | Path pattern | Example |
|-------|-------------|---------|
| Project thumbnail | `static/img/thumbs/project_{name}.jpeg` | `project_defidash.jpeg` |
| Post-specific image | `static/img/thumbs/{project}_{slug}.jpeg` | `defidash_preview-leverage.jpeg` |

### How to generate

```bash
# Project thumbnail
./scripts/generate-thumb.sh static/img/thumbs/project_myproject.jpeg "prompt here"

# With reference image (style transfer)
./scripts/generate-thumb.sh static/img/thumbs/output.jpeg "prompt here" static/img/thumbs/project_defidash.jpeg
```

### Prompt guidelines

- **Default style**: Modern, minimal icon/logo on a dark background (reference: `project_defidash.jpeg`)
- **Project thumbnails**: Clean project identity image — single letter or icon, bold color on dark bg
- **Post thumbnails**: Adapt to content topic (DeFi -> charts/finance, infra -> servers/architecture, etc.)
- Always: professional, clean, suitable as a 1:1 blog card thumbnail
- Do NOT include text unless it's a single letter or short acronym

### Environment

Requires `GEMINI_API_KEY` environment variable. The script will error if not set.

## 8. Image & Diagram Attribution

- 외부에서 가져온 다이어그램, 아키텍처 이미지, 도표 등에는 **반드시 출처(Reference)를 표기**한다.
- 이미지 바로 아래에 이탤릭체로 출처를 명시한다:
  ```markdown
  ![다이어그램 설명](image.png)
  *출처: [출처 제목](URL)*
  ```
- 직접 작성한 다이어그램이나 스크린샷에는 출처를 달지 않아도 된다.
- Prometheus 공식 로고 등 프로젝트 공식 에셋은 프로젝트명만 표기하면 충분하다.
