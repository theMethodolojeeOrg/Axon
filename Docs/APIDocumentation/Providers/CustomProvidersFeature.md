# Custom Providers Feature - Implementation Summary

## Overview
The Custom Providers feature allows users to add unlimited OpenAI-compatible AI provider endpoints and models to Axon. These custom configurations appear seamlessly alongside built-in providers (Anthropic, OpenAI, Gemini) throughout the app.

## Architecture

### Data Models (Settings.swift)

#### 1. CustomProviderConfig
Stores provider-level configuration:
- `id: UUID` - Unique identifier
- `providerName: String` - User-facing provider name
- `apiEndpoint: String` - Base URL for API requests
- `models: [CustomModelConfig]` - Array of models for this provider

#### 2. CustomModelConfig
Stores model-level configuration:
- `id: UUID` - Unique identifier
- `modelCode: String` - Technical model identifier (e.g., "llama-3.1-70b")
- `friendlyName: String?` - Optional display name (falls back to provider name)
- `contextWindow: Int` - Context window in tokens
- `description: String?` - Optional description (auto-generates if missing)
- `pricing: CustomModelPricing?` - Optional pricing information

#### 3. CustomModelPricing
Stores pricing details:
- `inputPerMTok: Double` - Input price per million tokens
- `outputPerMTok: Double` - Output price per million tokens
- `cachedInputPerMTok: Double?` - Optional cached input pricing

#### 4. UnifiedProvider & UnifiedModel
Enums that provide a unified interface for both built-in and custom providers/models:
- `UnifiedProvider`: `.builtIn(AIProvider)` or `.custom(CustomProviderConfig)`
- `UnifiedModel`: `.builtIn(AIModel)` or `.custom(CustomModelConfig, ...)`

### Storage Layer

#### SettingsStorage
Custom providers stored in `AppSettings.customProviders` array, persisted to UserDefaults as JSON.

#### APIKeysStorage
Custom provider API keys stored securely in Keychain with key format:
```
custom_provider_api_key_{UUID}
```

### UI Components

#### 1. CustomProvidersSettingsView
**Location**: `Views/Settings/CustomProvidersSettingsView.swift`

Main view for managing custom providers:
- Info banner explaining the feature
- List of configured providers (card-based)
- Add provider button
- Provider edit sheet with:
  - Provider name and endpoint fields
  - Multiple model configurations
  - Advanced pricing accordion
  - Validation and error handling

**Key Components**:
- `CustomProviderCard` - Displays provider with expandable model list
- `ModelInfoRow` - Shows individual model details
- `CustomProviderEditSheet` - Modal for creating/editing providers
- `ModelEditRow` - Form for editing individual models

#### 2. UnifiedProviderSelectionView
**Location**: `Views/Settings/UnifiedProviderSelectionView.swift`

Provides unified interface for provider/model selection:
- ViewModel extensions for unified provider management
- `UnifiedModelRow` - Displays both built-in and custom models consistently
- Pricing integration with PricingRegistry for built-in models

#### 3. Updated GeneralSettingsView
**Location**: `Views/Settings/GeneralSettingsView.swift`

Provider and model selection now support custom providers:
- Provider picker shows "Built-in Providers" and "Custom Providers" sections
- Model picker dynamically shows models for selected provider
- Selected model card displays pricing (if available) and context window
- Icon changes based on provider type (cpu.fill for built-in, server.rack for custom)

#### 4. Updated APIKeysSettingsView
**Location**: `Views/Settings/APIKeysSettingsView.swift`

New section for custom provider API keys:
- "Custom Provider Keys" section appears when custom providers exist
- `CustomProviderAPIKeyRow` - Shows provider name, endpoint, and configuration status
- `CustomProviderAPIKeyInputSheet` - Modal for entering API keys

#### 5. Updated SettingsTabView
**Location**: `Views/Settings/SettingsTabView.swift`

New "Custom" tab added between "API Keys" and "Memory":
- Icon: `slider.horizontal.3`
- Displays CustomProvidersSettingsView

### ViewModel Updates

