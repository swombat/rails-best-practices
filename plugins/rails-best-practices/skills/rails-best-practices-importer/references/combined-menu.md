# Combined Rails Best Practices Menu

Generated from `references/practice-catalog.json`.

## Starter Bundles

### Mixed Rails Foundation (`mixed-foundation`)

A portable base for a fresh Rails app: domain-first models, small controllers, disciplined views, and integration-heavy tests.

Recommended for: new Rails apps that need a strong default architecture, teams that want a shared baseline before adding tenancy or realtime.

- `fizzy:domain-driven-design`: Domain-Driven Design
- `campfire:resourceful-controller-design`: Resourceful Controller Design
- `fizzy:concerns-for-organization`: Using Rails Concerns for Organization
- `campfire:view-layer-and-css`: View Layer and CSS
- `campfire:testing-philosophy`: Testing Philosophy

### Campfire Collaboration Stack (`campfire-collaboration`)

Single-account, collaboration-heavy Rails with memberships, realtime updates, rich content, and classic Rails primitives.

Recommended for: once-per-customer installations, shared inbox, chat, CRM, support, or workspace products.

- `campfire:authentication-and-current`: Authentication and Current Context
- `campfire:single-account-bootstrap`: Single-Account Bootstrap
- `campfire:resourceful-controller-design`: Resourceful Controller Design
- `campfire:memberships-and-room-architecture`: Memberships and Room Architecture
- `campfire:realtime-with-hotwire-and-action-cable`: Realtime with Hotwire and Action Cable
- `campfire:rich-content-and-attachments`: Rich Content and Attachments
- `campfire:background-jobs-and-integrations`: Background Jobs and Integrations
- `campfire:view-layer-and-css`: View Layer and CSS
- `campfire:testing-philosophy`: Testing Philosophy

### Fizzy SaaS Stack (`fizzy-saas`)

Multi-tenant Rails with passwordless auth, tenant-aware authorization, hybrid controllers, operational patterns, and Rails-first UI.

Recommended for: greenfield SaaS products, multi-account apps that need structured auth and portability.

- `fizzy:authentication-spec`: Passwordless Authentication Architecture
- `fizzy:multi-tenant-authentication`: Multi-Tenant Authentication and Authorization
- `fizzy:restful-resource-design`: RESTful Resource Design
- `fizzy:hybrid-resource-controllers`: Hybrid Resource Controllers
- `fizzy:domain-driven-design`: Domain-Driven Design
- `fizzy:active-storage-authorization`: Active Storage Authorization
- `fizzy:event-sourcing-and-activity`: Event Sourcing and Activity Tracking
- `fizzy:platform-aware-rails`: Platform-Aware Rails
- `fizzy:testing-philosophy`: Testing Philosophy

### Hotwire UI Layer (`hotwire-ui`)

Server-rendered UI patterns for teams that want strong partials, custom CSS, form components, and pragmatic Turbo usage.

Recommended for: HTML-first Rails apps, teams standardizing on ERB, Stimulus, and custom CSS.

- `campfire:view-layer-and-css`: View Layer and CSS
- `fizzy:view-layer-philosophy`: View Layer Philosophy
- `fizzy:modern-css-architecture`: Modern CSS Architecture Without a Build Step
- `fizzy:form-components`: Professional Form Components in Rails
- `fizzy:turbo-patterns`: Turbo and Hotwire Patterns

### Operations and Portability (`operations-and-portability`)

Operational patterns for background work, events, exports, platform awareness, and production-oriented Rails concerns.

Recommended for: apps integrating with external systems, teams that need exports, notifications, or platform-sensitive behavior.

- `campfire:background-jobs-and-integrations`: Background Jobs and Integrations
- `fizzy:event-sourcing-and-activity`: Event Sourcing and Activity Tracking
- `fizzy:advanced-rails-patterns`: Advanced Rails Patterns
- `fizzy:account-data-transfer`: Structured Account Data Transfer
- `fizzy:platform-aware-rails`: Platform-Aware Rails

## Decision Axes

### Is the application single-account or multi-tenant? (`tenancy`)

This decides the core auth and tenant model, and it is the one branch that should not be merged casually.

- `single_account`: Single-account or once-per-customer. Default practices: campfire:authentication-and-current, campfire:single-account-bootstrap. Bundle: `campfire-collaboration`
- `multi_tenant`: Multi-tenant SaaS. Default practices: fizzy:authentication-spec, fizzy:multi-tenant-authentication. Bundle: `fizzy-saas`

