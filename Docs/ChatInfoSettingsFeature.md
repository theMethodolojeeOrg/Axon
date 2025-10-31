# Chat Info & Settings Feature - Implementation Summary

## Overview
The Chat Info & Settings feature provides per-conversation control over AI provider, model selection, and displays context usage and cost information. It replaces the cost ticker with a more comprehensive info button that opens a dedicated settings view.

## Key Features

### 1. Per-Conversation Provider/Model Selection
- **Override Global Settings**: Each conversation can use a different provider/model than the global default
- **Seamless Switching**: Change providers mid-conversation - the entire history is sent to the new model for continuity
- **Unified Interface**: Works with both built-in (Anthropic, OpenAI, Gemini) and custom providers
- **Model Filtering**: Only shows models with sufficient context window for current conversation

### 2. Context Window Progress Bar
- **Visual Indicator**: Progress bar shows percentage of context window used
- **Color Coding**:
  - Green (0-50%): Plenty of room
  - Orange (50-80%): Moderate usage
  - Red (80-100%): Nearing limit
- **Token Estimation**: Approximate token count based on message content (4 chars per token heuristic)
- **Formatted Display**: Shows "20K / 200K" style formatting

### 3. Cost Information & Navigation
- **Monthly Total**: Displays total cost this month
- **Direct Navigation**: "View Details" button navigates to full CostsBreakdownView
- **Consistent UI**: Uses NavigationLink instead of sheet for continuity

### 4. UI/UX Improvements
- **Info Icon**: Replaced cost ticker pill with info.circle icon in toolbar
- **Contextual Display**: Only shows in chat view when conversation exists
- **Clean Design**: Matches existing settings design language
- **Informative Note**: Explains that changing models sends full history

## Architecture

### Data Storage

#### ConversationOverrides Model
Per-conversation settings stored in UserDefaults:

```swift
struct ConversationOverrides: Codable {
    var builtInProvider: String?       // AIProvider rawValue
    var customProviderId: UUID?        // Custom provider UUID
    var builtInModel: String?          // AIModel id
    var customModelId: UUID?           // Custom model UUID
}
```

**Storage Key**: `conversation_overrides_{conversationId}`

### Component Structure

#### ChatInfoSettingsView
**Location**: `Views/Chat/ChatInfoSettingsView.swift`

**State Management**:
- `selectedProvider: UnifiedProvider?` - Current provider override
- `selectedModel: UnifiedModel?` - Current model override
- `estimatedTokens: Int` - Approximate token count
- Loads overrides from UserDefaults on appear
- Saves overrides when provider/model changes

**Sections**:
1. **AI Provider** - Picker with built-in and custom providers
2. **Model** - Picker with available models, filtered by context window
3. **Context Usage** - Progress bar with token count
4. **Costs** - Monthly total with navigation to details

**Token Estimation**:
```swift
let totalCharacters = messages.reduce(0) { $0 + $1.content.count }
estimatedTokens = max(1, totalCharacters / 4)
```

**Progress Color Logic**:
- < 50%: `AppColors.accentSuccess` (green)
- 50-80%: `AppColors.accentWarning` (orange)
- > 80%: `AppColors.accentError` (red)

### UI Integration

#### AppContainerView Changes
**Before**:
```swift
// Cost pill button
Button(action: { showCostBreakdown = true }) {
    HStack {
        Image(systemName: "creditcard")
        Text(costService.totalThisMonthUSDFriendly)
    }
    // ... styling
}
```

**After**:
```swift
// Info button (only when conversation exists)
if selectedConversation != nil {
    Button(action: { showChatInfo = true }) {
        Image(systemName: "info.circle")
            .font(.system(size: 20))
            .foregroundColor(AppColors.signalMercury)
    }
}
```

**Sheet Change**:
```swift
// Before
.sheet(isPresented: $showCostBreakdown) {
    CostsBreakdownView()
}

// After
.sheet(isPresented: $showChatInfo) {
    if let conversation = selectedConversation {
        ChatInfoSettingsView(conversation: conversation)
    }
}
```

