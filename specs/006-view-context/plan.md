# Implementation Plan: View Context Button

**Branch**: `006-view-context` | **Date**: 2025-12-28 | **Spec**: [spec.md](./spec.md)

## Summary

Add a "View" button to the ContextBanner that opens a sheet displaying the complete captured context. Users can see all captured information (source app, selected text, preceding/succeeding text, metadata) and copy it to clipboard.

## Technical Context

**Language/Version**: Swift 5.9+ with Swift Concurrency (async/await)  
**Primary Dependencies**: SwiftUI, AppKit  
**Storage**: N/A (read-only display of existing Context model)  
**Testing**: Manual testing + SwiftUI Previews  
**Target Platform**: macOS 13+  
**Project Type**: Single macOS application  
**Performance Goals**: Context viewer opens < 200ms  
**Constraints**: Must work within existing NSPanel-based PromptWindow architecture

## Constitution Check

✅ **Modularity**: Single new view component + minor modifications to existing views  
✅ **Code Quality**: Follows existing SwiftUI patterns in codebase  
✅ **UX**: Consistent with existing UI patterns (buttons, sheets, copy feedback)

## Project Structure

### Documentation (this feature)

```text
specs/006-view-context/
├── spec.md              # Feature specification
├── plan.md              # This file
├── tasks.md             # Implementation tasks (created by /speckit.tasks)
└── checklists/
    └── requirements.md  # Quality checklist
```

### Source Code Changes

```text
Extremis/UI/PromptWindow/
├── PromptView.swift              # MODIFY: Update ContextBanner to add View button
├── ContextViewerSheet.swift      # NEW: Context viewer sheet view
└── PromptWindowController.swift  # MODIFY: Add onViewContext callback, state management
```

## Current Architecture Analysis

### Relevant Components

1. **ContextBanner** (`PromptView.swift:213-230`)
   - Simple HStack showing truncated context info
   - Currently receives only `text: String`
   - Needs: View button + callback to show full context

2. **PromptInputView** (`PromptView.swift:8-127`)
   - Contains ContextBanner
   - Receives `contextInfo: String?` from PromptContainerView
   - Needs: Pass additional callback `onViewContext`

3. **PromptContainerView** (`PromptWindowController.swift:476-542`)
   - Orchestrates views, passes viewModel data
   - Has access to `viewModel.currentContext` (full Context object)
   - Needs: Sheet state management, onViewContext callback

4. **PromptViewModel** (`PromptWindowController.swift:187-471`)
   - Already has `currentContext: Context?` property
   - No changes needed - already stores full context

### Data Flow

```
PromptWindowController
    └── currentContext: Context?
            │
            ▼
    PromptViewModel.currentContext = context  (line 108)
            │
            ▼
    PromptContainerView (observes viewModel)
            │
            ▼
    PromptInputView (receives contextInfo: String?)
            │
            ▼
    ContextBanner (displays truncated text)
```

## Implementation Design

### Approach: SwiftUI Sheet

Use SwiftUI's `.sheet()` modifier for the context viewer. This is the standard macOS pattern for modal overlays and integrates naturally with SwiftUI state management.

### New Component: ContextViewerSheet

```swift
struct ContextViewerSheet: View {
    let context: Context
    let onDismiss: () -> Void
    @State private var showCopiedFeedback = false
    
    var body: some View {
        // Scrollable content with sections for each context field
        // Copy All button with feedback
        // Close button / Escape to dismiss
    }
}
```

### Modified Components

1. **ContextBanner**: Add "View" button with `eye` icon
2. **PromptInputView**: Add `onViewContext` callback parameter
3. **PromptContainerView**: 
   - Add `@State var showContextViewer = false`
   - Add `.sheet(isPresented:)` modifier
   - Pass `onViewContext` callback to PromptInputView

## Files to Modify