### Will the app serve mostly HTML, or HTML plus Turbo Streams and JSON endpoints from the same resources? (`response_surface`)

This decides whether the base controller guidance is enough or whether hybrid resource controllers should be part of the initial shape.

- `html_first`: Mostly HTML resources. Default practices: campfire:resourceful-controller-design, fizzy:restful-resource-design
- `html_turbo_json`: HTML plus Turbo and JSON. Default practices: fizzy:hybrid-resource-controllers, fizzy:turbo-patterns

### Does the app need presence, unread state, or live multi-user collaboration? (`collaboration`)

Campfire's collaboration documents are strongest when the app behaves like a shared workspace instead of a classic CRUD app.

- `standard_crud`: No heavy live collaboration. Default practices: fizzy:turbo-patterns
- `live_collaboration`: Live collaboration and per-user state. Default practices: campfire:memberships-and-room-architecture, campfire:realtime-with-hotwire-and-action-cable

### Will the project use deliberate server-rendered UI with custom CSS, or does it already have a separate design system or Tailwind stack? (`frontend`)

Both source projects lean on ERB, helpers, Stimulus, and custom CSS; that philosophy transfers well, but CSS architecture should not be copied blindly into a repo that already standardized on another stack.

- `custom_css`: Server-rendered UI with custom CSS. Default practices: campfire:view-layer-and-css, fizzy:modern-css-architecture, fizzy:form-components. Bundle: `hotwire-ui`
- `existing_design_system`: Existing Tailwind or component system. Default practices: campfire:view-layer-and-css, fizzy:view-layer-philosophy

## Combined Menu

### Auth and Tenancy (`auth-and-tenancy`)

Selection mode: `choose_one_core_track`.

Choose exactly one core tenancy track. Campfire is intentionally single-account and session-centric. Fizzy is intentionally multi-tenant and tenant-aware. Do not import both bootstraps into the same app.

- `campfire:authentication-and-current` (campfire): Cookie-backed sessions, narrow Current usage, and signed-link patterns for single-account apps. Best for: single-account applications, request-scoped authentication context, session-centric Rails auth. Import: docs_only, starter_scaffold, guided_patch. Kind: `portable_plus_notes`. Doc: `references/bundled-docs/campfire-best-practices/best-practices/authentication-and-current.md`
- `campfire:single-account-bootstrap` (campfire): Explicit bootstrap flow for apps that are installed once per customer or run as one shared account. Best for: once-per-customer installs, single-tenant products, greenfield app setup. Import: docs_only, starter_scaffold. Kind: `portable_plus_notes`. Doc: `references/bundled-docs/campfire-best-practices/best-practices/single-account-bootstrap.md`
- `fizzy:authentication-spec` (fizzy): Passwordless auth architecture with sessions, tokens, and tenant-aware authorization boundaries. Best for: multi-tenant SaaS, magic links or passkeys, session and token auth. Import: docs_only, starter_scaffold, guided_patch. Kind: `portable_plus_notes`. Doc: `references/bundled-docs/fizzy-best-practices/best-practices/authentication-spec.md`
- `fizzy:multi-tenant-authentication` (fizzy): Identity, membership, tenant resolution, and layered authorization for multi-tenant Rails apps. Best for: account memberships, tenant switching, B2B SaaS authorization. Import: docs_only, starter_scaffold, guided_patch. Kind: `portable_plus_notes`. Doc: `references/bundled-docs/fizzy-best-practices/best-practices/multi-tenant-authentication.md`

Overlap guidance:
- `variant`: campfire:authentication-and-current, fizzy:authentication-spec. Both define the core auth stack. Campfire assumes cookie-backed sessions for a single-account app. Fizzy assumes passwordless auth in a multi-tenant system.
- `variant`: campfire:single-account-bootstrap, fizzy:multi-tenant-authentication. These are mutually exclusive starting points. Choose Campfire for single-account installs and Fizzy for account membership systems.
- `complement`: fizzy:authentication-spec, fizzy:multi-tenant-authentication. These two Fizzy docs are meant to travel together.

### Controllers and Routes (`controllers-and-routes`)

Selection mode: `choose_one_base_plus_optional_extensions`.

Pick one base resource-controller philosophy, then layer in hybrid responses only if the app truly serves HTML, Turbo Streams, and JSON from the same resources.