#### ChatView Changes
Added toolbar item and sheet:
```swift
.toolbar {
    ToolbarItem(placement: .navigationBarTrailing) {
        Button(action: { showChatInfo = true }) {
            Image(systemName: "info.circle")
        }
    }
}
.sheet(isPresented: $showChatInfo) {
    ChatInfoSettingsView(conversation: conversation)
}
```

### Files Modified

1. **AppContainerView.swift**
   - Replaced `showCostBreakdown` with `showChatInfo`
   - Changed toolbar button from cost pill to info icon
   - Updated sheet to show ChatInfoSettingsView

2. **ChatView.swift**
   - Added `showChatInfo` state
   - Added toolbar with info button
   - Added sheet for ChatInfoSettingsView

3. **Created: ChatInfoSettingsView.swift**
   - Complete per-conversation settings interface
   - Provider/model selection with overrides
   - Context usage progress bar
   - Cost display with navigation

## User Workflow

### Accessing Chat Info
1. Open any existing conversation
2. Tap the info icon (ⓘ) in the top-right toolbar
3. View settings modal

### Changing Provider
1. In Chat Info & Settings, find "AI Provider" section
2. Tap the picker to see all providers (built-in and custom)
3. Select new provider
4. First model from new provider auto-selected
5. Overrides saved to UserDefaults
6. Next message sent to new provider with full conversation history

### Changing Model
1. In Chat Info & Settings, find "Model" section
2. Tap the picker to see available models
3. Models with insufficient context window appear grayed out in separate section
4. Select new model
5. Override saved
6. Next message uses new model

### Monitoring Context Usage
- Progress bar shows real-time estimate of context window usage
- Hover to see exact token count: "20.5K / 200K"
- Color changes as you approach context limit
- Warning at 80% to consider model switch or conversation reset

### Viewing Costs
- See monthly total at a glance
- Tap "View Details" to navigate to CostsBreakdownView
- Full breakdown by provider with today/month totals

## Technical Details

### Context Window Filtering
Models are filtered based on estimated token count:

```swift
let validModels = availableModels.filter { model in
    estimatedTokens == 0 || model.contextWindow >= estimatedTokens
}
```

Models with insufficient context appear in separate "Insufficient Context" section showing required context size.

### Override Persistence
Per-conversation overrides persist across:
- App restarts (stored in UserDefaults)
- Conversation switches
- Provider/model list changes (gracefully handles deleted custom providers)

### Fallback Behavior
If override refers to deleted provider/model:
- Falls back to global default from Settings
- No data loss - just uses app-level settings
- User can reselect new provider in Chat Info

### Number Formatting
Token counts formatted for readability:
- `< 1,000`: "456"
- `1,000 - 999,999`: "20.5K"
- `≥ 1,000,000`: "1.2M"

## Design Patterns

### Reusable Components
- **SettingsSection**: Consistent section headers across settings views
- **UnifiedProvider/UnifiedModel**: Seamless handling of built-in and custom providers
- **Progress Bar**: Reusable geometry-based progress visualization

