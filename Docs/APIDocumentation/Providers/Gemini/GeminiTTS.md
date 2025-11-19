Gemini API Speech & Audio CURL Documentation

Authentication

All Gemini API requests require authentication using an API key, typically passed as a query parameter or header.

# Get your API key from: [https://aistudio.google.com/app/apikey](https://aistudio.google.com/app/apikey)
GEMINI_API_KEY="your_api_key_here"


Text-to-Speech (TTS)

Gemini's TTS capabilities allow you to generate high-quality, controllable speech using specific models like gemini-2.5-flash-preview-tts.

Basic TTS Request

Convert text to speech using a specific prebuilt voice.

curl "[https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent?key=$](https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent?key=$){GEMINI_API_KEY}" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{
    "contents": [{
      "parts": [{
        "text": "Hello! This is a test of the Gemini text to speech API."
      }]
    }],
    "generationConfig": {
      "response_modalities": ["AUDIO"],
      "speech_config": {
        "voice_config": {
          "prebuilt_voice_config": {
            "voice_name": "Puck"
          }
        }
      }
    }
  }' \
  --output output.wav


Voice Options

Gemini offers a variety of voices tailored for different tones.

Available Voices:
| Voice Name | Tone Description |
|:-----------|:-----------------|
| Puck | Upbeat, energetic |
| Charon | Deep, informative |
| Kore | Firm, authoritative |
| Fenrir | Excitable, fast-paced |
| Aoede | Breezy, light |
| Zephyr | Bright, clear |
| Orus | Firm, direct |
| Leda | Youthful |

(Full list includes over 20 voices like Erinome, Algenib, etc.)

Multi-Speaker Conversations

You can generate a conversation between multiple speakers in a single request.

curl "[https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent?key=$](https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent?key=$){GEMINI_API_KEY}" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{
    "contents": [{
      "parts": [{
        "text": "Speaker1: Hi there, how are you?\nSpeaker2: I am doing great, thanks for asking!"
      }]
    }],
    "generationConfig": {
      "response_modalities": ["AUDIO"],
      "speech_config": {
        "multi_speaker_voice_config": {
           "speaker_voice_configs": [
             {
               "speaker": "Speaker1",
               "voice_config": { "prebuilt_voice_config": { "voice_name": "Puck" } }
             },
             {
               "speaker": "Speaker2",
               "voice_config": { "prebuilt_voice_config": { "voice_name": "Kore" } }
             }
           ]
        }
      }
    }
  }' \
  --output conversation.wav


Controlling Speech Style

You can direct the emotion and style directly within the text prompt.

curl "[https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent?key=$](https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-tts:generateContent?key=$){GEMINI_API_KEY}" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{
    "contents": [{
      "parts": [{
        "text": "Say in a whispered, mysterious tone: The secret code is hidden under the mat."
      }]
    }],
    "generationConfig": {
      "response_modalities": ["AUDIO"],
      "speech_config": {
        "voice_config": {
          "prebuilt_voice_config": {
            "voice_name": "Charon"
          }
        }
      }
    }
  }' \
  --output whisper.wav


Audio Understanding (Speech-to-Text)

Gemini models are multimodal and can "hear" audio files to transcribe them, answer questions about them, or summarize them.

1. Upload Audio (Files API)

For files larger than 20MB or for reuse, upload the file first.

# Upload the file
curl "[https://generativelanguage.googleapis.com/upload/v1beta/files?key=$](https://generativelanguage.googleapis.com/upload/v1beta/files?key=$){GEMINI_API_KEY}" \
  -H "X-Goog-Upload-Command: start, upload, finalize" \
  -H "X-Goog-Upload-Header-Content-Length: $(wc -c < audio.mp3)" \
  -H "X-Goog-Upload-Header-Content-Type: audio/mpeg" \
  --data-binary @audio.mp3


(The response will contain a uri like https://generativelanguage.googleapis.com/v1beta/files/xxxxx)

2. Generate Transcript

Use the file URI to request a transcript.

curl "[https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$](https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$){GEMINI_API_KEY}" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{
    "contents": [{
      "parts": [
        { "file_data": { "mime_type": "audio/mpeg", "file_uri": "YOUR_FILE_URI" } },
        { "text": "Generate a verbatim transcript of this audio with speaker labels." }
      ]
    }]
  }'


Inline Audio (Small Files)

For small audio clips, you can base64 encode them inline.

curl "[https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$](https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$){GEMINI_API_KEY}" \
  -H "Content-Type: application/json" \
  -X POST \
  -d '{
    "contents": [{
      "parts": [
        {
          "inline_data": {
            "mime_type": "audio/mpeg",
            "data": "'$(base64 -w 0 input.mp3)'"
          }
        },
        { "text": "Summarize what is being said in this clip." }
      ]
    }]
  }'


Real-Time Interaction (Live API)

For low-latency, bidirectional voice conversations (Speech-to-Speech), use the Gemini Live API via WebSockets.

WebSocket Endpoint

wss://[generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent?key=$](https://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent?key=$){GEMINI_API_KEY}


Handshake Setup Message

{
  "setup": {
    "model": "models/gemini-2.0-flash-exp",
    "generation_config": {
      "response_modalities": ["AUDIO"],
      "speech_config": {
        "voice_config": {
          "prebuilt_voice_config": {
            "voice_name": "Puck"
          }
        }
      }
    }
  }
}


Models Reference

Audio Generation (TTS)

Model ID

Description

gemini-2.5-flash-preview-tts

Specialized low-latency model for high-quality speech generation.

Audio Understanding (STT)

Model ID

Description

gemini-1.5-flash

Fast, cost-effective multimodal understanding. Best for high-volume transcription.

gemini-1.5-pro

Higher reasoning capability. Best for complex analysis of audio content.

gemini-2.0-flash-exp

Experimental next-gen model with improved multimodal latency.

Audio Limits

Max Audio Length: ~9.5 hours per prompt (multimodal).

Sample Rate: Output audio is typically 24kHz.

Formats: WAV is the standard output container for the raw PCM data provided.