#### SettingsViewModel Extensions
**Location**: `ViewModels/SettingsViewModel.swift` and `UnifiedProviderSelectionView.swift`

New methods for custom provider management:
- `addCustomProvider(_:)` - Add new provider
- `updateCustomProvider(_:)` - Update existing provider
- `deleteCustomProvider(id:)` - Delete provider and its API key
- `getCustomProvider(id:)` - Retrieve provider by ID
- `saveCustomProviderAPIKey(_:providerId:providerName:)` - Save API key
- `getCustomProviderAPIKey(providerId:)` - Retrieve API key
- `clearCustomProviderAPIKey(providerId:providerName:)` - Clear API key
- `isCustomProviderConfigured(_:)` - Check if API key is configured

Unified provider methods:
- `allUnifiedProviders()` - Get all providers (built-in + custom)
- `currentUnifiedProvider()` - Get currently selected provider
- `currentUnifiedModel()` - Get currently selected model
- `selectUnifiedProvider(_:)` - Switch to a different provider
- `selectUnifiedModel(_:)` - Switch to a different model

## User Workflow

### Adding a Custom Provider

1. **Navigate to Settings > Custom tab**
2. **Click "Add Custom Provider"**
3. **Fill in provider details**:
   - Provider Name (required): e.g., "LocalLM"
   - API Endpoint (required): e.g., "https://api.local-llm.com"
4. **Add models** (click + to add more):
   - Model Code (required): e.g., "llama-3.1-70b"
   - Friendly Name (optional): e.g., "Llama 3.1 70B"
   - Context Window: Default 128000
   - Description (optional): Brief description
   - Advanced Pricing (optional):
     - Input Price per 1M tokens
     - Output Price per 1M tokens
     - Cached Input Price (optional)
5. **Click Save**
6. **Navigate to Settings > API Keys**
7. **Find provider in "Custom Provider Keys" section**
8. **Click menu > "Add Key"**
9. **Paste API key and save**
10. **Navigate to Settings > General**
11. **Select custom provider from "AI Provider" dropdown** (under "Custom Providers" section)
12. **Select desired model** from "Model" dropdown

### Editing a Custom Provider

1. Navigate to Settings > Custom tab
2. Find the provider card
3. Click the menu button (•••)
4. Select "Edit"
5. Make changes
6. Click Save

### Deleting a Custom Provider

1. Navigate to Settings > Custom tab
2. Find the provider card
3. Click the menu button (•••)
4. Select "Delete"
5. Confirm deletion
6. API key is automatically removed from Keychain

## Backend Integration

### API Request Format

Custom providers use the existing `openai-compatible` provider in the backend API. When making requests with a custom provider selected:

```json
{
  "conversationId": "conv-123",
  "message": "User message",
  "provider": "openai-compatible",
  "model": "{modelCode}",
  "openaiCompatible": {
    "apiKey": "{user-api-key}",
    "baseUrl": "{apiEndpoint}"
  },
  "options": {
    "temperature": 0.7,
    "maxTokens": 2048
  }
}
```

The backend already supports this format (see `conversationAPI.md`), so no backend changes are required!

### ConversationService Integration

The ConversationService needs to be updated to:
1. Detect when a custom provider is selected (check `settings.selectedCustomProviderId`)
2. Use `provider: "openai-compatible"` in API requests
3. Pass `openaiCompatible` object with apiKey and baseUrl
4. Use the model's `modelCode` as the model parameter

## Validation & Error Handling

### Provider Configuration Validation
- Provider name: Non-empty string
- API endpoint: Valid HTTPS URL
- At least one model must be configured
- Model codes must be unique within provider

### API Key Validation
- Non-empty string
- Stored securely in Keychain
- Status indicator shows configuration state

### Fallback Behavior
- Friendly Name → Provider Name
- Description → "Custom Provider {N}, Model {M}"
- No pricing → Hide pricing row entirely
- Invalid provider/model → Fall back to default Anthropic/Sonnet

## Design Patterns

### Consistent UI/UX
- Custom providers integrate seamlessly with built-in providers
- Same card-based layout throughout settings
- Consistent color scheme (AppColors.signalMercury for accents)
- Standard icons: server.rack for custom providers, cpu.fill for built-in
- Mercury accent color for interactive elements