- `campfire:resourceful-controller-design` (campfire): Small controllers and noun-based routes built around resources instead of ad hoc verbs. Best for: HTML-first applications, clean controller boundaries, new app scaffolding. Import: docs_only, starter_scaffold, guided_patch. Kind: `portable_plus_notes`. Doc: `references/bundled-docs/campfire-best-practices/best-practices/resourceful-controller-design.md`
- `fizzy:restful-resource-design` (fizzy): CRUD-oriented resource design that keeps controllers small by modeling endpoints as nouns. Best for: controller discipline, route design, HTML-first Rails apps. Import: docs_only, starter_scaffold, guided_patch. Kind: `portable_reference`. Doc: `references/bundled-docs/fizzy-best-practices/best-practices/restful-resource-design.md`
- `fizzy:hybrid-resource-controllers` (fizzy): Serve HTML, Turbo Stream, and JSON from the same resource controller without fragmenting the domain. Best for: Turbo plus JSON, HTML-first APIs, shared resource workflows. Import: docs_only, starter_scaffold, guided_patch. Kind: `portable_plus_notes`. Doc: `references/bundled-docs/fizzy-best-practices/best-practices/hybrid-resource-controllers.md`

Overlap guidance:
- `equivalent`: campfire:resourceful-controller-design, fizzy:restful-resource-design. These are strongly aligned. Choose one canonical controller doc to avoid duplicate doctrine.
- `complement`: fizzy:hybrid-resource-controllers, campfire:resourceful-controller-design. Hybrid controllers are an extension of the base resourceful pattern, not a replacement for it.

### Models and Domain (`models-and-domain`)

Selection mode: `mix_and_match`.

These documents mostly compose well. Use domain-driven design and concerns as the foundation, then add state, callbacks, or delegated types where the domain calls for them.

- `campfire:model-organization-with-concerns` (campfire): Trait-based concerns and small collaborators for large Active Record models. Best for: growing models, shared traits, avoiding service-object sprawl. Import: docs_only, guided_patch. Kind: `portable_plus_notes`. Doc: `references/bundled-docs/campfire-best-practices/best-practices/model-organization-with-concerns.md`
- `fizzy:concerns-for-organization` (fizzy): Use concerns as real traits and organizational units instead of dumping behavior into services. Best for: large models, trait extraction, organization without indirection. Import: docs_only, guided_patch. Kind: `portable_reference`. Doc: `references/bundled-docs/fizzy-best-practices/best-practices/concerns-for-organization.md`
- `fizzy:domain-driven-design` (fizzy): Put the domain model at the center of the app and let controllers and views stay thin around it. Best for: greenfield architecture, rich business domains, moving logic out of controllers. Import: docs_only, starter_scaffold, guided_patch. Kind: `portable_reference`. Doc: `references/bundled-docs/fizzy-best-practices/best-practices/domain-driven-design.md`
- `fizzy:state-modeling-with-records` (fizzy): Model optional or significant state with associated records when booleans stop carrying enough meaning. Best for: stateful workflows, optional capabilities, audit-friendly modeling. Import: docs_only, starter_scaffold, guided_patch. Kind: `portable_reference`. Doc: `references/bundled-docs/fizzy-best-practices/best-practices/state-modeling-with-records.md`
- `fizzy:callbacks-done-right` (fizzy): A pragmatic callback discipline: use them when they fit the lifecycle, not as hidden service layers. Best for: lifecycle-driven model logic, active record events, cleanup of callback-heavy code. Import: docs_only, guided_patch. Kind: `portable_reference`. Doc: `references/bundled-docs/fizzy-best-practices/best-practices/callbacks-done-right.md`
- `fizzy:delegated-types-pattern` (fizzy): Use delegated types when several content variants share operational behavior but need distinct internals. Best for: polymorphic content systems, shared feeds, content-oriented domains. Import: docs_only, starter_scaffold, guided_patch. Kind: `portable_reference`. Doc: `references/bundled-docs/fizzy-best-practices/best-practices/delegated-types-pattern.md`

Overlap guidance:
- `equivalent`: campfire:model-organization-with-concerns, fizzy:concerns-for-organization. These are the same organizational instinct from two codebases. Pick one as the main concern doctrine.

### Views, CSS, and Forms (`views-css-and-forms`)

Selection mode: `choose_one_base_view_doc_plus_optional_layers`.

