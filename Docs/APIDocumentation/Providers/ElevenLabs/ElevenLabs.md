# ElevenLabs API CURL Documentation

## Authentication

All ElevenLabs API requests require authentication using an API key in the `xi-api-key` header[1][2].

```bash
# Get your API key from: https://elevenlabs.io/app/settings/api-keys
XI_API_KEY="your_api_key_here"
```

***

## Text-to-Speech (TTS)

### Basic TTS Request

Convert text to speech using a specific voice[3][4].

```bash
curl -X POST "https://api.elevenlabs.io/v1/text-to-speech/{VOICE_ID}" \
  -H "Content-Type: application/json" \
  -H "xi-api-key: ${XI_API_KEY}" \
  -H "accept: audio/mpeg" \
  -d '{
    "text": "Hello! This is a test of the ElevenLabs text to speech API.",
    "model_id": "eleven_multilingual_v2",
    "voice_settings": {
      "stability": 0.5,
      "similarity_boost": 0.75,
      "style": 0.0,
      "use_speaker_boost": true
    }
  }' \
  --output output.mp3
```

### TTS Models Available

**Available Models**[3][5]:
- `eleven_multilingual_v2` - Most emotionally rich, expressive (10,000 char limit)
- `eleven_turbo_v2_5` - High quality, low-latency (40,000 char limit)
- `eleven_turbo_v2` - High quality, low-latency (30,000 char limit)
- `eleven_flash_v2_5` - Ultra-low 75ms latency (40,000 char limit)
- `eleven_flash_v2` - Fast, affordable (30,000 char limit)
- `eleven_monolingual_v1` - English only

### Advanced TTS with Output Format

```bash
curl -X POST "https://api.elevenlabs.io/v1/text-to-speech/{VOICE_ID}?output_format=mp3_44100_128" \
  -H "Content-Type: application/json" \
  -H "xi-api-key: ${XI_API_KEY}" \
  -d '{
    "text": "Your text here",
    "model_id": "eleven_flash_v2_5",
    "voice_settings": {
      "stability": 0.5,
      "similarity_boost": 0.75
    },
    "optimize_streaming_latency": 3,
    "seed": 12345
  }' \
  --output output.mp3
```

### Output Formats[3]

**MP3 Formats:**
- `mp3_22050_32` - 22.05kHz @ 32kbps (default)
- `mp3_44100_32` - 44.1kHz @ 32kbps
- `mp3_44100_64` - 44.1kHz @ 64kbps
- `mp3_44100_96` - 44.1kHz @ 96kbps
- `mp3_44100_128` - 44.1kHz @ 128kbps
- `mp3_44100_192` - 44.1kHz @ 192kbps (requires Creator tier)

**PCM Formats:**
- `pcm_16000` - 16kHz (requires Pro tier)
- `pcm_22050` - 22.05kHz
- `pcm_24000` - 24kHz
- `pcm_44100` - 44.1kHz (requires Pro tier)

**Other Formats:**
- `ulaw_8000` - μ-law 8kHz (telephony)
- `opus_16000` - Opus 16kHz
- `opus_24000` - Opus 24kHz

### TTS Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `text` | string | Text to convert (max varies by model) |
| `model_id` | string | Model to use for generation |
| `voice_settings.stability` | float (0-1) | Voice consistency control |
| `voice_settings.similarity_boost` | float (0-1) | Enhances similarity to original voice |
| `voice_settings.style` | float (0-1) | Speaking style intensity |
| `voice_settings.use_speaker_boost` | boolean | Enhances speaker clarity |
| `optimize_streaming_latency` | int (0-4) | Latency optimization level[4] |
| `seed` | integer | For deterministic output |
| `previous_text` | string | Maintains prosody flow |
| `next_text` | string | Maintains prosody flow |

### Streaming TTS via WebSocket

For real-time streaming applications[6][7]:

```bash
# WebSocket endpoint
wss://api.elevenlabs.io/v1/text-to-speech/{VOICE_ID}/stream-input?model_id={MODEL_ID}
```

**WebSocket Protocol** (JSON messages):

```json
{
  "text": "Text to stream",
  "voice_settings": {
    "stability": 0.5,
    "similarity_boost": 0.75
  },
  "generation_config": {
    "chunk_length_schedule": [120, 160, 250, 290]
  }
}
```

***

## Speech-to-Text (STT)

### Scribe v1 - Speech to Text

