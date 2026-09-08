import { Plugin } from "@opencode-ai/plugin"
import fs from "fs/promises"
import path from "path"

const MODEL = "gemini-3.7-flash"
const FALLBACK_MODEL = "gemini-3.5-flash"
const INLINE_LIMIT = 15 * 1024 * 1024 // 15MB

const MIME_TYPES: Record<string, string> = {
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".png": "image/png",
  ".webp": "image/webp",
  ".mp4": "video/mp4",
  ".mov": "video/quicktime",
  ".webm": "video/webm",
  ".mpeg": "video/mpeg",
}

function guessMimeType(filePath: string): string {
  const ext = path.extname(filePath).toLowerCase()
  const mime = MIME_TYPES[ext]
  if (!mime) throw new Error(`Extension non supportée: ${ext}`)
  return mime
}

async function uploadFile(filePath: string, mimeType: string, apiKey: string): Promise<string> {
  const data = await fs.readFile(filePath)
  const stats = await fs.stat(filePath)

  const startRes = await fetch(
    `https://generativelanguage.googleapis.com/upload/v1beta/files?key=${apiKey}`,
    {
      method: "POST",
      headers: {
        "X-Goog-Upload-Protocol": "resumable",
        "X-Goog-Upload-Command": "start",
        "X-Goog-Upload-Header-Content-Length": String(stats.size),
        "X-Goog-Upload-Header-Content-Type": mimeType,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ file: { display_name: path.basename(filePath) } }),
    }
  )
  const uploadUrl = startRes.headers.get("x-goog-upload-url")
  if (!uploadUrl) throw new Error("Échec de l'initialisation de l'upload Gemini")

  const uploadRes = await fetch(uploadUrl, {
    method: "POST",
    headers: {
      "Content-Length": String(stats.size),
      "X-Goog-Upload-Offset": "0",
      "X-Goog-Upload-Command": "upload, finalize",
    },
    body: data,
  })
  const fileInfo = await uploadRes.json()
  let state = fileInfo.file.state
  let fileUri = fileInfo.file.uri
  const fileName = fileInfo.file.name as string

  while (state === "PROCESSING") {
    await new Promise((r) => setTimeout(r, 2000))
    const checkRes = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/${fileName}?key=${apiKey}`
    )
    const checkInfo = await checkRes.json()
    state = checkInfo.state
    fileUri = checkInfo.uri
  }
  if (state !== "ACTIVE") throw new Error(`Fichier Gemini en état inattendu: ${state}`)

  return fileUri
}

async function callGemini(
  model: string,
  prompt: string,
  contentPart: any,
  apiKey: string
): Promise<Response> {
  return fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }, contentPart] }],
      }),
    }
  )
}

export default Plugin.define({
  id: "millian.gemini-vision",
  setup: async (ctx) => {
    await ctx.tool.transform((tools) => {
      tools.add(
        {
          name: "gemini_vision",
          description:
            "Analyse une image ou une vidéo locale avec Gemini 3.7 Flash (vision multimodale, tier gratuit AI Studio)",
          input: {
            type: "object",
            properties: {
              filePath: {
                type: "string",
                description: "Chemin absolu du fichier image ou vidéo à analyser",
              },
              prompt: {
                type: "string",
                description: "Question ou instruction à propos du contenu visuel",
                default: "Décris précisément ce que tu vois dans ce fichier.",
              },
            },
            required: ["filePath"],
            additionalProperties: false,
          },
          output: {
            type: "object",
            properties: {
              text: { type: "string" },
              modelUsed: { type: "string" },
            },
            required: ["text", "modelUsed"],
            additionalProperties: false,
          },
          execute: async ({ filePath, prompt }) => {
            const apiKey = process.env.GEMINI_API_KEY
            if (!apiKey) throw new Error("Variable d'environnement GEMINI_API_KEY manquante")

            const finalPrompt = prompt ?? "Décris précisément ce que tu vois dans ce fichier."
            const mimeType = guessMimeType(filePath)
            const stats = await fs.stat(filePath)

            let contentPart: any
            if (stats.size <= INLINE_LIMIT) {
              const data = await fs.readFile(filePath)
              contentPart = {
                inline_data: { mime_type: mimeType, data: data.toString("base64") },
              }
            } else {
              const fileUri = await uploadFile(filePath, mimeType, apiKey)
              contentPart = { file_data: { mime_type: mimeType, file_uri: fileUri } }
            }

            let modelUsed = MODEL
            let res = await callGemini(MODEL, finalPrompt, contentPart, apiKey)

            // Fallback si rate limit (429) sur le tier gratuit
            if (res.status === 429) {
              await new Promise((r) => setTimeout(r, 1500))
              modelUsed = FALLBACK_MODEL
              res = await callGemini(FALLBACK_MODEL, finalPrompt, contentPart, apiKey)
            }

            if (!res.ok) {
              const errText = await res.text()
              throw new Error(`Erreur API Gemini (${res.status}): ${errText}`)
            }

            const json = await res.json()
            const text =
              json.candidates?.[0]?.content?.parts?.map((p: any) => p.text).join("\n") ??
              "Aucune réponse textuelle retournée par Gemini."

            return {
              output: { text, modelUsed },
              content: text,
            }
          },
        }
      )
    })
  },
})
