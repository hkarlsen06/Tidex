# iOS Wagey Chatbot Implementation Plan

## Overview

Implement Wagey AI chatbot in the native iOS app using the existing `/api/chat` streaming endpoint. The iOS app will have a native SwiftUI chat interface that consumes Server-Sent Events (SSE) from the web backend.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         iOS App                                  │
├─────────────────────────────────────────────────────────────────┤
│  WageyView (SwiftUI)                                            │
│    ├── ChatMessageList (messages + streaming text)              │
│    ├── ChatInputField (text input + send button)                │
│    └── ToolStatusIndicator (shows tool execution)               │
├─────────────────────────────────────────────────────────────────┤
│  WageyViewModel (@Observable)                                   │
│    ├── messages: [ChatMessage]                                  │
│    ├── currentStreamingText: String                             │
│    ├── isStreaming: Bool                                        │
│    └── sendMessage(content:) async                              │
├─────────────────────────────────────────────────────────────────┤
│  WageyService                                                   │
│    ├── streamChat(messages:userId:userName:) -> AsyncStream     │
│    └── SSE parsing + chunk handling                             │
├─────────────────────────────────────────────────────────────────┤
│  SSEStreamParser                                                │
│    └── Parses "data: {json}\n\n" format from URLSession bytes   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ HTTPS POST (Bearer token)
                              │ Content-Type: text/event-stream
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Next.js Backend                             │
│  /api/chat (existing River endpoint)                            │
│    ├── Validates input                                          │
│    ├── Checks usage limits                                      │
│    ├── Calls Claude API                                         │
│    ├── Executes tools                                           │
│    └── Streams ChatChunk responses                              │
└─────────────────────────────────────────────────────────────────┘
```

## File Structure

```
ios/App/TidexApp/Native/
├── Features/
│   └── Wagey/
│       ├── WageyView.swift              # Main chat UI
│       ├── WageyViewModel.swift         # State management
│       ├── Components/
│       │   ├── ChatMessageBubble.swift  # Message bubble component
│       │   ├── ChatMessageList.swift    # Scrollable message list
│       │   ├── ChatInputField.swift     # Text input with send button
│       │   ├── ToolStatusView.swift     # Tool execution indicator
│       │   └── StreamingTextView.swift  # Animated streaming text
│       └── Models/
│           └── ChatMessage.swift        # Message data model
├── Services/
│   └── Chat/
│       ├── WageyService.swift           # Chat API service
│       └── SSEStreamParser.swift        # SSE parsing utility
└── Storage/
    └── Models/
        └── LocalChatHistory.swift       # Optional: persist chat history
```

## Implementation Tasks

### Task 1: SSE Stream Parser (Foundation Layer)

**File:** `ios/App/TidexApp/Native/Services/Chat/SSEStreamParser.swift`

Create a reusable SSE parser that:
- Consumes `URLSession.AsyncBytes`
- Parses `data: {json}\n\n` format
- Yields parsed JSON objects as an `AsyncThrowingStream`
- Handles connection errors and reconnection

**Key Implementation:**
```swift
/// Parses Server-Sent Events from an async byte stream
actor SSEStreamParser {
    /// Parse SSE events from URLSession bytes
    static func parse<T: Decodable>(
        _ bytes: URLSession.AsyncBytes,
        as type: T.Type
    ) -> AsyncThrowingStream<T, Error>
}
```

### Task 2: Chat Models

**File:** `ios/App/TidexApp/Native/Features/Wagey/Models/ChatMessage.swift`

Define data models matching the web app:

```swift
/// A chat message in the Wagey conversation
struct ChatMessage: Identifiable, Equatable {
    let id: String
    let role: MessageRole
    var content: String
    var toolCalls: [ToolCall]?
    let timestamp: Date

    enum MessageRole: String, Codable {
        case user
        case assistant
    }
}

/// A tool call within a message
struct ToolCall: Identifiable, Equatable, Codable {
    let id: String
    let name: String
    var arguments: String?
    var result: String?
    var success: Bool?
}