Transcribe audio files with 99 language support, speaker diarization, and word-level timestamps[5][8].

```bash
curl -X POST "https://api.elevenlabs.io/v1/speech-to-text" \
  -H "xi-api-key: ${XI_API_KEY}" \
  -F "file=@audio_file.mp3" \
  -F "model_id=scribe_v1" \
  -F "language_code=eng" \
  -F "diarize=true" \
  -F "tag_audio_events=true" \
  -F "num_speakers=2"
```

### STT with Cloud Storage URL

```bash
curl -X POST "https://api.elevenlabs.io/v1/speech-to-text" \
  -H "Content-Type: application/json" \
  -H "xi-api-key: ${XI_API_KEY}" \
  -d '{
    "cloud_storage_url": "https://example.com/audio.mp3",
    "model_id": "scribe_v1",
    "language_code": "eng",
    "diarize": true,
    "tag_audio_events": true,
    "num_speakers": 2
  }'
```

### STT Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `file` | file | Audio file to transcribe (< 2GB) |
| `cloud_storage_url` | string | HTTPS URL of audio file |
| `model_id` | string | Use `scribe_v1` |
| `language_code` | string | ISO language code (e.g., "eng", "spa") |
| `diarize` | boolean | Enable speaker identification (up to 10 speakers) |
| `tag_audio_events` | boolean | Tag laughter, applause, etc. |
| `num_speakers` | integer | Expected number of speakers (optional) |
| `diarization_threshold` | float | Speaker separation sensitivity[8] |
| `use_multi_channel` | boolean | Process multi-channel audio separately |
| `webhook` | boolean | Enable async processing with webhooks |

### STT Response Format

```json
{
  "text": "Full transcription text",
  "words": [
    {
      "text": "word",
      "start": 0.0,
      "end": 0.5,
      "speaker_id": 0
    }
  ],
  "speakers": [
    {
      "speaker_id": 0,
      "segments": [...]
    }
  ],
  "audio_events": [
    {
      "type": "laughter",
      "start": 5.2,
      "end": 5.8
    }
  ]
}
```

***

## Voice Library Management

### List All Available Voices

Get all voices in your library including custom cloned voices[9][10].

```bash
curl -X GET "https://api.elevenlabs.io/v1/voices" \
  -H "xi-api-key: ${XI_API_KEY}" \
  -H "Accept: application/json"
```

### Response Format

```json
{
  "voices": [
    {
      "voice_id": "21m00Tcm4TlvDq8ikWAM",
      "name": "Rachel",
      "category": "premade",
      "labels": {
        "accent": "american",
        "age": "young",
        "gender": "female"
      },
      "preview_url": "https://...",
      "available_for_tiers": [],
      "settings": {
        "stability": 0.75,
        "similarity_boost": 0.75
      }
    }
  ]
}
```

### Search Voices (v2 Endpoint)

Advanced search with filtering and pagination[11].

```bash
curl -X GET "https://api.elevenlabs.io/v2/voices?page_size=100&category=premade&language=en" \
  -H "xi-api-key: ${XI_API_KEY}" \
  -H "Accept: application/json"
```

### Get Specific Voice Details

```bash
curl -X GET "https://api.elevenlabs.io/v1/voices/{VOICE_ID}" \
  -H "xi-api-key: ${XI_API_KEY}"
```

### Get Voice Settings

```bash
curl -X GET "https://api.elevenlabs.io/v1/voices/{VOICE_ID}/settings" \
  -H "xi-api-key: ${XI_API_KEY}"
```

### Update Voice Settings

```bash
curl -X POST "https://api.elevenlabs.io/v1/voices/{VOICE_ID}/settings/edit" \
  -H "Content-Type: application/json" \
  -H "xi-api-key: ${XI_API_KEY}" \
  -d '{
    "stability": 0.5,
    "similarity_boost": 0.75,
    "style": 0.0,
    "use_speaker_boost": true
  }'
```

***

## Voice Cloning & Creation

### Instant Voice Clone

Clone a voice from audio samples.

```bash
curl -X POST "https://api.elevenlabs.io/v1/voices/add" \
  -H "xi-api-key: ${XI_API_KEY}" \
  -F "name=My Custom Voice" \
  -F "description=A cloned voice" \
  -F "files=@sample1.mp3" \
  -F "files=@sample2.mp3" \
  -F "labels={\"accent\":\"american\",\"age\":\"young\"}"
```

