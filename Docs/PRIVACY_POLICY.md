# Axon Privacy Policy

**Effective Date:** December 11, 2025
**Last Updated:** December 11, 2025

---

## Introduction

Axon ("we," "our," or "the app") is developed by methodolojee, a sole proprietorship operated by Thomas Oury in Colorado, USA. This privacy policy explains how Axon handles your data.

**The short version:** Axon is a local-first app. Your data stays on your device. We don't collect it, we can't see it, and we don't sell it.

---

## Data We Collect

### Data We Collect: None

methodolojee does not collect, store, or transmit any of your personal data to our servers. We have no servers that receive your data. We have no analytics. We have no tracking.

---

## Data Stored on Your Device

Axon stores the following data locally on your device:

| Data Type | Storage Location | Purpose |
|-----------|------------------|---------|
| Conversations | Device (SwiftData) | Your chat history with AI assistants |
| Memories | Device (SwiftData) | Contextual information for personalized responses |
| API Keys | iOS Keychain | Authentication with AI providers you configure |
| App Settings | Device (JSON file) | Your preferences and configuration |

This data:
- Never leaves your device unless you explicitly enable cloud sync or use AI providers
- Is encrypted using iOS Data Protection (AES-256)
- Is deleted when you uninstall the app
- Can be exported or deleted at any time through the app

---

## Third-Party Services

### AI Providers

When you use Axon to chat with AI assistants, your messages are sent directly to the AI provider you configure. Axon supports:

- **OpenAI** (ChatGPT, GPT-4, etc.)
- **Anthropic** (Claude)
- **Google** (Gemini)
- **xAI** (Grok)
- **Custom providers** you configure

**Important:** When you send a message, that message and any context (like memories) are transmitted to your chosen AI provider. This data is subject to their privacy policies:

| Provider | Privacy Policy |
|----------|---------------|
| OpenAI | [openai.com/privacy](https://openai.com/privacy) |
| Anthropic | [anthropic.com/privacy](https://anthropic.com/privacy) |
| Google | [policies.google.com/privacy](https://policies.google.com/privacy) |
| xAI | [x.ai/privacy](https://x.ai/privacy) |

We encourage you to review these policies, particularly regarding:
- Data retention periods
- Whether your data is used for model training
- How to request data deletion

### Text-to-Speech (Optional)

If you enable text-to-speech features:
- **ElevenLabs**: AI responses may be sent to ElevenLabs for voice synthesis. See [elevenlabs.io/privacy](https://elevenlabs.io/privacy)
- **Apple TTS**: Uses on-device processing; no data transmitted

### iCloud Sync (Optional)

If you enable iCloud sync:
- Your conversations and memories may be synced via Apple's iCloud CloudKit
- This data is protected by Apple's end-to-end encryption
- Only accessible with your Apple ID
- Subject to [Apple's Privacy Policy](https://www.apple.com/legal/privacy/)

### Custom Backend (Optional)

If you configure a custom backend URL:
- Data may be transmitted to your self-hosted server
- You control that infrastructure and its privacy practices
- We recommend using HTTPS and proper authentication

---

## API Keys

Your API keys (for OpenAI, Anthropic, etc.) are:
- Stored exclusively in the iOS Keychain with hardware-backed encryption
- Never transmitted to methodolojee
- Never backed up to iCloud
- Only sent to the respective AI provider for authentication

---

## Data Security

Axon implements multiple layers of security:

1. **Encryption at Rest**: All local data encrypted with iOS Data Protection (AES-256)
2. **Keychain Security**: API keys stored with hardware-backed encryption (Secure Enclave)
3. **Transport Security**: All network requests use TLS 1.3
4. **App Lock**: Optional biometric (Face ID/Touch ID) or passcode protection
5. **Privacy Blur**: Optional blur in app switcher to hide content

For technical details, see our [Encryption Documentation](https://github.com/methodolojee/Axon/blob/main/Docs/ENCRYPTION.md).

---

## Children's Privacy

Axon is not directed at children under 13. We do not knowingly collect data from children. Since we don't collect any data at all, there is no children's data to protect. However, AI providers may have their own age restrictions.

---

## Your Rights

Because your data is stored locally on your device, you have complete control:

### Access
- View all your conversations and memories in the app
- Export data via Settings

### Deletion
- Delete individual conversations or memories
- Clear all data via Settings
- Uninstall the app to remove all local data

### Portability
- Export conversations as JSON
- Export memories as JSON

### For AI Provider Data
To exercise rights over data sent to AI providers (access, deletion, etc.), contact those providers directly using the links above.

---

## European Users (GDPR)

For users in the European Economic Area:

- **Data Controller**: For local data, you are the controller. For data sent to AI providers, those providers are controllers.
- **Legal Basis**: Consent (you choose to send messages) and contract performance (providing the app's functionality)
- **Data Transfers**: When you use US-based AI providers, data is transferred outside the EU under those providers' data transfer mechanisms
- **No methodolojee Processing**: We do not process your personal data

---

## California Users (CCPA)

For California residents:

- **Sale of Data**: We do not sell your personal information
- **Collection**: We do not collect your personal information
- **Categories Collected**: None
- **Right to Know/Delete**: Your data is local; you control it entirely

---

## Changes to This Policy

We may update this privacy policy occasionally. Changes will be posted at:
- This document in the app's repository
- The App Store listing

Material changes will be noted with an updated "Last Updated" date.

---

## Contact Us

For privacy questions or concerns:

**Thomas Oury / methodolojee**
Email: tom@methodolojee.org
Address: 6089 Vivian Street, Arvada, CO 80004, USA

GitHub: [github.com/methodolojee/Axon](https://github.com/methodolojee/Axon)

---

## Summary

| Question | Answer |
|----------|--------|
| Do you collect my data? | No |
| Do you sell my data? | No |
| Can you see my conversations? | No |
| Where is my data stored? | On your device only |
| Who receives my messages? | Only the AI provider you choose |
| Can I delete my data? | Yes, anytime, completely |
| Do you use analytics? | No |
| Do you track me? | No |

---

*This privacy policy is provided under the MIT License along with the Axon source code.*
