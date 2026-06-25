# Spec Versioning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add semantic-release automation so `info.version` in `openapi/openapi.yaml` is bumped automatically on every push to `main`, matching the release pattern used by `homelab-api` and `homelab-cli`.

**Architecture:** `cycjimmy/semantic-release-action@v6` (same action as sibling repos) runs in a GitHub Actions `release` workflow. Two extra plugins are added via `extra_plugins`: `@semantic-release/exec` patches `info.version` before tagging, and `@semantic-release/git` commits the changed file back. `CLAUDE.md` and `API_GUIDELINES.md` get versioning sections documenting the commit conventions.

**Tech Stack:** semantic-release, `cycjimmy/semantic-release-action@v6`, `@semantic-release/exec`, `@semantic-release/git`, GitHub Actions.

---

### Task 1: Add `.releaserc.json`

**Files:**
- Create: `.releaserc.json`

- [ ] **Step 1: Create `.releaserc.json`**

  Create `.releaserc.json` at the repo root:

  ```json
  {
    "branches": ["main"],
    "plugins": [
      "@semantic-release/commit-analyzer",
      "@semantic-release/release-notes-generator",
      ["@semantic-release/exec", {
        "prepareCmd": "sed -i 's/^  version: .*/  version: ${nextRelease.version}/' openapi/openapi.yaml"
      }],
      ["@semantic-release/git", {
        "assets": ["openapi/openapi.yaml"],
        "message": "chore(release): ${nextRelease.version} [skip ci]"
      }],
      "@semantic-release/github"
    ]
  }
  ```

  The `sed -i` (no empty string) is Linux/GitHub Actions syntax. The pattern `^  version: ` targets the two-space-indented `version:` field under `info:` in `openapi.yaml` — the only field at that indent level.

- [ ] **Step 2: Verify JSON is valid**

  ```bash
  python3 -m json.tool .releaserc.json
  ```

  Expected: the JSON is printed without errors.

- [ ] **Step 3: Commit**

  ```bash
  git add .releaserc.json
  git commit -m "chore: add semantic-release config"
  ```

---

### Task 2: Add release GitHub Actions workflow

**Files:**
- Create: `.github/workflows/release.yaml`

- [ ] **Step 1: Create `.github/workflows/release.yaml`**

  ```yaml
  name: release

  on:
    push:
      branches:
        - main

  jobs:
    lint:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v4
        - uses: actions/setup-node@v4
          with:
            node-version: "20"
        - name: Lint
          run: make lint

    semantic:
      runs-on: ubuntu-latest
      needs: lint
      permissions:
        contents: write
      steps:
        - uses: actions/checkout@v4
          with:
            fetch-depth: 0
        - uses: actions/setup-node@v4
          with:
            node-version: "24"
        - name: Semantic Release
          uses: cycjimmy/semantic-release-action@v6
          with:
            extra_plugins: |
              @semantic-release/exec
              @semantic-release/git
          env:
            GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
  ```

  Notes:
  - `lint` job runs `make lint` as a gate before releasing — matches the existing `lint.yaml` workflow jobs.
  - `semantic` requires `contents: write` so `@semantic-release/git` can push the version bump commit back to `main`.
  - `fetch-depth: 0` is required by semantic-release to read the full git history for version calculation.
  - Node 20 for lint (matches `lint.yaml`), Node 24 for semantic-release (matches sibling repos).

- [ ] **Step 2: Verify the workflow file is valid YAML**

  ```bash
  python3 -c "import yaml, sys; yaml.safe_load(open('.github/workflows/release.yaml'))" && echo "valid"
  ```

  Expected: `valid`

- [ ] **Step 3: Verify lint still passes**

  ```bash
  make lint
  ```

  Expected: exits 0 with no errors.

- [ ] **Step 4: Commit**

  ```bash
  git add .github/workflows/release.yaml
  git commit -m "ci: add semantic-release workflow"
  ```

---

### Task 3: Update `CLAUDE.md` with versioning section

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add a `## Versioning` section to `CLAUDE.md`**

  Append the following section after the `## Lint pipeline` section:

  ```markdown
  ## Versioning

  The spec uses semantic-release. On every push to `main`, the release workflow
  analyzes commits, determines the next SemVer, patches `info.version` in
  `openapi/openapi.yaml`, commits the change back, and creates a GitHub release.

  ### Commit conventions

  | Change type | Commit prefix | Version bump |
  |---|---|---|
  | Description or example fix | `fix:` | patch |
  | New endpoint or new optional field | `feat:` | minor |
  | Change oasdiff flags as breaking | `feat!:` or `BREAKING CHANGE` footer | major |

  ### `BREAKING CHANGE` rule

  Use the `BREAKING CHANGE` footer (or `!` shorthand) **only when `make breaking`
  / oasdiff reports a breaking change**. oasdiff already ignores endpoints
  annotated with `x-stability-level: draft`, so no manual filtering is needed.
  If oasdiff is silent, no breaking change footer is needed.

  All current endpoints carry `x-stability-level: draft`. No breaking changes
  are expected until an endpoint graduates to `x-stability-level: stable`.

  ### `info.version` is managed automatically

  Do not edit `info.version` in `openapi/openapi.yaml` by hand. It is patched
  by semantic-release on each release.
  ```

- [ ] **Step 2: Verify lint still passes**

  ```bash
  make lint
  ```

  Expected: exits 0 with no errors.

- [ ] **Step 3: Commit**

  ```bash
  git add CLAUDE.md
  git commit -m "docs: add versioning conventions to CLAUDE.md"
  ```

---

### Task 4: Update `API_GUIDELINES.md` with versioning section

**Files:**
- Modify: `API_GUIDELINES.md`

- [ ] **Step 1: Add a `## Versioning` section to `API_GUIDELINES.md`**

  Append the following section at the end of the file:

  ```markdown
  ## Versioning

  The spec version follows [Semantic Versioning](https://semver.org/) and is
  managed by semantic-release. Use these commit prefixes when changing the spec:

  | Change type | Commit prefix | Version bump |
  |---|---|---|
  | Description or example fix | `fix:` | patch |
  | New endpoint or new optional field | `feat:` | minor |
  | Change oasdiff flags as breaking | `feat!:` or `BREAKING CHANGE` footer | major |

  Use `BREAKING CHANGE` only when oasdiff confirms a breaking change. oasdiff
  ignores `x-stability-level: draft` endpoints automatically.
  ```

- [ ] **Step 2: Verify lint still passes**

  ```bash
  make lint
  ```

  Expected: exits 0 with no errors.

- [ ] **Step 3: Commit**

  ```bash
  git add API_GUIDELINES.md
  git commit -m "docs: add versioning conventions to API_GUIDELINES.md"
  ```
