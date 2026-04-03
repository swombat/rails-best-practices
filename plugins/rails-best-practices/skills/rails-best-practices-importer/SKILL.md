---
name: rails-best-practices-importer
description: Use when the user wants to compare, choose, or import Rails best practices from the bundled Campfire and Fizzy references into a new or existing Rails app. This skill builds from a combined menu, resolves overlaps, and then applies the selected patterns as docs, starter scaffolding, or guided patches.
---

# Rails Best Practices Importer

## Overview

Use this skill to import selected Campfire and Fizzy Rails practices into the current repository. The source of truth is `references/practice-catalog.json`; the human-readable menu is `references/combined-menu.md`; the operating procedure is `references/import-workflow.md`.

If `references/combined-menu.md` is missing or stale, regenerate it with:

```bash
ruby scripts/build_catalog.rb
```

## Workflow

1. Read `references/combined-menu.md` and `references/import-workflow.md`.
2. Inspect the target Rails app before making recommendations or edits.
   - Read `Gemfile`, `config/routes.rb`, `app/models`, `app/controllers`, `app/views`, `app/javascript`, `app/assets`, tests, and schema or migrations that touch the selected area.
3. Resolve the smallest number of architectural choices needed to proceed.
   - If tenancy is unclear, ask one short question before changing auth.
   - Otherwise, prefer making a reasonable inference from the codebase instead of running a questionnaire.
4. Choose practices from the combined menu.
   - Pick one core auth track.
   - Pick one base controller document.
   - Pick one base view-layer document.
   - Add complementary practices only where the target app needs them.
5. Load only the selected source docs.
   - Do not load the entire Campfire or Fizzy corpus into context.
   - Use the `doc_path` values in `references/practice-catalog.json` to open the exact docs needed.
6. If deeper implementation reference is needed after the user selects a practice, use the source repos in this order:
   - bundled docs inside `references/bundled-docs/`
   - local checkouts at `~/dev/once-campfire` and `~/dev/fizzy` if present
   - official GitHub repos at `https://github.com/basecamp/once-campfire` and `https://github.com/basecamp/fizzy`
7. Apply the selected practices in the right mode.
   - `docs_only`: add or adapt docs and architectural notes inside the target repo.
   - `starter_scaffold`: shape a new or mostly-empty Rails app around the selected practices.
   - `guided_patch`: integrate the practices carefully into an existing app.
8. Finish with a concise summary that names the selected practice ids, the import mode used, and any unresolved variants.

## Core Rules

- Do not mix Campfire single-account bootstrap with Fizzy multi-tenant auth.
- Do not import both base controller docs or both base testing docs unless the user explicitly wants comparison material.
- Treat Campfire and Fizzy view-layer docs as overlapping philosophies; choose one as the main doctrine, then borrow details from the other only when useful.
- If the target app already standardized on Tailwind, ViewComponent, Phlex, Devise, or another major stack choice, translate the selected best practice conceptually instead of force-fitting the source implementation.
- For greenfield apps, add a short architecture decision note if the repository has no equivalent documentation yet.

## Resources

### references/

- `references/practice-catalog.json`: structured catalog of practices, families, overlaps, bundles, and doc paths.
- `references/combined-menu.md`: generated combined menu for quick browsing and user-facing selection.
- `references/import-workflow.md`: sequencing rules, compatibility guidance, and inspection checklist.

### scripts/

- `scripts/build_catalog.rb`: validates the catalog and regenerates `references/combined-menu.md`.

## Example Requests

- `Use $rails-best-practices-importer to show the combined menu and recommend a stack for this new Rails app.`
- `Use $rails-best-practices-importer to import the Fizzy SaaS bundle into this repository.`
- `Use $rails-best-practices-importer to compare Campfire and Fizzy auth practices and implement the single-account option.`