### Color Coding
- **Success**: Green (#4CAF50) for healthy context usage
- **Warning**: Orange/Amber for moderate usage
- **Error**: Red for critical usage
- **Mercury**: Teal (#3f6f7a) for primary actions

### State Synchronization
- Settings changes trigger immediate save to UserDefaults
- Model change triggers re-estimation of token count
- Provider change auto-updates available models

## Benefits

### User Benefits
1. **Flexibility**: Test different models within same conversation
2. **Cost Control**: Switch to cheaper models when appropriate
3. **Context Management**: Visual feedback on context usage
4. **Transparency**: Clear cost information per conversation
5. **Optimization**: Use best model for each phase of conversation

### Developer Benefits
1. **No Backend Changes**: All stored locally in UserDefaults
2. **Clean Separation**: Conversation overrides separate from global settings
3. **Extensible**: Easy to add more per-conversation settings
4. **Type-Safe**: Uses existing UnifiedProvider/UnifiedModel system

## Usage Examples

### Example 1: Cost Optimization
1. Start conversation with GPT-5 for complex reasoning
2. Once approach is clear, switch to GPT-5 Mini for implementation
3. Save 75% on output tokens while maintaining context

### Example 2: Context Expansion
1. Conversation approaching context limit with Claude Haiku 4.5 (200K)
2. Check progress bar: 85% used
3. Switch to GPT-4.1 (1M context window)
4. Continue conversation with 5x more context

### Example 3: Provider Comparison
1. Start with Claude for creative task
2. Switch to GPT-5 to compare responses
3. Switch to custom provider (Deepseek) for cost-effective iteration
4. Full conversation history maintained across all switches

### Example 4: Custom Provider Testing
1. Configure local Ollama instance as custom provider
2. Test locally before sending to cloud
3. Switch to production provider when satisfied
4. No data loss, seamless experience

## Future Enhancements

### Potential Additions
1. **Temperature Control**: Per-conversation temperature slider
2. **System Prompt Override**: Custom system prompts per conversation
3. **Memory Settings**: Enable/disable memory injection per conversation
4. **Max Tokens**: Control response length per conversation
5. **Export Settings**: Save conversation config as template
6. **Cost Prediction**: Estimate cost of next message
7. **Context Summary**: AI-generated summary when approaching limit
8. **Auto-Switch**: Automatically switch to larger context model when needed
9. **Model Comparison**: Send same message to multiple models
10. **Conversation Forking**: Branch conversation with different model

## Testing Checklist

### Functionality
- [ ] Info icon appears in AppContainerView toolbar
- [ ] Info icon appears in ChatView toolbar
- [ ] Icon only shows when conversation exists
- [ ] Tapping icon opens ChatInfoSettingsView
- [ ] Provider picker shows all built-in providers
- [ ] Provider picker shows all custom providers
- [ ] Model picker shows available models for selected provider
- [ ] Model picker filters by context window
- [ ] Progress bar displays correctly
- [ ] Progress bar color changes based on usage
- [ ] Token count estimation is reasonable
- [ ] Cost display shows monthly total
- [ ] "View Details" navigates to CostsBreakdownView
- [ ] Overrides persist across app restarts
- [ ] Overrides persist across conversation switches

### Edge Cases
- [ ] Works with empty conversation (no messages yet)
- [ ] Works with very long conversation (> 100K tokens)
- [ ] Handles deleted custom provider gracefully
- [ ] Handles deleted custom model gracefully
- [ ] Context window calculation with emoji/special chars
- [ ] Multiple rapid provider/model changes
- [ ] Provider change while message is sending

### UI/UX
- [ ] Info icon color matches design system (Mercury)
- [ ] Modal appears with smooth animation
- [ ] Navigation to CostsBreakdownView feels natural
- [ ] Progress bar visually clear and intuitive
- [ ] Color coding is accessible
- [ ] Number formatting is readable
- [ ] Info note is clear and helpful
- [ ] Picker sections are well-organized

## Notes

### Design Decisions
- **UserDefaults vs Core Data**: UserDefaults chosen for simplicity - small data, no relationships
- **Local Storage**: No backend needed - overrides are client-side preference
- **Token Estimation**: Simple heuristic (4 chars/token) sufficient for UI indication
- **Navigation vs Sheet**: NavigationLink to CostsBreakdownView provides better continuity
- **Auto-Model Selection**: When provider changes, auto-select first model for convenience
- **Context Filtering**: Prevent impossible model selections by filtering in UI

### Known Limitations
1. **Token Estimation**: Rough approximation, actual tokenization varies by model
2. **Context Carryover**: Full history sent on model switch may exceed new model's limit (filtered in UI)
3. **No Backend Sync**: Overrides not synced across devices
4. **No Model Memory**: Doesn't remember per-model conversation state

### Performance Considerations
- Token estimation runs on `Task {}` to avoid blocking UI
- Override save is synchronous but very fast (UserDefaults)
- Progress calculation cached until conversation changes
