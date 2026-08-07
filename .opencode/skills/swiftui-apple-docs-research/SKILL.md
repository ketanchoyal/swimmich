---
name: swiftui-apple-docs-research
description: Research skill that finds and consolidates official Apple/SwiftUI documentation and real code examples using the Xcode MCP (DocumentationSearch / doc_search) and Exa MCP (web_search_exa, web_fetch_exa, get_code_context_exa) tools. Use before implementing any unfamiliar SwiftUI/UIKit/framework API, when verifying exact method signatures or availability, when the agent is unsure of correct syntax, or when the user asks "how do I do X in SwiftUI" and a grounded, source-backed answer is needed instead of a guess. Load before writing code against an API you haven't recently verified.
license: MIT
compatibility: opencode
metadata:
  domain: ios-swiftui
  role: research
  requires-tools: xcode-mcp, exa-mcp
---

# Apple & SwiftUI Documentation Research

Never guess API signatures, availability, or behavior from memory alone when a documentation tool is available. This skill defines the order and method for gathering **grounded, current, and example-backed** answers before writing SwiftUI/Apple framework code.

## Why This Matters

LLM training data lags behind Apple's yearly API changes (new iOS 26 APIs, deprecated modifiers, renamed parameters). Guessing produces code that compiles-looking but doesn't exist, or targets the wrong OS version. Always verify against a live source before committing to an implementation.

## Tool Roles

| Tool (MCP) | Source | Best for |
|---|---|---|
| `DocumentationSearch` / `doc_search` (Xcode MCP, via `xcrun mcpbridge`) | Local Xcode SDK docs, on-device index, WWDC session content | Authoritative, offline-first lookup of exact API signatures, parameter names, availability annotations (`@available`), and official framework docs. Always try this first — it's fastest and most accurate for anything Apple ships. |
| `get_code_context_exa` (Exa MCP) | GitHub, StackOverflow, technical blogs, docs sites | Real-world code snippets showing an API actually being used, migration examples, common patterns not documented by Apple (e.g. combining two APIs). |
| `web_search_exa` (Exa MCP) | General web | Broader context: WWDC session summaries, community best practices, recent blog posts about iOS 26 changes, comparisons between approaches. |
| `web_fetch_exa` (Exa MCP) | Specific known URL | Full-page extraction when a search result snippet is insufficient — e.g. reading an entire Apple Developer documentation page or a long tutorial. |

## Research Workflow

Follow this order for any unfamiliar or uncertain API:

1. **Local docs first**: call `DocumentationSearch`/`doc_search` with the exact symbol or concept name (e.g. `"glassEffect"`, `"NavigationSplitView"`, `"@Observable"`). This is faster and more authoritative than any web tool since it reads from the actual installed SDK.
2. **If local docs are missing/thin** (new API not yet indexed, or a conceptual "how do I..." question rather than a symbol lookup): call `web_search_exa` with a precise, source-aware query, e.g. `"site:developer.apple.com glassEffectContainer"` or `"SwiftUI NavigationSplitView sidebar detail example"`.
3. **For real usage patterns and working code**: call `get_code_context_exa` with the API name plus the concrete task, e.g. `"SwiftUI @Observable ViewModel dependency injection example"`. This surfaces GitHub/StackOverflow snippets that show the API in a working context, not just the signature.
4. **If a search result is a specific Apple Developer Documentation page or a long article**, use `web_fetch_exa` to pull the full content rather than relying on a truncated snippet — Apple doc pages often have critical details (availability notes, deprecation warnings, sample code) below the fold.
5. **Cross-check** at least two sources when the API is new (post iOS 17) or when behavior is ambiguous (e.g. animation timing, exact default values) — official docs plus one working code example.
6. **Never fabricate a method signature, parameter name, or availability version.** If none of the tools return a confident answer, say so explicitly rather than inventing plausible-looking Swift.

## Query Formulation Rules

- Use the exact Swift symbol name when known (`glassEffect(_:in:isEnabled:)`, not "the glass effect thing").
- For local doc search, prefer the bare symbol/type name over a full sentence — it indexes like a search engine over API names, not natural language.
- For Exa searches, be specific about iOS version when it matters: `"iOS 26 SwiftUI NavigationSplitView"` not just `"SwiftUI navigation"`.
- For code examples via `get_code_context_exa`, phrase as a task, not just an API name: `"paginated List with SwiftData @Query"` surfaces more useful snippets than `"@Query"` alone.
- When researching a deprecated-vs-current API question, explicitly search both terms (old and new name) to confirm the migration path and deprecation version.

## Output Format When Reporting Research

When consolidating findings for the user or for use in code generation, structure the result as:

1. **API/concept** — exact name and minimum OS version.
2. **Signature** — as found in official docs, verbatim.
3. **Official description** — one or two sentences from Apple's docs.
4. **Working example** — a real snippet (from `get_code_context_exa` or an Apple sample), adapted minimally.
5. **Gotchas** — deprecations, common mistakes, availability caveats found during research.

## Anti-Patterns

- Writing SwiftUI code for a rarely-used or newly introduced API purely from training-data memory without checking `DocumentationSearch` first.
- Treating an Exa web result as authoritative over the local Xcode SDK documentation when both are available — local docs win on accuracy for exact signatures.
- Citing a StackOverflow answer or blog post as if it were Apple's official stance on a design pattern — clearly separate "official Apple guidance" from "community pattern."
- Skipping verification because the API "looks familiar" — API surfaces change subtly between OS versions (renamed parameters, changed defaults).
- Fetching an entire long documentation page with `web_fetch_exa` when a `DocumentationSearch` symbol lookup would have answered the question directly and faster.
