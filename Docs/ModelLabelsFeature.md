# Model Labels Feature - Implementation Summary

## Overview
Added visual model labels under AI assistant profile images in chat to help users track which responses came from which model. Labels are unbeknownst to the model itself (purely for user reference).

## Implementation

### 1. Message Model Updates
**File**: `Models/Message.swift`

Added two optional fields to the `Message` struct:
```swift
let modelName: String?       // e.g., "Claude Sonnet 4.5", "GPT-5 Mini", "Deepseek"
let providerName: String?    // e.g., "Anthropic", "OpenAI", "LocalLM"
```

These fields are:
- Optional (backward compatible with existing messages)
- Populated automatically when messages are created
- Used purely for display purposes in the UI

### 2. UI Updates
**File**: `Views/Chat/ChatView.swift`

Updated `MessageBubble` to display model label under assistant avatar:

**Before**:
```
┌─────┐
│ ✨  │  Message content...
└─────┘
```

**After**:
```
┌─────┐
│ ✨  │  Message content...
└─────┘
 GPT-4
```

**Implementation**:
- Wrapped avatar in `VStack` with 4pt spacing
- Added `Text(modelName)` below avatar
- Used `AppTypography.labelSmall()` font
- Colored with `AppColors.textTertiary` for subtle appearance
- Fixed width (60pt) to align messages consistently

### 3. Service Layer Updates
**File**: `Services/Conversation/ConversationService.swift`

#### Helper Function: `getProviderAndModel()`
Determines which provider/model to use with this priority:
1. **Conversation-specific overrides** (from ChatInfoSettingsView)
2. **Global custom provider** (if selected in Settings)
3. **Global built-in provider** (default fallback)

Returns tuple: `(provider: String, modelName: String, providerName: String)`

#### Message Creation
When receiving assistant messages from backend:
- Checks if backend provided `modelName` and `providerName`
- If not, populates them from current settings/overrides
- Ensures all assistant messages have model metadata for display

### 4. Label Display Logic

**User Messages**: No label (user avatar only)

**Assistant Messages**: Label appears if `modelName` is present
- Line limit: 1 (prevents multi-line labels)
- Subtle tertiary text color
- Small font size for minimal visual impact
- Fixed width container for consistent alignment

## User Experience

### Visual Design
- **Subtle**: Light gray color, small font - doesn't compete with message content
- **Informative**: Users can quickly see model switches in conversation
- **Consistent**: Fixed width ensures messages align properly

### Example Conversation
```
┌─────┐
│ ✨  │  I am based on OpenAI's GPT-3 model...
└─────┘
 GPT-3

[User switches to Claude Sonnet 4.5]

┌─────┐
│ ✨  │  I can help you with that...
└─────┘
Claude
Sonnet
```

### Model Switching
When user switches models mid-conversation (via ChatInfoSettingsView):
1. New messages show new model label
2. Old messages retain their original model labels
3. Clear visual history of which model said what
4. Model itself is unaware of this labeling

## Technical Details

### Model Name Sources

**Built-in Models**:
- From `AIModel.name` property
- Examples: "Claude Sonnet 4.5", "GPT-5 Mini", "Gemini 2.5 Pro"

**Custom Models**:
- From `CustomModelConfig.friendlyName` if provided
- Falls back to `CustomProviderConfig.providerName`
- Examples: "Deepseek", "LocalLM", "Llama 3.1 70B"

### Provider Name Sources

**Built-in Providers**:
- From `AIProvider.displayName`
- Examples: "Anthropic (Claude)", "OpenAI (GPT)", "Google Gemini"

**Custom Providers**:
- From `CustomProviderConfig.providerName`
- Examples: "Deepseek", "LocalLM", "Ollama"

### Backward Compatibility
- Existing messages without `modelName`/`providerName` don't crash
- Label simply doesn't appear if metadata is missing
- Gracefully handles nil values

## Files Modified

1. **Models/Message.swift**
   - Added `modelName: String?`
   - Added `providerName: String?`
   - Updated init parameters
   - Updated CodingKeys

