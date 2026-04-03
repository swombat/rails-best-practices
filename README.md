# Rails Best Practices Codex Plugin

This repository contains a local Codex plugin named `rails-best-practices` and a skill named `$rails-best-practices-importer`.

The plugin bundles:

- Campfire best-practice docs
- Fizzy best-practice docs
- a structured overlap catalog
- a generated combined menu
- a skill that helps Codex choose and import the right practices into a Rails app

The goal is simple: let Codex inspect a target Rails codebase, help you choose the right Campfire/Fizzy patterns, and then apply them as documentation, starter scaffolding, or guided patches.

## What Gets Installed

- Plugin: `rails-best-practices`
- Skill: `rails-best-practices-importer`
- Plugin manifest: `plugins/rails-best-practices/.codex-plugin/plugin.json`
- Repo-local marketplace entry: `.agents/plugins/marketplace.json`

The plugin is self-contained. The source docs are bundled inside the skill, so you do not need separate Campfire or Fizzy checkouts for normal use.

## Install Into A Specific Rails Repo

Use this option when you want the plugin available only inside one target Rails app.

From the target Rails repository:

```bash
mkdir -p plugins .agents/plugins
cp -R /path/to/rails-best-practices/plugins/rails-best-practices ./plugins/
cp /path/to/rails-best-practices/.agents/plugins/marketplace.json ./.agents/plugins/marketplace.json
```

After that, Codex should discover a local plugin named `rails-best-practices` in that repository.

## Install As A Home-Local Plugin

Use this option when you want the plugin available across multiple repositories.

```bash
mkdir -p ~/plugins ~/.agents/plugins
cp -R /path/to/rails-best-practices/plugins/rails-best-practices ~/plugins/
```

Then create or update `~/.agents/plugins/marketplace.json` so it contains an entry like this:

```json
{
  "name": "rails-best-practices-local",
  "interface": {
    "displayName": "Rails Best Practices"
  },
  "plugins": [
    {
      "name": "rails-best-practices",
      "source": {
        "source": "local",
        "path": "./plugins/rails-best-practices"
      },
      "policy": {
        "installation": "AVAILABLE",
        "authentication": "ON_INSTALL"
      },
      "category": "Developer Tools"
    }
  ]
}
```

If you already have a marketplace file, append the `rails-best-practices` entry instead of replacing the whole file.

## First Use

Start with the skill name explicitly:

```text
Use $rails-best-practices-importer to show the combined Campfire and Fizzy menu for this Rails app.
```

That tells Codex to:

- read the combined menu
- inspect the target Rails app
- resolve overlapping practices
- recommend a compatible import plan

## Best Use On A New Rails Codebase

For a greenfield or mostly-empty Rails app, use the skill as an architecture selector first, then as an implementation tool.

Recommended flow:

1. Ask for a stack recommendation.
2. Confirm the tenancy model.
3. Let Codex apply a starter bundle.
4. Refine with optional add-ons like Turbo, attachments, events, or form components.

Good prompts:

```text
Use $rails-best-practices-importer to recommend a stack for this new Rails app. It will be a multi-tenant SaaS with Hotwire and minimal JSON.
```

```text
Use $rails-best-practices-importer to implement the Fizzy SaaS bundle in this repository.
```

```text
Use $rails-best-practices-importer to set this up as a single-account collaboration app using the Campfire track.
```

```text
Use $rails-best-practices-importer to add the Hotwire UI bundle on top of the current greenfield setup.
```

For new apps, the most important early choice is tenancy:

- Campfire track: single-account or once-per-customer installs
- Fizzy track: multi-tenant SaaS with tenant-aware auth

Do not ask Codex to mix those two bootstraps.

## Best Use On An Existing Rails Codebase

For an existing app, the skill works best when used as a compatibility layer instead of a full rewrite tool.

Recommended flow:

1. Ask Codex to inspect the current stack.
2. Ask for a compatible subset of practices.
3. Apply one family or bundle at a time.
4. Keep auth, routing, views, and tests aligned within each change.

Good prompts:

```text
Use $rails-best-practices-importer to inspect this app and recommend which Campfire or Fizzy practices fit without rewriting the whole stack.
```

```text
Use $rails-best-practices-importer to add a better resource-controller structure and testing approach to this existing Rails app.
```

```text
Use $rails-best-practices-importer to compare the Campfire and Fizzy auth tracks against this repository and recommend only one.
```

```text
Use $rails-best-practices-importer to add Active Storage authorization and rich content patterns to this codebase.
```

For existing apps, ask Codex to preserve major choices already present in the codebase. Examples:

- keep Tailwind if the app already standardized on it
- keep Devise or another auth stack unless you explicitly want a migration
- translate the selected practice conceptually if the source implementation does not match the app

## Recommended Decision Order

When you use the skill, make decisions in this order:

1. Tenancy and auth
2. Controllers and routes
3. Realtime and collaboration depth
4. View layer and CSS strategy
5. Operational add-ons

That order avoids contradictory imports.

## What The Skill Knows How To Reconcile

The plugin includes a combined menu that maps overlap between Campfire and Fizzy across:

- auth and tenancy
- controllers and routes
- models and domain design
- views, CSS, and forms
- realtime and collaboration
- content, storage, and profiles
- jobs, events, and integrations
- testing
- portability and platform concerns

It classifies overlaps as:

- equivalent: largely the same idea, pick one canonical doc
- variant: choose one path
- complement: both can be imported together

## Regenerating The Combined Menu

If you update the catalog or bundled docs, regenerate the menu with:

```bash
ruby plugins/rails-best-practices/skills/rails-best-practices-importer/scripts/build_catalog.rb
```

## Source Of Truth

If you want to inspect or extend the plugin itself, the main files are:

- `plugins/rails-best-practices/.codex-plugin/plugin.json`
- `plugins/rails-best-practices/skills/rails-best-practices-importer/SKILL.md`
- `plugins/rails-best-practices/skills/rails-best-practices-importer/references/practice-catalog.json`
- `plugins/rails-best-practices/skills/rails-best-practices-importer/references/combined-menu.md`
- `plugins/rails-best-practices/skills/rails-best-practices-importer/references/import-workflow.md`

## Suggested Starting Prompt

If you are not sure where to start, use this:

```text
Use $rails-best-practices-importer to inspect this Rails app, show me the combined Campfire/Fizzy menu, and recommend the safest import plan.
```