Choose one base view philosophy doc, then add CSS architecture and form components if the target app wants a custom server-rendered UI system.

- `campfire:view-layer-and-css` (campfire): Partials, helpers, Stimulus wiring, and custom CSS as the main server-rendered UI stack. Best for: ERB-first applications, custom CSS, Stimulus-enhanced UI. Import: docs_only, starter_scaffold, guided_patch. Kind: `portable_plus_notes`. Doc: `references/bundled-docs/campfire-best-practices/best-practices/view-layer-and-css.md`
- `fizzy:view-layer-philosophy` (fizzy): Partials and helpers as the default Rails view abstraction, with presenter objects as the rare exception. Best for: server-rendered views, helper discipline, ERB composition. Import: docs_only, starter_scaffold, guided_patch. Kind: `portable_reference`. Doc: `references/bundled-docs/fizzy-best-practices/best-practices/view-layer-philosophy.md`
- `fizzy:modern-css-architecture` (fizzy): Layered custom CSS architecture for Rails without Tailwind, Sass, or a CSS build step. Best for: Propshaft and importmap apps, custom CSS systems, build-step avoidance. Import: docs_only, starter_scaffold, guided_patch. Kind: `portable_reference`. Doc: `references/bundled-docs/fizzy-best-practices/best-practices/modern-css-architecture.md`
- `fizzy:form-components` (fizzy): Consistent, accessible form components built with CSS custom properties and Stimulus behaviors. Best for: design systems, form-heavy Rails apps, progressive enhancement. Import: docs_only, starter_scaffold, guided_patch. Kind: `portable_reference`. Doc: `references/bundled-docs/fizzy-best-practices/best-practices/form-components.md`

Overlap guidance:
- `equivalent`: campfire:view-layer-and-css, fizzy:view-layer-philosophy. Both push toward partials, helpers, Stimulus, and restraint. Use one as the base doctrine and draw examples from the other if needed.
- `complement`: fizzy:modern-css-architecture, fizzy:form-components. Form components sit naturally on top of the CSS architecture.

### Realtime and Collaboration (`realtime-and-collaboration`)

Selection mode: `choose_depth_of_realtime`.

Choose Campfire when the app needs collaboration objects, membership boundaries, presence, or unread state. Choose Fizzy when the app mostly needs reusable Turbo patterns without the full collaboration domain.

- `campfire:memberships-and-room-architecture` (campfire): Collaboration architecture built around first-class membership records and per-user state. Best for: chat and inbox products, per-user unread state, collaboration boundaries. Import: docs_only, starter_scaffold, guided_patch. Kind: `portable_plus_notes`. Doc: `references/bundled-docs/campfire-best-practices/best-practices/memberships-and-room-architecture.md`
- `campfire:realtime-with-hotwire-and-action-cable` (campfire): Live collaboration patterns that separate persisted HTML updates from ephemeral signals. Best for: presence, unread state, collaboration-heavy interfaces. Import: docs_only, starter_scaffold, guided_patch. Kind: `portable_plus_notes`. Doc: `references/bundled-docs/campfire-best-practices/best-practices/realtime-with-hotwire-and-action-cable.md`
- `fizzy:turbo-patterns` (fizzy): Reusable Turbo patterns for real-time Rails UIs, multi-session updates, and light abstraction. Best for: Turbo streams, live UI updates, HTML-first realtime. Import: docs_only, starter_scaffold, guided_patch. Kind: `portable_reference`. Doc: `references/bundled-docs/fizzy-best-practices/best-practices/turbo-patterns.md`

Overlap guidance:
- `variant_or_complement`: campfire:realtime-with-hotwire-and-action-cable, fizzy:turbo-patterns. Campfire is the stronger collaboration-system reference. Fizzy is the stronger generic Turbo pattern catalog. They can complement each other, but Campfire should anchor live collaboration apps.
- `complement`: campfire:memberships-and-room-architecture, campfire:realtime-with-hotwire-and-action-cable. These two Campfire docs usually travel together.

### Content, Storage, and Profiles (`content-storage-and-profiles`)

Selection mode: `mix_and_match`.

These practices generally compose well. Rich content, attachment authorization, and profile handling solve adjacent concerns and can be imported together.