### Edit Voice

```bash
curl -X POST "https://api.elevenlabs.io/v1/voices/{VOICE_ID}/edit" \
  -H "xi-api-key: ${XI_API_KEY}" \
  -F "name=Updated Voice Name" \
  -F "description=Updated description" \
  -F "files=@new_sample.mp3"
```

### Delete Voice

```bash
curl -X DELETE "https://api.elevenlabs.io/v1/voices/{VOICE_ID}" \
  -H "xi-api-key: ${XI_API_KEY}"
```

***

## Speech-to-Speech (Voice Changer)

Convert audio with content and emotion to a different voice[12].

```bash
curl -X POST "https://api.elevenlabs.io/v1/speech-to-speech/{VOICE_ID}?output_format=mp3_44100_128" \
  -H "xi-api-key: ${XI_API_KEY}" \
  -F "audio=@input_audio.mp3" \
  -F "model_id=eleven_multilingual_sts_v2" \
  -F "voice_settings={\"stability\":0.5,\"similarity_boost\":0.75}" \
  --output output.mp3
```

***

## Additional Endpoints

### Get Models List

```bash
curl -X GET "https://api.elevenlabs.io/v1/models" \
  -H "xi-api-key: ${XI_API_KEY}"
```

### Get User Info & Subscription

```bash
curl -X GET "https://api.elevenlabs.io/v1/user" \
  -H "xi-api-key: ${XI_API_KEY}"
```

### Get Usage Statistics

```bash
curl -X GET "https://api.elevenlabs.io/v1/user/subscription" \
  -H "xi-api-key: ${XI_API_KEY}"
```

***

## Complete LLM Integration Example

### LLM → Voice Service Flow

```bash
# Step 1: Get LLM response (example with any LLM)
LLM_RESPONSE="Hello! How can I assist you today?"

# Step 2: Convert to speech
curl -X POST "https://api.elevenlabs.io/v1/text-to-speech/21m00Tcm4TlvDq8ikWAM" \
  -H "Content-Type: application/json" \
  -H "xi-api-key: ${XI_API_KEY}" \
  -d "{
    \"text\": \"${LLM_RESPONSE}\",
    \"model_id\": \"eleven_flash_v2_5\",
    \"voice_settings\": {
      \"stability\": 0.5,
      \"similarity_boost\": 0.75
    }
  }" \
  --output llm_response.mp3
```

### Voice → LLM Service Flow

```bash
# Step 1: User speaks, record audio as user_input.mp3

# Step 2: Transcribe with ElevenLabs
TRANSCRIPTION=$(curl -X POST "https://api.elevenlabs.io/v1/speech-to-text" \
  -H "xi-api-key: ${XI_API_KEY}" \
  -F "file=@user_input.mp3" \
  -F "model_id=scribe_v1" \
  -F "language_code=eng" | jq -r '.text')

# Step 3: Send to LLM (example structure)
# LLM_RESPONSE=$(curl -X POST "your_llm_endpoint" -d "{\"prompt\": \"${TRANSCRIPTION}\"}")

# Step 4: Convert LLM response back to speech
# (Use TTS example above)
```

***

## Best Practices

### For Real-Time Applications

1. **Use Flash models**: `eleven_flash_v2_5` for lowest latency (75ms)[3]
2. **Enable latency optimization**: Set `optimize_streaming_latency` to 3 or 4
3. **Use WebSocket streaming**: For chunk-by-chunk processing[6]
4. **Lower quality formats**: Use `mp3_22050_32` or `pcm_16000` for speed

### For High Quality

1. **Use Multilingual v2**: `eleven_multilingual_v2` for most expressive output
2. **Higher bitrates**: Use `mp3_44100_192` or `pcm_44100`
3. **Tune voice settings**: Adjust stability (0.5-0.75) and similarity_boost (0.75-0.85)
4. **Include context**: Use `previous_text` and `next_text` for natural flow

### For Transcription

1. **Specify language**: Improves accuracy when language is known
2. **Enable diarization**: For multi-speaker conversations
3. **Tag audio events**: Capture non-speech context (laughter, applause)
4. **Use webhooks**: For async processing of large files

### Error Handling

```bash
# Check response status and handle errors
RESPONSE=$(curl -w "\n%{http_code}" -X POST "https://api.elevenlabs.io/v1/text-to-speech/{VOICE_ID}" \
  -H "xi-api-key: ${XI_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"text":"test","model_id":"eleven_multilingual_v2"}' \
  --output output.mp3)

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

if [ "$HTTP_CODE" -eq 200 ]; then
  echo "Success!"
else
  echo "Error: HTTP $HTTP_CODE"
fi
```