/// Chat chunk types from the streaming API
enum ChatChunk: Decodable {
    case text(content: String)
    case toolStart(toolName: String, toolCallId: String, toolArguments: String?)
    case toolResult(toolName: String, toolCallId: String, result: String, success: Bool)
    case done
    case error(message: String)
    case wageyLimit(remaining: Int, resetDays: Int)
    case wageyNoAccess
}
```

### Task 3: Wagey Service

**File:** `ios/App/TidexApp/Native/Services/Chat/WageyService.swift`

Implement the API service:

```swift
@MainActor
final class WageyService: ObservableObject {
    static let shared = WageyService()

    /// Stream chat responses from the API
    func streamChat(
        messages: [ChatMessage],
        userId: String,
        userName: String?
    ) -> AsyncThrowingStream<ChatChunk, Error>

    /// Check Wagey access level and remaining messages
    func checkAccess() async throws -> WageyAccessInfo
}
```

**API Request Format:**
```json
POST /api/chat
Authorization: Bearer <access_token>
Content-Type: application/json

{
  "routerStreamKey": "wagey",
  "input": {
    "messages": [
      { "role": "user", "content": "Add a shift tomorrow 9-17" }
    ],
    "userId": "uuid",
    "userName": "Hjalmar"
  }
}
```

**Response:** SSE stream with `data: {json}\n\n` format

### Task 4: WageyViewModel

**File:** `ios/App/TidexApp/Native/Features/Wagey/WageyViewModel.swift`

State management with @Observable:

```swift
@MainActor
@Observable
final class WageyViewModel {
    // State
    private(set) var messages: [ChatMessage] = []
    private(set) var currentStreamingText: String = ""
    private(set) var isStreaming: Bool = false
    private(set) var limitReached: Bool = false
    private(set) var remainingMessages: Int?
    private(set) var error: Error?

    // Current streaming task (for cancellation)
    private var streamTask: Task<Void, Never>?

    // Actions
    func sendMessage(_ content: String) async
    func cancelStream()
    func clearConversation()

    // Private helpers
    private func processChunk(_ chunk: ChatChunk)
    private func finalizeStreamingText()
}
```

### Task 5: Chat UI Components

#### 5a: ChatMessageBubble

**File:** `ios/App/TidexApp/Native/Features/Wagey/Components/ChatMessageBubble.swift`

Message bubble with:
- User messages: right-aligned, brand color background
- Assistant messages: left-aligned, surface color background
- Tool call indicators with status
- Markdown rendering for assistant responses

#### 5b: ChatMessageList

**File:** `ios/App/TidexApp/Native/Features/Wagey/Components/ChatMessageList.swift`

Scrollable list with:
- Auto-scroll to bottom on new messages
- Pull-to-refresh (optional)
- Empty state with suggestions
- Streaming text indicator at bottom

#### 5c: ChatInputField

**File:** `ios/App/TidexApp/Native/Features/Wagey/Components/ChatInputField.swift`

Input field with:
- Multi-line text input (auto-expanding)
- Send button (enabled when text present and not streaming)
- Keyboard handling
- Haptic feedback on send

#### 5d: ToolStatusView

**File:** `ios/App/TidexApp/Native/Features/Wagey/Components/ToolStatusView.swift`

Tool execution indicator showing:
- Tool name (localized)
- Spinner while executing
- Checkmark on success
- Error state on failure

### Task 6: Main WageyView

**File:** `ios/App/TidexApp/Native/Features/Wagey/WageyView.swift`

Main view composing all components:

```swift
struct WageyView: View {
    @State private var viewModel = WageyViewModel()
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        VStack(spacing: 0) {
            // Header
            WageyHeader(
                remainingMessages: viewModel.remainingMessages,
                onNewChat: { viewModel.clearConversation() }
            )

            // Messages
            ChatMessageList(
                messages: viewModel.messages,
                streamingText: viewModel.currentStreamingText,
                isStreaming: viewModel.isStreaming
            )

            // Input
            ChatInputField(
                onSend: { content in
                    Task { await viewModel.sendMessage(content) }
                },
                disabled: viewModel.isStreaming || viewModel.limitReached
            )
        }
        .background(Color.tidexBackground)
    }
}
```

### Task 7: Navigation Integration

Add Wagey to the app's tab bar or settings menu:
- Add tab item with sparkle icon
- Gate access behind subscription check (Pro/Max)
- Show paywall for free users

### Task 8: Localization

Add localization keys to `Localizable.strings`:
- `wagey.title` = "Wagey"
- `wagey.subtitle` = "AI-assistent for vakter"
- `wagey.placeholder` = "Spor Wagey om noe..."
- `wagey.newChat` = "Ny chat"
- `wagey.sending` = "Sender..."
- `wagey.limitReached` = "Du har brukt alle meldingene dine denne måneden"
- Tool names and status messages

## API Contract

### Request

```
POST https://app.tidex.no/api/chat
Authorization: Bearer <jwt_access_token>
Content-Type: application/json
Accept: text/event-stream

