# ElevenLabs Integration Guide

This document provides a comprehensive overview of the ElevenLabs integration within the NeurXAxonChat system. It covers the backend architecture, API endpoints, frontend hooks, and security implementation.

## Architecture Overview

The system uses a secure proxy architecture to interact with ElevenLabs. Direct calls from the frontend to ElevenLabs are **not** permitted to ensure API key security.

1.  **Frontend (`useTTS` Hook)**: Initiates requests and manages audio playback state.
2.  **Firebase Cloud Function (`apiElevenLabs`)**: Acts as a secure proxy. It handles authentication, retrieves the encrypted API key, calls ElevenLabs, and manages audio storage.
3.  **Firebase Storage**: Stores generated audio files for caching and persistence.
4.  **ElevenLabs API**: The external service provider for TTS and STT.

## Security & Authentication

*   **API Key Storage**: The ElevenLabs API key is stored in the user's encrypted settings document in Firestore (`users/{userId}/settings/appSettings`).
*   **Encryption**: The key is encrypted using the system's encryption service. The backend retrieves and decrypts this key on-the-fly for each request.
*   **Authentication**: All requests to `apiElevenLabs` require a valid Firebase ID token in the `Authorization` header.

## Backend API Reference

**Endpoint**: `https://us-central1-neurx-8f122.cloudfunctions.net/apiElevenLabs`
**Method**: `POST`

All requests must include a JSON body with an `action` parameter.

### Common Actions

#### 1. Text-to-Speech Generation (`tts_generate`)

Generates audio from text. Supports long text via automatic chunking.

**Parameters:**
*   `action`: `"tts_generate"`
*   `text`: String (The text to convert)
*   `voiceId`: String (ElevenLabs Voice ID)
*   `model`: String (e.g., `"eleven_turbo_v2_5"`)
*   `conversationId`: String (Optional, for storage organization)
*   `messageId`: String (Optional, for storage organization)
*   `voiceSettings`: Object (Optional, stability/similarity settings)

**Response:**
```json
{
  "success": true,
  "audioUrls": ["https://..."], // Signed URLs to stored audio chunks
  "chunkCount": 1,
  "metadata": { ... }
}
```

#### 2. Speech-to-Text (`stt_transcribe`)

Transcribes audio using the Scribe model.

**Parameters:**
*   `action`: `"stt_transcribe"`
*   `cloudStorageUrl`: String (URL of the audio file to transcribe)
*   `modelId`: `"scribe_v1"`
*   `diarize`: Boolean (Optional)

#### 3. Voice Management

*   **List Voices**: `action: "voices_list"`
*   **Search Voices**: `action: "voices_search"`, `category`, `language`
*   **Get Voice**: `action: "voices_get"`, `voiceId`
*   **Get Settings**: `action: "voices_get_settings"`, `voiceId`

#### 4. User Info

*   **Get User Info**: `action: "user_info"`
*   **Get Subscription**: `action: "user_subscription"`

### Audio Storage

Generated audio is automatically stored in Firebase Storage to prevent redundant generation costs.

**Path Structure**:
`users/{userId}/audio/{conversationId}/{messageId}/chunk_{index}.mp3`

## Frontend Integration

### `useTTS` Hook

Located in `src/hooks/useTTS.ts`, this hook manages the entire TTS lifecycle.

#### Key Features
*   **Automatic Caching**: Checks memory cache and Firebase Storage before generating new audio.
*   **Chunked Playback**: Handles seamless playback of multiple audio chunks for long messages.
*   **State Management**: Tracks playing state, generation status, and errors.

#### Usage Example

```typescript
import { useTTS } from '../hooks/useTTS';

const MyComponent = () => {
  const { 
    generateAudioForMessage, 
    playMessageAudio, 
    isGenerating, 
    currentlyPlaying 
  } = useTTS();

  const handlePlay = async (message) => {
    // 1. Generate or retrieve audio
    const audioUrls = await generateAudioForMessage(
      message.id,
      message.content,
      conversationId,
      'assistant'
    );

    // 2. Play the audio
    if (audioUrls) {
      playMessageAudio(message.id, audioUrls);
    }
  };

  return (
    <button onClick={() => handlePlay(message)} disabled={isGenerating(message.id)}>
      {currentlyPlaying?.messageId === message.id ? 'Playing...' : 'Play'}
    </button>
  );
};
```

### Types (`src/types/tts.ts`)

Key type definitions for type safety:

*   `TTSModel`: Supported models (`eleven_turbo_v2_5`, `eleven_multilingual_v2`, etc.)
*   `TTSSettings`: Configuration interface for user preferences.
*   `VoiceSettings`: Fine-tuning parameters (stability, similarity boost).

## Data Flow Diagram

1.  **User Request**: User clicks "Play" on a message.
2.  **Cache Check**: `useTTS` checks local `audioCache`.
3.  **Storage Check**: If not in cache, checks Firebase Storage for existing files.
4.  **Generation (if needed)**:
    *   `useTTS` calls `apiElevenLabs` with `tts_generate`.
    *   Backend decrypts API key.
    *   Backend calls ElevenLabs API.
    *   Backend saves audio to Firebase Storage.
    *   Backend returns signed URLs.
5.  **Playback**: `useTTS` plays the audio URLs sequentially.

## Troubleshooting

*   **"ElevenLabs API key not configured"**: Ensure the user has entered their API key in the Settings dialog.
*   **"Invalid ID token"**: The user's session may have expired. Re-authentication is required.
*   **Audio not playing**: Check browser autoplay policies and ensure the `audioUrls` are valid signed URLs.
*   **Rate Limits**: Check the `user_subscription` endpoint to verify quota usage.
