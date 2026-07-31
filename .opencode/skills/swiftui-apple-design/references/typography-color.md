# Typography & Color Reference

## Semantic Text Style Scale
Use these instead of fixed point sizes — they scale with Dynamic Type and match system UI exactly.

| Style | Typical use |
|---|---|
| `.largeTitle` | Screen-level hero title (e.g. "Settings" nav title in large-title mode) |
| `.title` / `.title2` / `.title3` | Section headers, prominent card titles |
| `.headline` | Emphasized row titles, card titles |
| `.body` | Default body copy, list row primary text |
| `.callout` | Slightly smaller supporting text |
| `.subheadline` | Secondary line under a headline |
| `.footnote` | Metadata, timestamps |
| `.caption` / `.caption2` | Smallest labels, fine print |

Weight modifiers: `.fontWeight(.semibold)`, `.bold()`. Combine style + weight rather than inventing a custom size: `.font(.title3.weight(.semibold))`.

Rounded design (use sparingly, consumer/playful contexts only):
```swift
Text("42").font(.system(.largeTitle, design: .rounded).bold())
```

## Semantic Colors
Never hardcode hex/RGB for UI chrome — always prefer these so Light/Dark Mode and accessibility contrast settings work automatically.

**Foreground:**
- `.foregroundStyle(.primary)` — main content
- `.foregroundStyle(.secondary)` — supporting text
- `.foregroundStyle(.tertiary)` — de-emphasized (chevrons, disabled-adjacent)
- `.foregroundStyle(.quaternary)` — barely-there dividers/placeholders

**Backgrounds:**
- `Color(.systemBackground)` — primary screen background
- `Color(.secondarySystemBackground)` — grouped content background
- `Color(.tertiarySystemBackground)` — nested surfaces

**Fills (for shapes/controls, not text):**
- `Color(.systemFill)`, `.secondarySystemFill`, `.tertiarySystemFill`, `.quaternarySystemFill`

**Tint / accent:**
- `.tint(.accentColor)` or a custom `Color("AccentColor")` from the asset catalog — set once at the app or NavigationStack root, don't scatter custom colors per-view.

**Semantic status colors** (use Apple's, don't invent new ones):
- `.red` (destructive/error), `.orange` (warning), `.green` (success/positive), `.blue` (info/links — but don't clash with your accent color), `.yellow` (caution)

## SF Symbols Rendering Modes
```swift
.symbolRenderingMode(.monochrome)   // single tone (default)
.symbolRenderingMode(.hierarchical) // one color, varying opacity — good default for most icons
.symbolRenderingMode(.palette)      // multiple explicit colors
    .foregroundStyle(.white, .red)  // pairs with .palette
.symbolRenderingMode(.multicolor)   // symbol's built-in multicolor (e.g. weather symbols)
```
Variable symbols (e.g. battery, wifi level) animate with `.contentTransition(.symbolEffect)`.

## Dark Mode Checklist
- [ ] Every custom `Color` is either a semantic system color or defined in the Asset Catalog with both Light and Dark variants (not a single hardcoded hex)
- [ ] Materials (`.regularMaterial`, `.thinMaterial`, etc.) used for translucent surfaces instead of a manually chosen light/dark background color
- [ ] Images/illustrations with transparent backgrounds have been checked against a dark canvas — no invisible dark-on-dark logos
- [ ] Shadows are subtle enough not to look wrong on a dark background (shadows are barely visible in Dark Mode by nature — that's correct, don't compensate with a glow)
- [ ] Preview both appearances: `.preferredColorScheme(.dark)` in a SwiftUI preview, or the Xcode canvas variant switcher
