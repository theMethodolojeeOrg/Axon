Server-side encryption/decryption plan to match the client

Below are concrete, copyable instructions (with TypeScript/Node examples) for your Cloud Function to read, decrypt, and use the ElevenLabs API key that the iOS client now writes. This matches the current client-side scheme in your EncryptionService (CryptoKit + ChaCha20-Poly1305 + SHA256 derivation).

1) Firestore schema the server should expect

• Data key envelope (used to encrypt settings payloads):
   • Path: users/{uid}/encryption/key
   • Fields:
   {
      encryptedKey: {
        ciphertext: "<base64-ciphertext>:<base64-tag>",
        nonce: "<base64-12-bytes>",
        version: 1
      },
      version: 1,
      createdAt: <serverTimestamp>,
      updatedAt: <serverTimestamp>
    }

    • App settings (contains ElevenLabs key payload):
   • Path: users/{uid}/settings/appSettings
   • Fields:

   {
      encrypted: {
        ciphertext: "<base64-ciphertext>:<base64-tag>",
        nonce: "<base64-12-bytes>",
        version: 1
      },
      // optional: app.blob (your manual settings sync JSON), version, updatedAt, etc.
    }

    Notes:
• ciphertext field is a colon-concatenation of two Base64 strings: "<ciphertextB64>:<tagB64>".
• nonce is Base64 of 12 bytes (ChaCha20-Poly1305).
• The client uses CryptoKit ChaCha20-Poly1305 and SHA256 for master key derivation.

2) Master key derivation (must match the client)

• Master key = SHA256 of "\(uid):NeurXAxonChat_Encryption_V1".
• Exactly this salt: "NeurXAxonChat_Encryption_V1".
• This yields a 32-byte key.

TypeScript (Node 20+):

import crypto from "node:crypto";

const APP_SALT = "NeurXAxonChat_Encryption_V1";

function deriveMasterKey(userId: string): Buffer {
  const input = `${userId}:${APP_SALT}`;
  return crypto.createHash("sha256").update(input, "utf8").digest(); // 32 bytes
}

3) Decrypt the data key envelope

• Read users/{uid}/encryption/key.
• Extract:
   • encryptedKey.ciphertext → split on ":" to get ciphertextB64, tagB64
   • encryptedKey.nonce → Base64 decode (12 bytes)
• Decrypt with ChaCha20-Poly1305 using the master key.

TypeScript:

function base64ToBuf(b64: string) { return Buffer.from(b64, "base64"); }

function chacha20poly1305Decrypt(
  key: Buffer, // 32 bytes
  nonce: Buffer, // 12 bytes
  ciphertext: Buffer,
  tag: Buffer,
  aad?: Buffer
): Buffer {
  // Node supports chacha20-poly1305 if OpenSSL is built with it (GCF Node 20 typically supports it)
  const decipher = crypto.createDecipheriv("chacha20-poly1305", key, nonce, { authTagLength: 16 });
  if (aad && aad.length) decipher.setAAD(aad);
  decipher.setAuthTag(tag);
  const dec1 = decipher.update(ciphertext);
  const dec2 = decipher.final();
  return Buffer.concat([dec1, dec2]);
}

async function fetchAndDecryptDataKey(firestore: FirebaseFirestore.Firestore, uid: string): Promise<Buffer> {
  const doc = await firestore.collection("users").doc(uid).collection("encryption").doc("key").get();
  if (!doc.exists) throw new Error("Data key not found");

  const data = doc.data()!;
  const ek = data.encryptedKey;
  if (!ek || typeof ek.ciphertext !== "string" || typeof ek.nonce !== "string") {
    throw new Error("Invalid data key format");
  }

  const parts = ek.ciphertext.split(":");
  if (parts.length !== 2) throw new Error("Invalid ciphertext format for data key");
  const ct = base64ToBuf(parts[0]);
  const tag = base64ToBuf(parts[1]);
  const nonce = base64ToBuf(ek.nonce);

  const masterKey = deriveMasterKey(uid);
  const dataKey = chacha20poly1305Decrypt(masterKey, nonce, ct, tag);
  // Expect 32 bytes
  if (dataKey.length !== 32) throw new Error("Decrypted data key has unexpected length");
  return dataKey;
}

4) Decrypt the ElevenLabs payload

• Read users/{uid}/settings/appSettings.encrypted.
• Extract:
   • encrypted.ciphertext → split on ":" to get ciphertextB64, tagB64
   • encrypted.nonce → Base64 decode (12 bytes)
