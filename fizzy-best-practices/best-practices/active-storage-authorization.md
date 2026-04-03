# Active Storage Authorization

This document describes a portable pattern for securing Active Storage attachments in Rails. The core idea is that file authorization should come from the record that owns the attachment, not from a separate whitelist buried in file-serving code.

If you apply this pattern in another repository, start with the generic sections below and treat `Fizzy Notes` as one implementation example.

## The Core Idea

Authorization belongs to the owning record.

That means:

- blobs ask their attachments whether the current actor can access them
- attachments delegate access checks to the attached record
- records expose a small authorization API such as `accessible_to?`
- records optionally expose `publicly_accessible?` when some files are intentionally public

This keeps the rules close to the domain and stops file-serving endpoints from becoming a second, inconsistent authorization system.

## Why the Default Setup Is Often Not Enough

Out of the box, Active Storage is good at serving files. It is not opinionated enough about your domain's access rules.

That becomes a problem when:

- some attachments inherit access from a private parent record
- some files are public and should be cacheable
- some files are owner-only downloads
- rich text embeds and variants must follow the same rules as direct attachments

Without a coherent pattern, teams often end up with private records but effectively public attachments.

## Extend Blobs and Attachments, Not Just Controllers

A useful abstraction is to teach the storage objects two questions:

- `accessible_to?(actor)`
- `publicly_accessible?`

Conceptually:

```ruby
blob.accessible_to?(user)
blob.publicly_accessible?

attachment.accessible_to?(user)
attachment.publicly_accessible?
```

Those answers should come from the attached record.

Representative shape:

```ruby
class ActiveStorage::Attachment
  def accessible_to?(actor)
    record.accessible_to?(actor)
  end

  def publicly_accessible?
    record.publicly_accessible?
  end
end
```

That keeps the controllers thin and the domain rules centralized.

## Wrap the Built-In Controllers

Once blobs and attachments can answer those questions, the built-in Active Storage controllers can be wrapped with one concern that:

1. authenticates when needed
2. skips authentication for intentionally public files
3. returns `403` when the actor lacks record-level access
4. sets public cache headers only for truly public blobs

This approach works well because it protects:

- original blobs
- variants and previews
- proxy endpoints

all through the same authorization vocabulary.

## Useful Record-Level Patterns

### Private by Membership

Collaborative records usually inherit access from their parent container:

```ruby
class Document < ApplicationRecord
  belongs_to :project

  def accessible_to?(actor)
    project.accessible_to?(actor)
  end

  def publicly_accessible?
    published? && project.publicly_accessible?
  end
end
```

This works well for records like:

- documents
- comments
- attachments on tasks or issues

### Public by Design

Some files are intentionally public:

- avatars
- marketing assets
- publicly shared exports

That should be encoded on the record itself:

```ruby
class Avatar < ApplicationRecord
  def accessible_to?(_actor)
    true
  end

  def publicly_accessible?
    true
  end
end
```

### Private by Ownership

Some downloads are neither collaborative nor public. They are owner-only.

```ruby
class Export < ApplicationRecord
  belongs_to :user

  def accessible_to?(actor)
    actor == user
  end

  def publicly_accessible?
    false
  end
end
```

This pattern is useful for exports, invoices, billing archives, and other personal downloads.

## Rich Text Embeds and Variants Must Follow the Same Rules

Do not stop at direct `has_one_attached` and `has_many_attached` access.

The same rules should usually protect:

- rich text embeds
- image variants
- previews
- downloads generated from private records

If those surfaces bypass the owning record's authorization logic, you have a gap even if the main blob endpoint is protected.

## Public Files and Cacheability Are Related, But Not Identical

One of the easiest mistakes is treating "file can be served" and "file can be publicly cached" as the same thing.

Better rule:

- public files can use public cache headers
- private files may still be served through Active Storage, but should not be publicly cacheable

That protects against turning authenticated content into cacheable public assets by accident.

## Testing Guidance

Useful tests:

- authenticated actor with access can fetch the blob
- authenticated actor without access gets `403`
- unauthenticated actor is redirected or rejected for private blobs
- unauthenticated actor can fetch intentionally public blobs
- variants and previews follow the same rules as original blobs
- proxy caching is public only when the underlying record is public

The key is to test through the real Active Storage routes, not just the record methods.

## When to Use a Different Approach

This pattern is strongest when your app already relies on Active Storage's normal blob and proxy routes.

A different approach may be better when:

- every file is public
- every file is served through a dedicated application controller for business reasons
- the file backend is not Active Storage

Even then, the domain rule still holds: the owning record should answer the access question.

## Practical Guidance

- Give attachment-owning records an explicit access API.
- Make attachments delegate to the owning record.
- Protect built-in blob, variant, and proxy routes consistently.
- Treat public cache headers as a separate decision from ordinary access.
- Remember rich text embeds and previews when auditing file security.

## Fizzy Notes

Fizzy currently applies this pattern by extending Active Storage blobs and attachments with access questions and wrapping the built-in controllers. The same rules cover direct attachments, rich text embeds, avatar variants, and exported files.
