# 03 — Linting & Code Quality

## Tools

| Tool | Version | Config File | Purpose |
|------|---------|-------------|---------|
| SwiftLint | Latest (Homebrew) | `.swiftlint.yml` | Static analysis, style enforcement |
| SwiftFormat | Latest (Homebrew) | `.swiftformat` | Automatic code formatting |

## Running

```bash
make lint        # Run SwiftLint
make format      # Run SwiftFormat (modifies files)
make format-check # SwiftFormat dry-run (CI mode)
```

## SwiftLint Configuration Rationale

### Thresholds

| Rule | Warning | Error | Reason |
|------|---------|-------|--------|
| `file_length` | 550 | 700 | AudioEngine=537, CarPlayManager=525 are the largest |
| `type_body_length` | 450 | 600 | Large SwiftUI views and singletons |
| `function_body_length` | 60 | 100 | Some SwiftUI body/setup funcs are naturally long |
| `line_length` | 150 | 200 | SwiftUI chains can be verbose |
| `cyclomatic_complexity` | 15 | 25 | CarPlay/queue logic has branching |

### Disabled Rules

| Rule | Reason |
|------|--------|
| `trailing_comma` | Style preference — trailing commas allowed |
| `multiple_closures_with_trailing_closure` | Common in SwiftUI modifiers |
| `identifier_name` | Short names (x, id, i) fine in context |
| `type_name` | Short type names acceptable |
| `nesting` | SwiftUI views naturally nest deeply |
| `opening_brace` | Conflicts with some SwiftUI patterns |

### Severity Overrides

| Rule | Severity | Reason |
|------|----------|--------|
| `force_cast` | warning | Some intentional casts (UIImage bridging) |
| `force_try` | warning | JSONEncoder in non-failable contexts |
| `todo` | warning | Allow TODO/FIXME as reminders |

### Opt-in Rules Enabled

`closure_end_indentation`, `closure_spacing`, `collection_alignment`, `contains_over_filter_count`, `empty_count`, `empty_string`, `fatal_error_message`, `first_where`, `implicit_return`, `last_where`, `modifier_order`, `overridden_super_call`, `redundant_nil_coalescing`, `sorted_first_last`, `toggle_bool`, `unneeded_parentheses_in_closure_argument`, `vertical_parameter_alignment_on_call`

## Baseline Violations (Initial Run)

**Total: 25 warnings, 0 errors across 62 files**

### By Category

| Category | Count | Files |
|----------|-------|-------|
| `function_body_length` | 8 | AudioEngine, RemoteCommandManager, AlbumDetailView (×2), SearchView, StationSearchView, ServerManagerView, TrackContextMenu |
| `vertical_parameter_alignment` | 6 | CarPlaySceneDelegate (×2), CarPlaySearchHandler (×4) |
| `force_try` | 2 | StationSearchView (×2) |
| `for_where` | 2 | SmartPlaylistView (×2) |
| `line_length` | 1 | SettingsView:385 (version string fix made it longer) |
| `redundant_sendable` | 1 | SubsonicClient |
| `void_function_in_ternary` | 1 | AudioEngine:173 |
| `trailing_newline` | 1 | MiniPlayerView:336 |
| `unused_closure_parameter` | 1 | VisualizerView:74 |
| `implicit_optional_initialization` | 1 | AlbumsView:6 |
| `vertical_parameter_alignment_on_call` | 1 | SubsonicEndpoints:178 |

### Priority Fix Plan

**Quick fixes (trivial, auto-fixable):**
- `trailing_newline` — remove extra blank line
- `implicit_optional_initialization` — remove `= nil`
- `unused_closure_parameter` — replace with `_`
- `redundant_sendable` — remove Sendable conformance
- `for_where` — convert `for + if` to `for where`

**Medium effort:**
- `vertical_parameter_alignment` — reformat parameter lists (6 sites)
- `line_length` — break long line
- `void_function_in_ternary` — convert to if/else
- `force_try` — convert to try/catch

**Deferred to Sprint 2 (requires refactoring):**
- `function_body_length` — 8 long functions need extraction of sub-views/helpers

## CI Integration

SwiftLint runs as the first CI job. Build jobs depend on lint passing.

```yaml
# .github/workflows/ci.yml
lint:
  runs-on: macos-14
  steps:
    - uses: actions/checkout@v4
    - run: brew install swiftlint
    - run: swiftlint lint --config .swiftlint.yml --strict
```

**CI Quality Gate:** `--strict` flag means all warnings are treated as errors. The baseline violations must be fixed before CI will pass.

## SwiftFormat Configuration

SwiftFormat matches existing project style:
- 4-space indentation
- Swift 6.0 features
- Trailing commas preserved
- Header comments left as-is
- No organization/sorting of imports (preserves existing order)

Disabled rules that would conflict with project conventions:
- `blankLinesAtStartOfScope` / `blankLinesAtEndOfScope`
- `redundantReturn` (explicit returns preferred in some contexts)
- `sortImports` / `organizeDeclarations` / `markTypes`