- `campfire:rich-content-and-attachments` (campfire): Canonical rich-body modeling, attachment safety, and projection-friendly content handling. Best for: Action Text, attachments, user-authored content. Import: docs_only, starter_scaffold, guided_patch. Kind: `portable_plus_notes`. Doc: `references/bundled-docs/campfire-best-practices/best-practices/rich-content-and-attachments.md`
- `fizzy:active-storage-authorization` (fizzy): Authorize files through the records that own them instead of ad hoc blob whitelists. Best for: private attachments, variants, record-owned authorization. Import: docs_only, starter_scaffold, guided_patch. Kind: `portable_plus_notes`. Doc: `references/bundled-docs/fizzy-best-practices/best-practices/active-storage-authorization.md`
- `fizzy:user-profiles-and-avatars` (fizzy): Profiles, avatars, preferences, theming, and user-boundary decisions around personal data. Best for: profile pages, avatar handling, user preferences. Import: docs_only, starter_scaffold, guided_patch. Kind: `portable_reference`. Doc: `references/bundled-docs/fizzy-best-practices/best-practices/user-profiles-and-avatars.md`

### Jobs, Events, and Integrations (`jobs-events-and-integrations`)

Selection mode: `mix_and_match`.

Campfire's job discipline and Fizzy's event and advanced operational patterns complement each other well.

- `campfire:background-jobs-and-integrations` (campfire): Thin jobs, explicit integration boundaries, and clear failure behavior. Best for: webhooks, notifications, third-party APIs. Import: docs_only, guided_patch. Kind: `portable_plus_notes`. Doc: `references/bundled-docs/campfire-best-practices/best-practices/background-jobs-and-integrations.md`
- `fizzy:event-sourcing-and-activity` (fizzy): A single event model for feeds, notifications, webhooks, and audit-style activity. Best for: activity feeds, webhooks, notifications, audit trails. Import: docs_only, starter_scaffold, guided_patch. Kind: `portable_reference`. Doc: `references/bundled-docs/fizzy-best-practices/best-practices/event-sourcing-and-activity.md`
- `fizzy:advanced-rails-patterns` (fizzy): Production-grade patterns for jobs, storage, search, notifications, webhooks, and related operational concerns. Best for: mature applications, production hardening, operational Rails features. Import: docs_only, guided_patch. Kind: `mixed_reference`. Doc: `references/bundled-docs/fizzy-best-practices/best-practices/advanced-rails-patterns.md`

### Testing (`testing`)

Selection mode: `choose_one_canonical_doc`.

Both testing docs are closely aligned. Pick one as the canonical testing reference and only pull the second if you need concrete examples from both codebases.

- `campfire:testing-philosophy` (campfire): Integration-heavy Rails testing with focused browser coverage and real-stack confidence. Best for: Minitest suites, request and integration tests, greenfield testing doctrine. Import: docs_only, guided_patch. Kind: `portable_plus_notes`. Doc: `references/bundled-docs/campfire-best-practices/best-practices/testing-philosophy.md`
- `fizzy:testing-philosophy` (fizzy): Integration-heavy Rails testing with selective smaller tests for dense domain logic. Best for: Minitest and RSpec teams alike, real-stack confidence, pragmatic system testing. Import: docs_only, guided_patch. Kind: `portable_plus_notes`. Doc: `references/bundled-docs/fizzy-best-practices/best-practices/testing-philosophy.md`

Overlap guidance:
- `equivalent`: campfire:testing-philosophy, fizzy:testing-philosophy. The testing philosophy is nearly identical across both projects.

### Portability and Platform (`portability-and-platform`)

Selection mode: `optional_add_ons`.

These Fizzy practices are specialized operational add-ons. Pull them only if the target app needs exports, imports, platform detection, or request-context features.

- `fizzy:account-data-transfer` (fizzy): Ordered export and import of account data using record groups and manifests. Best for: account migrations, exports, customer portability. Import: docs_only, starter_scaffold, guided_patch. Kind: `portable_plus_notes`. Doc: `references/bundled-docs/fizzy-best-practices/best-practices/account-data-transfer.md`
- `fizzy:platform-aware-rails` (fizzy): Treat request metadata, timezone, and client platform as first-class Rails inputs. Best for: mobile or bridge clients, timezone-sensitive UX, platform-specific feature flags. Import: docs_only, starter_scaffold, guided_patch. Kind: `portable_plus_notes`. Doc: `references/bundled-docs/fizzy-best-practices/best-practices/platform-aware-rails.md`