| File | Change Type | Description |
|------|-------------|-------------|
| `Extremis/UI/PromptWindow/PromptView.swift` | MODIFY | Add View button to ContextBanner, add onViewContext to PromptInputView |
| `Extremis/UI/PromptWindow/PromptWindowController.swift` | MODIFY | Add sheet state and callback to PromptContainerView |
| `Extremis/UI/PromptWindow/ContextViewerSheet.swift` | NEW | Create context viewer sheet component |

## Implementation Steps

### Step 1: Create ContextViewerSheet (45 min)
Create new SwiftUI view that displays all context fields:
- Source section (app name, bundle ID, window title, URL)
- Selected text section (with copy button)
- Preceding text section
- Succeeding text section
- Metadata section (app-specific: Slack, Gmail, GitHub)
- Copy All button with "Copied!" feedback

### Step 2: Modify ContextBanner (15 min)
Add View button to ContextBanner:
- Add `onViewContext: (() -> Void)?` parameter
- Add eye icon button that calls callback
- Only show button when callback is provided

### Step 3: Wire Up PromptInputView (15 min)
Pass callback through PromptInputView:
- Add `onViewContext: (() -> Void)?` parameter
- Pass to ContextBanner

### Step 4: Add Sheet to PromptContainerView (30 min)
Integrate sheet presentation:
- Add `@State private var showContextViewer = false`
- Add `.sheet(isPresented: $showContextViewer)` modifier
- Pass `onViewContext` callback to PromptInputView
- Access `viewModel.currentContext` for sheet content

## Code Sketches

### ContextViewerSheet Structure

```swift
struct ContextViewerSheet: View {
    let context: Context
    let onDismiss: () -> Void
    @State private var showCopiedFeedback = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            // Scrollable content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sourceSection
                    if context.selectedText != nil { selectedTextSection }
                    if context.precedingText != nil { precedingTextSection }
                    if context.succeedingText != nil { succeedingTextSection }
                    metadataSection
                }
                .padding()
            }

            // Footer with Copy All button
            footer
        }
        .frame(minWidth: 500, minHeight: 400, maxHeight: 600)
    }
}
```

### ContextBanner Update

```swift
struct ContextBanner: View {
    let text: String
    var onViewContext: (() -> Void)? = nil  // Optional callback

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .foregroundColor(.secondary)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer()

            // View button (only if callback provided)
            if let onViewContext = onViewContext {
                Button(action: onViewContext) {
                    Image(systemName: "eye")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("View full context")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
```

### PromptContainerView Sheet Integration

```swift
struct PromptContainerView: View {
    @ObservedObject var viewModel: PromptViewModel
    @State private var showContextViewer = false
    // ... existing properties

    var body: some View {
        VStack(spacing: 0) {
            // ... existing header and content
        }
        .sheet(isPresented: $showContextViewer) {
            if let context = viewModel.currentContext {
                ContextViewerSheet(
                    context: context,
                    onDismiss: { showContextViewer = false }
                )
            }
        }
    }
}
```

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Sheet doesn't dismiss on Escape | Use `.onExitCommand { }` or verify macOS default behavior |
| Large context causes performance issues | Use LazyVStack, limit preview lengths, test with 50k+ chars |
| Copy feedback not visible | Use overlay or toast pattern similar to LoadingOverlayController |
| Context is nil when View clicked | Guard with `if let` and hide button when no context |

## Success Metrics

- [ ] View button appears in context banner when context is available
- [ ] Clicking View opens sheet with complete context
- [ ] All context fields displayed (source, selected, preceding, succeeding, metadata)
- [ ] Copy All copies complete context to clipboard
- [ ] Sheet dismissible via close button, Escape, or click outside
- [ ] Sheet opens within 200ms
- [ ] Works with long text content (scrollable, no UI freeze)

## Testing Plan

1. **Manual Testing**:
   - Test with various apps (Slack, browser, TextEdit)
   - Test with selection vs. no selection
   - Test with long text content
   - Test copy functionality
   - Test keyboard navigation (Escape to close)

2. **SwiftUI Previews**:
   - Create previews for ContextViewerSheet with sample data
   - Create previews for ContextBanner with/without callback