{
  "routerStreamKey": "wagey",
  "input": {
    "messages": [
      {
        "role": "user" | "assistant" | "tool",
        "content": "string",
        "tool_calls": [{ "id": "string", "type": "function", "function": { "name": "string", "arguments": "string" } }],
        "tool_call_id": "string",
        "name": "string"
      }
    ],
    "userId": "uuid",
    "userName": "string (optional)"
  }
}
```

### Response (SSE Stream)

Each event is formatted as `data: {json}\n\n`

**Chunk Types:**

```typescript
// Text content (stream character by character)
{ "chunk": { "type": "text", "content": "Hello" } }

// Tool execution started
{ "chunk": { "type": "tool_start", "toolName": "manage_shift", "toolCallId": "call_123", "toolArguments": "{...}" } }

// Tool execution completed
{ "chunk": { "type": "tool_result", "toolName": "manage_shift", "toolCallId": "call_123", "result": "{...}", "success": true } }

// Usage limit reached
{ "chunk": { "type": "wagey_limit", "remaining": 0, "resetDays": 5 } }

// No access (shouldn't happen if UI gates properly)
{ "chunk": { "type": "wagey_no_access" } }

// Stream complete
{ "chunk": { "type": "done" } }

// Error occurred
{ "chunk": { "type": "error", "error": "Error message" } }
```

## Design Specifications

### Colors (from Color+Tidex.swift)
- Background: `Color.tidexBackground`
- User bubble: `Color.tidexBlue` with white text
- Assistant bubble: `Color.tidexSurfacePrimary`
- Text primary: `Color.tidexTextPrimary`
- Text secondary: `Color.tidexTextSecondary`
- Tool indicator: `Color.tidexBlue` (spinner), `Color.tidexSuccess` (done)
- Error: `Color.tidexError`

### Typography
- Header title: `.tidexTitle2`
- Message text: `.tidexBody`
- Tool status: `.tidexCaption`
- Input placeholder: `.tidexBody` with `.tidexTextMuted`

### Spacing
- Message padding: `Spacing.md` (16pt)
- Message gap: `Spacing.sm` (12pt)
- Input padding: `Spacing.md` (16pt)

### Animations
- Message appear: fade in + slide up (spring animation)
- Streaming text: character-by-character with cursor blink
- Tool status: pulse animation while executing
- Send button: scale down on press, haptic feedback

## Testing Checklist

- [ ] SSE parser handles malformed data gracefully
- [ ] Stream cancellation works (user navigates away)
- [ ] Network errors show appropriate UI
- [ ] Auth token refresh during long conversations
- [ ] Tool calls display correctly
- [ ] Limit reached disables input
- [ ] Memory management (no leaks on repeated chats)
- [ ] VoiceOver accessibility
- [ ] Dark mode appearance
- [ ] Keyboard handling (dismiss, input expansion)

## Dependencies

No new external dependencies required. Uses:
- Foundation (URLSession)
- SwiftUI
- Combine (for some reactive patterns)
- Existing Supabase SDK (for auth tokens)

## Rollout Plan

1. **Phase 1:** Implement SSE parser + service layer (no UI)
2. **Phase 2:** Build chat UI components
3. **Phase 3:** Integrate with main app navigation
4. **Phase 4:** Add localization
5. **Phase 5:** Testing and polish