• Decrypt with ChaCha20-Poly1305 using the data key from step 3.
• The plaintext is JSON. Expected structure:

{ "tts": { "elevenLabsApiKey": "sk_..." } }

async function fetchAndDecryptElevenLabsKey(
  firestore: FirebaseFirestore.Firestore,
  uid: string
): Promise<string> {
  const doc = await firestore.collection("users").doc(uid).collection("settings").doc("appSettings").get();
  if (!doc.exists) throw new Error("appSettings doc not found");

  const data = doc.data()!;
  const enc = data.encrypted;
  if (!enc || typeof enc.ciphertext !== "string" || typeof enc.nonce !== "string") {
    throw new Error("Invalid encrypted settings format");
  }

  const parts = enc.ciphertext.split(":");
  if (parts.length !== 2) throw new Error("Invalid ciphertext format for settings");
  const ct = base64ToBuf(parts[0]);
  const tag = base64ToBuf(parts[1]);
  const nonce = base64ToBuf(enc.nonce);

  const dataKey = await fetchAndDecryptDataKey(firestore, uid);
  const plaintext = chacha20poly1305Decrypt(dataKey, nonce, ct, tag);
  const json = JSON.parse(plaintext.toString("utf8"));

  const apiKey = json?.tts?.elevenLabsApiKey;
  if (!apiKey || typeof apiKey !== "string" || apiKey.trim() === "") {
    throw new Error("ElevenLabs API key not configured");
  }
  return apiKey;
}

5) Use the ElevenLabs key in your function

In your apiElevenLabs Cloud Function:
• Authenticate the caller (you already do with Bearer Firebase ID token).
• Resolve uid from the token.
• Call fetchAndDecryptElevenLabsKey(firestore, uid).
• Use the returned key to call ElevenLabs.

Example handler skeleton:
import { onRequest } from "firebase-functions/v2/https";
import { getApp, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import crypto from "node:crypto";

initializeApp();
const firestore = getFirestore(getApp());

export const apiElevenLabs = onRequest(async (req, res) => {
  try {
    const authHeader = req.get("Authorization") || "";
    const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : null;
    if (!token) return res.status(401).json({ error: "Missing auth token" });

    // Verify token (left as an exercise; you likely already have this)
    const uid = await verifyAndExtractUid(token); // implement using admin.auth()

    const elevenKey = await fetchAndDecryptElevenLabsKey(firestore, uid);

    const action = req.body?.action;
    if (action === "voices_list") {
      // Call ElevenLabs voices endpoint with elevenKey...
      // return res.json({ voices: [...] });
    } else if (action === "models_list") {
      // Call models endpoint...
    } else if (action === "tts_generate_base64") {
      // Generate TTS...
    } else {
      return res.status(400).json({ error: "Unknown action" });
    }
  } catch (err: any) {
    const msg = typeof err?.message === "string" ? err.message : String(err);
    return res.status(400).json({ error: msg });
  }
});

6) Validation and error handling

• If any of the following are missing/invalid, return a 400 with a descriptive message:
   • encryption/key doc missing or malformed
   • settings/appSettings.encrypted missing or malformed
   • Wrong nonce length (should be 12 bytes)
   • Decryption failure (bad tag) → “Decryption failed (invalid key or corrupted data)”
   • Missing tts.elevenLabsApiKey in decrypted JSON

• Log failures to help diagnose configuration issues.

7) Optional: Versioning and future-proofing

Right now both envelopes use version: 1. If you plan a migration:
• Bump to version: 2 and store separate fields:
   • ciphertext, tag, nonce, algo: "ChaCha20-Poly1305".
• On server, branch on version to support legacy reads while migrating.

8) Migration note (if you ever had libsodium format before)

If older users have a Sodium XSalsa20-Poly1305 format in Firestore:
• Detect nonce length (24 bytes) and/or algo/version.
• Decrypt with libsodium (server-side) or reject with a clear error and prompt the client to re-save the key (which will write the new format).
• For now, since you said you “just added sodium” and then removed it, you may not have legacy data — keep this in mind if logs show 24-byte nonces.

9) Quick checklist

• Ensure your Cloud Function environment supports chacha20-poly1305 in Node crypto (Node 20 on GCF typically does).
• Confirm that nonce Base64 decodes to 12 bytes.
• Confirm master key derivation: SHA256 of "${uid}:NeurXAxonChat_Encryption_V1".
• Confirm Firestore paths and field names match exactly.
