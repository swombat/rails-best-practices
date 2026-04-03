# Structured Account Data Transfer

This document describes a portable pattern for exporting and importing a tenant or account as a structured archive. The core idea is to treat data transfer as an ordered set of record groups, not one giant serializer.

This pattern is useful when you need:

- inspectable exports
- resumable imports
- strict integrity checks
- support for attachments or rich text
- a clean way to add new models over time

## Why Not Use One Giant Serializer

Monolithic export code often starts simple and ends brittle.

Common failure modes:

- hidden dependency ordering
- custom handling scattered across one huge object
- no clean place to validate one slice of the archive
- poor support for resumable imports
- hard-to-reason-about polymorphic or attachment data

The better pattern is to split the archive into ordered units of work.

## The Core Objects

### Export

The export object should stay thin.

Its job is usually:

1. open the archive
2. ask a manifest which record sets to export
3. let each record set write its own slice

### Manifest

The manifest is the dependency-ordered list of record sets.

That ordering is the whole point. Parents and supporting records are transferred before dependents.

Representative order:

- account or workspace metadata
- users and settings
- projects, boards, lists, tags
- memberships and access rules
- primary business records such as tasks, comments, and assignments
- state records such as closures or publications
- events, notifications, deliveries
- rich text, blobs, attachments, and binary files

The manifest becomes a readable statement of transfer dependencies.

## Record Sets Are the Unit of Work

Each record set should own one table or one coherent slice of data.

Representative interface:

```ruby
class DataTransfer::RecordSet
  def export(archive)
  end

  def import(archive)
  end

  def check(archive)
  end
end
```

A record set should answer:

- which records it owns
- where they live in the archive
- which attributes are required
- which integrity checks apply
- whether special import or export behavior is needed

This keeps the transfer logic composable instead of monolithic.

## A Simple Archive Shape Works Well

A strong default is one JSON file per record:

```text
data/tasks/<id>.json
data/comments/<id>.json
data/events/<id>.json
```

That makes the export:

- easy to inspect
- easy to diff
- easy to resume from

Specialized record sets can override that when needed.

Example:

- one singleton metadata file such as `data/account.json`
- one binary directory for exported files

## Import Should Be Fast, But Still Explicit

Imports often benefit from batched writes such as `insert_all!`, but the process should remain understandable.

Useful import behavior:

- force imported rows onto the target tenant
- rewrite timestamps such as `updated_at` when appropriate
- support resuming from a file marker or checkpoint
- allow a callback to report progress

This keeps imports operationally practical without hiding the underlying data model.

## Integrity Checking Should Happen Before Writes

Do not treat the archive as trustworthy input.

Useful checks include:

- file name ID matches JSON ID
- required attributes are present
- referenced parent records exist in the archive or target system
- records do not already collide in unsafe ways
- polymorphic types are limited to a known allowlist

The transfer format is only valuable if malformed or conflicting archives fail loudly and early.

## Let the Manifest Own the Importable Model List

One subtle but important detail: the manifest should define the closed world of importable model types.

Why:

- polymorphic associations should not trust arbitrary type strings from the archive
- every importable model should have an explicit place in the dependency order
- new models become visible in one central list

This prevents the archive from smuggling in unexpected types.

## Specialized Record Sets Handle the Hard Cases

Keep the base record-set behavior intentionally small. Use specialized subclasses for cases that need custom logic.

Common examples:

- singleton metadata
- Action Text rich text
- Active Storage blobs
- Active Storage attachments
- exported binary files
- settings or configuration objects with unusual paths

That creates the right split:

- generic JSON-record behavior in the base class
- format-specific behavior in dedicated subclasses

## Testing Guidance

Useful tests for this pattern:

- each record set exports the expected archive paths
- `check` fails on malformed data before `import` writes anything
- dependency ordering is correct
- imports are idempotent or fail clearly when duplicates are not allowed
- specialized record sets correctly handle blobs, files, and rich text

End-to-end export/import tests are still important, but they should sit on top of well-tested record-set behavior.

## When to Use a Simpler Approach

You may not need this architecture when:

- the export covers only one or two tables
- imports are not supported
- the archive will never need to be inspected or resumed

For simple one-way exports, a smaller serializer may be enough.

## Practical Guidance

- Make the export object thin.
- Put dependency ordering in a manifest.
- Make each record set own one slice of data.
- Keep validation strict.
- Add specialized record sets only when the data truly needs custom handling.

## Fizzy Notes

Fizzy currently uses this pattern for full account export and import. Its transfer system is built around a manifest plus ordered record sets, with dedicated handling for rich text, Active Storage, and exported binary files.