***

## Language Support

ElevenLabs supports **32 languages** with Flash v2.5 and **29 languages** with Multilingual v2[3]:

English (USA, UK, Australia, Canada), Japanese, Chinese, German, Hindi, French (France, Canada), Korean, Portuguese (Brazil, Portugal), Italian, Spanish (Spain, Mexico), Indonesian, Dutch, Turkish, Filipino, Polish, Swedish, Bulgarian, Romanian, Arabic (Saudi Arabia, UAE), Czech, Greek, Finnish, Croatian, Malay, Slovak, Danish, Tamil, Ukrainian, Russian, Hungarian, Norwegian, Vietnamese.

***

## Pricing Considerations

- **Character limits** vary by model (10,000 to 40,000 chars)[5]
- **STT pricing**: $0.22-$0.40 per hour of audio[13]
- **Free tier**: Includes 2.5 hours of STT transcription[14]
- **Higher quality formats**: MP3 192kbps and PCM 44.1kHz require paid tiers[3]

This comprehensive guide provides all the CURL commands needed to build a complete LLM-to-voice and voice-to-LLM service using ElevenLabs API.

Sources
[1] Quickstart - ElevenLabs https://elevenlabs.io/docs/developer-guides/quickstart
[2] Api key to http - Questions - n8n Community https://community.n8n.io/t/api-key-to-http/84652
[3] Text to Speech | ElevenLabs Documentation https://elevenlabs.io/docs/capabilities/text-to-speech
[4] Create speech | ElevenLabs Documentation https://elevenlabs.io/docs/api-reference/text-to-speech/convert
[5] Models | ElevenLabs Documentation https://elevenlabs.io/docs/models
[6] ElevenLabs Streaming API Documentation With Samples https://play.ht/blog/elevenlabs-streaming-api/
[7] WebSocket | ElevenLabs Documentation https://elevenlabs.io/docs/api-reference/text-to-speech/v-1-text-to-speech-voice-id-stream-input
[8] Create transcript | ElevenLabs Documentation https://elevenlabs.io/docs/api-reference/speech-to-text/convert
[9] Getting Started - ElevenLabs https://elevenlabs-sdk.mintlify.app/api-reference/getting-started
[10] Get Voices - ElevenLabs https://elevenlabs-sdk.mintlify.app/api-reference/get-voices
[11] List voices | ElevenLabs Documentation https://elevenlabs.io/docs/api-reference/voices/search
[12] Voice changer | ElevenLabs Documentation https://elevenlabs.io/docs/api-reference/speech-to-speech/convert
[13] Support for ElevenLabs' STT Model (scribe_v1) · danny- ... https://github.com/danny-avila/LibreChat/discussions/6640
[14] Transcribing Pipe's Video Recordings With ElevenLabs' New ... https://blog.addpipe.com/transcribing-pipe-recordings-with-elevenlabs-new-speech-to-text-model-scribe/
[15] eleven_multilingual_v2 | AI/ML API Documentation https://docs.aimlapi.com/api-references/speech-models/text-to-speech/elevenlabs/eleven_multilingual_v2
[16] How to format 'Post' for Elevenlabs.api (Text to speech api) https://community.activepieces.com/t/how-to-format-post-for-elevenlabs-api-text-to-speech-api/771
[17] AI Voice: ElevenLabs & OpenAI TTS API Guide | APIpie https://apipie.ai/docs/Features/Voices
[18] ElevenLabs STT https://navinspire.ai/RAG/documentation/components/voice-message/elevenlabs-stt
[19] How to use custom voices in the ElevenLabs API: A Python tutorial https://www.youtube.com/watch?v=r5aJeq-f0OY
[20] Getting Started with ElevenLabs Text-to-Speech API - DEV Community https://dev.to/ssk14/getting-started-with-elevenlabs-text-to-speech-api-21j4
[21] ElevenLabs - Pipecat https://docs.pipecat.ai/server/services/stt/elevenlabs
[22] The official Python SDK for the ElevenLabs API. https://github.com/elevenlabs/elevenlabs-python
[23] ElevenLabs Text to Speech API https://www.youtube.com/watch?v=9yno3cFLc-Q
[24] GitHub - hlastras/elevenlabs_stt https://github.com/hlastras/elevenlabs_stt
[25] Voice Library | ElevenLabs Documentation https://elevenlabs.io/docs/product-guides/voices/voice-library
[26] How to use the ElevenLabs API: Python text-to-speech tutorial with examples https://www.youtube.com/watch?v=1t9FhxQcDiw
[27] Creating A Transcript https://elevenlabs.io/docs/product-guides/playground/speech-to-text
[28] ️🎤 elevenlabs-api is an open source Java wrapper around ... https://github.com/Andrewcpu/elevenlabs-api
[29] Text-To-Speech - ElevenLabs API ? · schreibfaul1 ESP32-audioI2S · Discussion #707 https://github.com/schreibfaul1/ESP32-audioI2S/discussions/707
[30] Speech-to-text, text-to-speech with ElevenLabs https://github.com/CyR1en/ElevenLabsS4TS
[31] ElevenLabs Voice API with Python https://www.youtube.com/watch?v=3BMy5KPa_kQ
[32] carleeno/elevenlabs_tts: Custom TTS Integration using ElevenLabs ... https://github.com/carleeno/elevenlabs_tts
[33] Get voice | ElevenLabs Documentation https://elevenlabs.io/docs/api-reference/voices/get
[34] Get audio from sample https://elevenlabs.io/docs/api-reference/voices/samples/audio/get
[35] Edit Voice - ElevenLabs https://elevenlabs-sdk.mintlify.app/api-reference/edit-voice
[36] ElevenLabs Scribe: The World's Most Accurate Speech-to-Text API (Quick Tutorial) https://www.youtube.com/watch?v=bKrkBBRsRgE
[37] Multi-Context WebSocket | ElevenLabs Documentation https://elevenlabs.io/docs/api-reference/text-to-speech/v-1-text-to-speech-voice-id-multi-stream-input
[38] How to Create AI Voice Over Videos using an API https://creatomate.com/blog/how-to-create-voice-over-videos-using-an-api
[39] Websockets - ElevenLabs https://elevenlabs-sdk.mintlify.app/api-reference/websockets
[40] Streaming - ElevenLabs https://elevenlabs-sdk.mintlify.app/api-reference/speech-to-speech-streaming
[41] Streaming Speech with ElevenLabs - Edge Functions https://supabase.com/docs/guides/functions/examples/elevenlabs-generate-speech-stream
[42] Edit voice settings | ElevenLabs Documentation https://elevenlabs.io/docs/api-reference/voices/settings/update
[43] API https://help.elevenlabs.io/hc/en-us/sections/14163158308369-API
[44] IMPORTANT: ElevenLabs default voices update on July 11 https://www.reddit.com/r/ElevenLabs/comments/1e00gbo/important_elevenlabs_default_voices_update_on/
[45] Add Full ElevenLabs API Support for Voice Selection via ... https://community.mindstudio.ai/t/add-full-elevenlabs-api-support-for-voice-selection-via-api-key-in-external-integrations/1424
[46] elevenlabs-docs/fern/docs/pages/developer-guides/cookbooks/speech-to-text/quickstart.mdx at main · elevenlabs/elevenlabs-docs https://github.com/elevenlabs/elevenlabs-docs/blob/main/fern/docs/pages/developer-guides/cookbooks/speech-to-text/quickstart.mdx?plain=1
[47] Cannot access elevenlabs voice using the API https://stackoverflow.com/questions/78053136/cannot-access-elevenlabs-voice-using-the-api
[48] Configuration and Authentication | elevenlabs/elevenlabs-js ... https://deepwiki.com/elevenlabs/elevenlabs-js/1.3-configuration-and-authentication
[49] elevenlabs-docs/fern/api-reference/pages/authentication.mdx at main · elevenlabs/elevenlabs-docs https://github.com/elevenlabs/elevenlabs-docs/blob/main/fern/api-reference/pages/authentication.mdx?plain=1
[50] review2 · elevenlabs/elevenlabs-docs@313d9fe https://github.com/elevenlabs/elevenlabs-docs/commit/313d9fe2ca6f3c733dbff97a51263c95573c5b5b
[51] elevenlabs-docs/fern/api-reference/authentication.mdx at main · elevenlabs/elevenlabs-docs https://github.com/elevenlabs/elevenlabs-docs/blob/main/fern/api-reference/authentication.mdx?plain=1
