---
name: comments
description: Write, refine, or review code comments in Morris's preferred style, including Swift DocC comments and comments affected by code changes. Use for documenting behavior, constraints, and design intent; excludes GitHub review comments and standalone guides.
---

# Comments

Explain behavior and preserve useful intent. A reader should understand what the code does and the constraints on using or changing it, independently of its current callers.

## Approach

1. **Read the code and nearby documentation.** Establish the actual behavior, relevant conditions, side effects, and conventions. Trace delegated behavior when needed to make the comment accurate.
2. **Identify the useful information.** Document the contract or design decision a reader needs. Distinguish a symbol's behavior from the incidental places that currently invoke it.
3. **Edit at the appropriate location.** Use a documentation comment for the symbol's contract and an inline comment for a local mechanism, constraint, or compromise. Keep the explanation beside the code it describes and follow the project's conventions.
4. **Check accuracy and scope.** Read the comment against the implementation. Remove stale claims and redundant narration while preserving useful details. For comment-only work, preserve executable behavior; flag any discrepancy that requires a code decision.

Finish when the comments accurately describe the relevant behavior or intent, fit the local documentation style, and contain no unsupported claims. Return a concise account of the changes or the requested comment text.

## What to document

**Behavior:** Describe what the operation does, when it performs work or returns early, and meaningful results or side effects. Include caching, concurrency, permission handling, or error behavior when they materially affect its contract.

**Constraints:** Preserve requirements such as transaction ordering or shared in-flight work that someone could break while making an apparently harmless change.

**Intentional choices:** Explain behavior that could otherwise be mistaken for a defect. For example, explicitly document that an index remains local by design so a later reader does not add it to synchronization.

**Temporary compromises:** When an agreed implementation is temporary, state the reason and intended replacement near the affected code. Describe the actual plan without inventing a commitment or deadline.

Keep explanations proportional. A short comment can preserve an important fact. Expand when multiple conditions are necessary to understand the behavior. These preferences do not require a comment on every declaration or restrict all comments to explaining “why.”

## DocC and inline style

Use a direct summary of the symbol's behavior. Follow established DocC conventions for parameters, results, errors, and related information where relevant. When documenting what a function returns, use `- Returns:`. Express meaningful notes and important constraints with proper callout syntax, such as `- Note:` and `- Important:`.

Use ordinary, precise language. Keep documentation centered on the symbol rather than the current UI, call-site list, or history of the task. Usage context belongs when it is part of the contract or is needed to use the API correctly.

Inline comments should capture the local fact a maintainer needs. Prefer a concise explanation of the mechanism over a story about which screens currently exercise it. Preserve useful existing comments and update those affected by the code change.

## Examples

Examples illustrate the style. Use them only when their statements are true of the actual implementation.

### Describe behavior independently of callers

**Bad:**

```swift
/// View appearances reuse the current snapshot. Pull-to-refresh, foregrounding,
/// and store notifications explicitly request a fresh one through `loadContacts`.
```

**Good:**

```swift
/// Fetches contacts when no successful snapshot is cached, sharing any in-flight fetch.
/// Returns without fetching when a cached snapshot exists, including an empty one.
/// Clears cached contact data if access is no longer available.
```

The useful information is the fetching conditions and effects, which remain relevant when callers change.

### Keep the local mechanism clear

**Bad:**

```swift
// SwiftUI can request the list from several tabs at once. All callers await
// the same fetch instead of invalidating and repeating each other's work.
```

**Good:**

```swift
// Concurrent callers share the same in-flight fetch.
```

### Preserve an intentional omission

**Weak:**

```swift
// Skip indexData.
```

**Better:**

```swift
// The documentation index stays on this device and is intentionally excluded from sync.
```

### Use a DocC callout for a requirement

**Weak:**

```swift
/// Call AFTER the source mutation, on the SAME transaction.
```

**Better:**

```swift
/// Enqueues replication work for the collection.
///
/// - Important: Call after the source mutation using the same transaction.
```

### Explain temporary plumbing

**Weak:**

```swift
// TODO: Clean this up.
```

**Better, when this replacement is agreed:**

```swift
// The language is passed explicitly until search receives it through dependency injection.
```