2. **Views/Chat/ChatView.swift**
   - Wrapped avatar in VStack
   - Added model label Text view
   - Fixed width for alignment

3. **Services/Conversation/ConversationService.swift**
   - Added `getProviderAndModel()` helper
   - Updated `sendMessage()` to populate metadata
   - Reads conversation overrides
   - Fallback to global settings

## Benefits

### For Users
1. **Visual Tracking**: Easy to see which model generated which response
2. **Model Comparison**: Compare responses from different models in same thread
3. **Context Awareness**: Know which model's capabilities you're working with
4. **History**: Permanent record of model switches in conversation

### For Debugging
1. **Issue Reports**: Users can report "GPT-4 said X" vs "Claude said Y"
2. **Cost Tracking**: Visual confirmation of which model was used
3. **Quality Assessment**: Compare model outputs side-by-side

### Privacy
- Model label is client-side only
- Not sent to backend
- Not visible to the model itself
- Purely for user reference

## Design Decisions

### Why Under Avatar?
- Natural association with the message source
- Doesn't interfere with message content
- Consistent positioning across all assistant messages
- Mirrors real chat apps (e.g., Slack, Discord)

### Why Subtle Styling?
- Primary focus should remain on message content
- Label is reference information, not critical
- Reduces visual clutter
- Professional appearance

### Why Fixed Width?
- Ensures message bubbles align consistently
- Prevents layout shifts when labels vary in length
- Cleaner, more professional look
- Better reading experience

### Why Optional Fields?
- Backward compatible with existing data
- Graceful degradation if metadata unavailable
- No breaking changes
- Future-proof architecture

## Future Enhancements

### Potential Additions
1. **Tooltip**: Hover to see full model details (context window, pricing, etc.)
2. **Color Coding**: Different colors per provider
3. **Icons**: Provider-specific icons (Anthropic logo, OpenAI logo, etc.)
4. **Clickable**: Tap label to see model info or switch models
5. **Token Count**: Show tokens used for that specific response
6. **Cost**: Show cost for that specific response
7. **Timing**: Show response time/latency

### Advanced Features
1. **Filter by Model**: "Show only GPT-4 responses"
2. **Model Stats**: Aggregate stats per model in conversation
3. **Model Comparison View**: Side-by-side comparison of responses
4. **Export with Labels**: Include model info in conversation exports

## Testing Checklist

### Functionality
- [ ] Label appears for assistant messages
- [ ] Label doesn't appear for user messages
- [ ] Label shows correct model name
- [ ] Label updates when switching models
- [ ] Old messages retain original model labels
- [ ] Works with built-in providers
- [ ] Works with custom providers
- [ ] Gracefully handles missing metadata
- [ ] Conversation overrides are respected
- [ ] Global settings are fallback

### UI/UX
- [ ] Label is readable but subtle
- [ ] Doesn't interfere with message content
- [ ] Fixed width maintains alignment
- [ ] Single line truncation works
- [ ] Color is appropriate (tertiary text)
- [ ] Font size is appropriate
- [ ] Spacing from avatar is correct

### Edge Cases
- [ ] Very long model names (truncation)
- [ ] Empty model name (no label shown)
- [ ] Model switch mid-conversation
- [ ] Multiple rapid model switches
- [ ] Conversation with 10+ different models
- [ ] Custom provider with no friendly name

## Notes

### Label Content Strategy
**Current**: Shows only model name (e.g., "Claude Sonnet 4.5")
**Alternative**: Could show provider + model (e.g., "Anthropic: Claude Sonnet 4.5")
**Decision**: Keep it concise - model name alone is sufficient and less cluttered

### Width Calculation
- Avatar: 32pt
- Spacing: 12pt
- Label: Should accommodate ~10 characters comfortably
- Total: 60pt provides good balance

### Text Wrapping
- Single line with truncation prevents multi-line labels
- Long names like "Claude Sonnet 4.5" fit comfortably
- Extremely long custom names truncate with "..."
