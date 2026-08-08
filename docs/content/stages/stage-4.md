---
title: Stage 4 — Docs site
description: Hugo + GitHub Pages
weight: 40
---

## What it builds

- Hugo site in `docs/`
- GitHub Action deploys to Pages on push to `main`

## Local preview

```bash
cd docs
hugo server
# http://localhost:1313/test-net/
```

## Publish

```bash
git push origin main
```

Repo → **Settings → Pages → Source: GitHub Actions**.

Site: https://brandonwhitmire.github.io/test-net/