### State Management
- Settings persist via UserDefaults (JSON encoding)
- API keys persist via Keychain (secure storage)
- ViewModel as single source of truth
- Generic KeyPath-based updates for settings

### Component Reusability
- `GeneralSettingsSection` for grouped settings
- `InfoBanner` for informational messages
- `EmptyStateView` for empty lists
- `CustomTextFieldStyle` for consistent form inputs
- `UnifiedModelRow` for displaying all model types

## Testing Checklist

### Configuration Flow
- [ ] Add new custom provider with single model
- [ ] Add custom provider with multiple models
- [ ] Edit existing provider
- [ ] Delete provider
- [ ] Add model to existing provider
- [ ] Remove model from provider
- [ ] Configure API key for custom provider
- [ ] Update API key
- [ ] Remove API key

### Selection Flow
- [ ] Select custom provider from General settings
- [ ] Select custom model after selecting custom provider
- [ ] Switch between built-in and custom providers
- [ ] Switch between custom providers
- [ ] Verify selection persists across app restarts

### Validation
- [ ] Try to save provider without name → Error
- [ ] Try to save provider with invalid URL → Error
- [ ] Try to save provider without models → Error
- [ ] Try to save model without code → Disabled save button
- [ ] Verify unique model codes within provider

### Display
- [ ] Verify fallback names work correctly
- [ ] Verify auto-generated descriptions
- [ ] Verify pricing displays correctly when provided
- [ ] Verify pricing hides when not provided
- [ ] Verify context window displays correctly

### Integration
- [ ] Test API request with custom provider
- [ ] Verify correct parameters sent to backend
- [ ] Test error handling for invalid API keys
- [ ] Test error handling for invalid endpoints

## File Summary

### New Files Created
1. `Models/Settings.swift` - Extended with custom provider models
2. `Views/Settings/CustomProvidersSettingsView.swift` - Main custom provider management UI
3. `Views/Settings/UnifiedProviderSelectionView.swift` - Unified provider/model interface
4. `Docs/CustomProvidersFeature.md` - This documentation

### Modified Files
1. `Models/Settings.swift` - Added custom provider data structures
2. `Services/Settings/SettingsStorage.swift` - Added custom provider API key methods
3. `ViewModels/SettingsViewModel.swift` - Added custom provider management methods
4. `Views/Settings/SettingsTabView.swift` - Added Custom tab
5. `Views/Settings/GeneralSettingsView.swift` - Updated provider/model selection
6. `Views/Settings/APIKeysSettingsView.swift` - Added custom provider keys section

## Future Enhancements

### Potential Improvements
1. **Import/Export**: Allow users to export/import provider configurations
2. **Provider Templates**: Pre-configured templates for popular providers (Ollama, LM Studio, etc.)
3. **Model Testing**: Test connection button to verify endpoint and model work
4. **Usage Tracking**: Track token usage and costs per custom provider
5. **Provider Icons**: Allow custom icons for providers
6. **Batch Operations**: Add/edit multiple models at once
7. **Search**: Search/filter providers and models
8. **Provider Categories**: Group custom providers by type
9. **Model Comparison**: Side-by-side comparison of models
10. **Shared Configurations**: Share provider configs with other users

## Notes

### Design Decisions
- **Unified Provider System**: Created `UnifiedProvider` and `UnifiedModel` enums instead of modifying `AIProvider` enum to maintain backward compatibility and separation of concerns.
- **Separate API Key Storage**: Custom provider API keys stored separately in Keychain to allow per-provider security and management.
- **Auto-naming Convention**: Consistent fallback naming (Custom Provider N, Model M) ensures no blank fields in UI.
- **Advanced Pricing Accordion**: Cached input pricing is optional and hidden in accordion to avoid overwhelming users.
- **Provider Index Tracking**: Custom providers tracked by UUID for stability across edits and deletions.

### Backend Compatibility
The existing backend API already supports custom OpenAI-compatible providers through the `openai-compatible` provider type, so this feature required zero backend changes!
