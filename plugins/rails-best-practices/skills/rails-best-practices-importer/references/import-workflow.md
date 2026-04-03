# Import Workflow

Use this workflow when the user wants to choose or import best practices from Campfire and Fizzy into a target Rails application.

## Decision Order

Make the architectural decisions in this order:

1. Tenancy: single-account Campfire track or multi-tenant Fizzy track.
2. Response surface: plain resourceful HTML or hybrid HTML/Turbo/JSON controllers.
3. Collaboration depth: standard CRUD, generic Turbo patterns, or full collaboration primitives.
4. Frontend style: carry over the server-rendered view philosophy only, or also import the custom CSS and form-component stack.
5. Operational add-ons: attachments, events, exports, platform awareness, or richer content.

If the user has not specified tenancy, ask one short question before making auth changes. That branch is the least safe to infer.

## Import Modes

- `docs_only`: add or adapt docs inside the target repository and stop short of broad code changes.
- `starter_scaffold`: establish initial structure for a fresh or mostly-empty Rails app.
- `guided_patch`: patch an existing app carefully after inspecting its current routes, models, views, tests, and dependencies.

Default mode:

- New or mostly-empty Rails app: prefer `starter_scaffold`.
- Existing app with meaningful code already present: prefer `guided_patch`.
- User asks for guidance or a comparison only: use `docs_only`.

## Safe Mixing Rules

- Choose exactly one core auth track.
  - Campfire: `authentication-and-current` plus `single-account-bootstrap`
  - Fizzy: `authentication-spec` plus `multi-tenant-authentication`
- Choose one base controller document.
  - Campfire `resourceful-controller-design`
  - Fizzy `restful-resource-design`
- Add `hybrid-resource-controllers` only if the same resource really serves HTML, Turbo Streams, and JSON.
- Choose one base view-layer document.
  - Campfire `view-layer-and-css`
  - Fizzy `view-layer-philosophy`
- `modern-css-architecture` and `form-components` are implementation layers, not replacements for the base view philosophy.
- `realtime-with-hotwire-and-action-cable` and `memberships-and-room-architecture` usually travel together.
- `rich-content-and-attachments` pairs well with `active-storage-authorization`.
- Choose one canonical testing document. Both testing docs are nearly equivalent.

## Target App Inspection

Inspect these files before making code changes:

- `Gemfile`
- `config/routes.rb`
- `app/models/**/*`
- `app/controllers/**/*`
- `app/views/**/*`
- `app/javascript/**/*`
- `app/assets/**/*`
- `test/**/*` or `spec/**/*`
- `db/schema.rb` or recent migrations when the selected practices affect data modeling

Look for these signals:

- Existing auth stack: `devise`, `sorcery`, custom session code, passkeys, magic links
- Tenancy model: `Account`, `Organization`, `Workspace`, `Membership`, `Current.account`
- Frontend stack: Tailwind, ViewComponent, Phlex, custom CSS, Importmap, Stimulus
- Realtime stack: Action Cable channels, Turbo Streams, presence or unread models
- Content stack: Action Text, Active Storage, background jobs, webhook endpoints

If the target app already standardized on another framework or library, preserve the existing choice and translate the selected best practice conceptually instead of force-fitting the source stack.

## Using Source Repos

The catalog is bundled with doc paths. If you need deeper implementation reference after the user picks a practice, use this order:

1. Bundled docs inside the skill.
2. Local source checkouts if they exist.
3. Official GitHub source repositories.

Local checkouts:

- `~/dev/once-campfire`
- `~/dev/fizzy`

Official GitHub source repositories:

- `https://github.com/basecamp/once-campfire`
- `https://github.com/basecamp/fizzy`

Search narrowly. Do not read those codebases wholesale unless the task truly requires it.

## Delivery

When you apply practices to a target app:

- Name the selected practices by id in the final summary.
- Call out any variants the user did not choose.
- For greenfield apps, add a short architecture decision note if the repo has no equivalent documentation yet.
- Keep patches cohesive: auth, routing, views, and tests should land together when they are part of one selected practice bundle.
