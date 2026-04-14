import dotenv from 'dotenv';
import cors from 'cors';
import express from 'express';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const backendRoot = path.resolve(__dirname, '..');
const envPath = path.join(backendRoot, '.env');
const dotenvResult = dotenv.config({ path: envPath });

const app = express();

const DEFAULT_MODEL = 'gemini-2.5-flash';
const REQUEST_TIMEOUT_MS = 15000;
const MAX_JSON_BODY = '100kb';

class RequestValidationError extends Error {
  constructor(message) {
    super(message);
    this.name = 'RequestValidationError';
  }
}

class GuideProxyError extends Error {
  constructor(message, statusCode = 500) {
    super(message);
    this.name = 'GuideProxyError';
    this.statusCode = statusCode;
  }
}

app.use(
  cors({
    origin: resolveCorsOrigin(),
  }),
);
app.use(express.json({ limit: MAX_JSON_BODY }));

app.get('/health', (_req, res) => {
  res.json({
    status: 'ok',
    geminiConfigured: hasGeminiApiKey(),
    model: resolveGeminiModel(),
    envFileLoaded: !dotenvResult.error,
  });
});

app.post('/api/guide/chat-only', async (req, res, next) => {
  try {
    const requestContext = requireObject(req.body?.requestContext, 'requestContext');
    const userMessage = requireString(req.body?.userMessage, 'userMessage');

    const prompt = buildChatOnlyPrompt({
      requestContext,
      userMessage,
    });

    const text = await requestGeminiText({
      prompt,
      responseMimeType: null,
      temperature: 0.6,
    });

    const responseText = text.trim();
    if (!responseText) {
      throw new GuideProxyError('Guide service returned an empty response.', 502);
    }

    res.json({ response: responseText });
  } catch (error) {
    next(error);
  }
});

app.post('/api/guide/initial-plan', async (req, res, next) => {
  try {
    const requestContext = requireObject(req.body?.requestContext, 'requestContext');
    const prompt = buildPlanGenerationPrompt(requestContext);
    const plan = await requestAndValidatePlan(prompt);
    res.json({ plan });
  } catch (error) {
    next(error);
  }
});

app.post('/api/guide/refine-plan', async (req, res, next) => {
  try {
    const requestContext = requireObject(req.body?.requestContext, 'requestContext');
    const prompt = buildPlanRefinementPrompt(requestContext);
    const plan = await requestAndValidatePlan(prompt);
    res.json({ plan });
  } catch (error) {
    next(error);
  }
});

app.use((error, _req, res, _next) => {
  if (error instanceof RequestValidationError) {
    return res.status(400).json({ error: error.message });
  }

  if (error instanceof GuideProxyError) {
    if (error.statusCode >= 500) {
      console.error('[GuideProxy] request failed:', error.message);
    }
    return res.status(error.statusCode).json({ error: error.message });
  }

  console.error('[GuideProxy] unexpected failure:', error);
  return res.status(500).json({ error: 'Guide service request failed.' });
});

const startupConfig = getStartupConfig();
if (dotenvResult.error) {
  console.warn(
    `[GuideProxy] .env not loaded from ${envPath}. Falling back to process env only.`,
  );
}
if (!startupConfig.geminiConfigured) {
  console.warn(
    '[GuideProxy] GEMINI_API_KEY missing. Guide endpoints will return 503 until configured.',
  );
}

app.listen(startupConfig.port, () => {
  console.log(
    `[GuideProxy] listening on :${startupConfig.port} (geminiConfigured=${startupConfig.geminiConfigured}, model=${startupConfig.model})`,
  );
});

function resolveCorsOrigin() {
  const raw = (process.env.CORS_ORIGIN ?? '*').trim();
  if (!raw || raw === '*') return true;

  const allowed = raw
    .split(',')
    .map((entry) => entry.trim())
    .filter(Boolean);

  if (allowed.length === 0) return true;

  return (origin, callback) => {
    if (!origin || allowed.includes(origin)) {
      callback(null, true);
      return;
    }
    callback(new Error('CORS origin not allowed'));
  };
}

function parsePort(raw) {
  const value = Number.parseInt(raw ?? '8080', 10);
  if (Number.isInteger(value) && value > 0) return value;
  return 8080;
}

function getStartupConfig() {
  return {
    port: parsePort(process.env.PORT),
    geminiConfigured: hasGeminiApiKey(),
    model: resolveGeminiModel(),
  };
}

function hasGeminiApiKey() {
  return (process.env.GEMINI_API_KEY ?? '').trim().length > 0;
}

function resolveGeminiApiKey() {
  const apiKey = (process.env.GEMINI_API_KEY ?? '').trim();
  if (!apiKey) {
    throw new GuideProxyError(
      'Guide service is not configured on the server.',
      503,
    );
  }
  return apiKey;
}

function resolveGeminiModel() {
  const model = (process.env.GEMINI_MODEL ?? '').trim();
  return model || DEFAULT_MODEL;
}

function requireObject(value, fieldName) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new RequestValidationError(`${fieldName} must be an object.`);
  }
  return value;
}

function requireString(value, fieldName) {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new RequestValidationError(`${fieldName} must be a non-empty string.`);
  }

  const trimmed = value.trim();
  if (trimmed.length > 4000) {
    throw new RequestValidationError(`${fieldName} is too long.`);
  }
  return trimmed;
}

async function requestAndValidatePlan(prompt) {
  const text = await requestGeminiText({
    prompt,
    responseMimeType: 'application/json',
    temperature: 0.35,
  });

  const rawPlanJson = extractFirstJsonObject(text);
  let decoded;
  try {
    decoded = JSON.parse(rawPlanJson);
  } catch (_error) {
    throw new GuideProxyError('Guide service returned invalid plan JSON.', 502);
  }

  return validatePlanPayload(decoded);
}

async function requestGeminiText({ prompt, responseMimeType, temperature }) {
  const apiKey = resolveGeminiApiKey();
  const model = resolveGeminiModel();

  const endpoint = new URL(
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
  );
  endpoint.searchParams.set('key', apiKey);

  const body = {
    contents: [
      {
        role: 'user',
        parts: [{ text: prompt }],
      },
    ],
    generationConfig: {
      temperature,
      ...(responseMimeType ? { responseMimeType } : {}),
    },
  };

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);

  let response;
  try {
    response = await fetch(endpoint, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
  } catch (_error) {
    throw new GuideProxyError('Guide service is temporarily unavailable.', 503);
  } finally {
    clearTimeout(timeout);
  }

  const rawBody = await response.text();
  let decoded = null;
  try {
    decoded = JSON.parse(rawBody);
  } catch (_error) {
    decoded = null;
  }

  if (!response.ok) {
    const status = response.status;
    const safeError = mapGeminiStatusToClientMessage(status);
    console.error(`[GuideProxy] Gemini HTTP ${status}.`);
    throw new GuideProxyError(safeError, mapGeminiStatusToHttpStatus(status));
  }

  return extractModelText(decoded);
}

function mapGeminiStatusToHttpStatus(status) {
  if (status === 401 || status === 403) return 503;
  if (status === 429) return 429;
  if (status >= 500) return 503;
  return 502;
}

function mapGeminiStatusToClientMessage(status) {
  if (status === 401 || status === 403) {
    return 'Guide service is not configured on the server.';
  }
  if (status === 429) {
    return 'Guide service is busy. Please try again in a moment.';
  }
  if (status >= 500) {
    return 'Guide service is temporarily unavailable.';
  }
  return 'Guide service request failed.';
}

function extractModelText(decoded) {
  if (!decoded || typeof decoded !== 'object') {
    throw new GuideProxyError('Guide service returned an invalid response shape.', 502);
  }

  const candidates = decoded.candidates;
  if (!Array.isArray(candidates) || candidates.length === 0) {
    throw new GuideProxyError('Guide service returned no candidates.', 502);
  }

  const firstCandidate = candidates[0];
  const parts = firstCandidate?.content?.parts;
  if (!Array.isArray(parts) || parts.length === 0) {
    throw new GuideProxyError('Guide service returned empty content.', 502);
  }

  const firstPart = parts[0];
  const text = typeof firstPart?.text === 'string' ? firstPart.text : '';
  if (!text.trim()) {
    throw new GuideProxyError('Guide service returned empty text.', 502);
  }

  return text;
}

function extractFirstJsonObject(text) {
  const trimmed = text.trim();
  if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
    return trimmed;
  }

  const start = trimmed.indexOf('{');
  const end = trimmed.lastIndexOf('}');
  if (start < 0 || end <= start) {
    throw new GuideProxyError('Guide service returned no JSON object.', 502);
  }
  return trimmed.slice(start, end + 1);
}

function validatePlanPayload(payload) {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
    throw new GuideProxyError('Guide plan payload is invalid.', 502);
  }

  const title = requireNonEmptyString(payload.title, 'title');
  const summary = requireNonEmptyString(payload.summary, 'summary');
  const estimatedDuration = optionalString(payload.estimated_duration);
  const estimatedBudget = optionalString(payload.estimated_budget);

  if (!Array.isArray(payload.stops)) {
    throw new GuideProxyError('Guide plan stops are invalid.', 502);
  }

  if (payload.stops.length < 2 || payload.stops.length > 4) {
    throw new GuideProxyError('Guide plan must include between 2 and 4 stops.', 502);
  }

  const stops = payload.stops.map((stop, index) => {
    if (!stop || typeof stop !== 'object' || Array.isArray(stop)) {
      throw new GuideProxyError(`Guide plan stop ${index + 1} is invalid.`, 502);
    }

    return {
      name: requireNonEmptyString(stop.name, `stops[${index}].name`),
      description: requireNonEmptyString(
        stop.description,
        `stops[${index}].description`,
      ),
      latitude: requireFiniteNumber(stop.latitude, `stops[${index}].latitude`),
      longitude: requireFiniteNumber(stop.longitude, `stops[${index}].longitude`),
    };
  });

  return {
    title,
    summary,
    estimated_duration: estimatedDuration,
    estimated_budget: estimatedBudget,
    stops,
  };
}

function requireNonEmptyString(value, fieldName) {
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw new GuideProxyError(`Guide payload field "${fieldName}" is invalid.`, 502);
  }
  return value.trim();
}

function optionalString(value) {
  if (value == null) return '';
  if (typeof value !== 'string') return String(value);
  return value.trim();
}

function requireFiniteNumber(value, fieldName) {
  const number = typeof value === 'number' ? value : Number(value);
  if (!Number.isFinite(number)) {
    throw new GuideProxyError(`Guide payload field "${fieldName}" is invalid.`, 502);
  }
  return number;
}

function buildChatOnlyPrompt({ requestContext, userMessage }) {
  const contextJson = JSON.stringify(requestContext);
  return `You are WakeMap's human-like travel guide assistant.
Respond with natural, conversational text only.
Do NOT return JSON.
Do NOT use markdown code fences.

Your goals:
- Give practical and friendly suggestions.
- Ask clarifying questions when useful.
- Help the user shape a plan without creating one yet.
- Invite the user to confirm when they want a full plan generated.

User message:
${userMessage}

Context JSON:
${contextJson}`;
}

function buildPlanGenerationPrompt(requestContext) {
  const requestJson = JSON.stringify(requestContext);
  return `You are a travel guide planner for WakeMap.
Return ONLY valid JSON.
No markdown.
No backticks.
No explanation.

Use this exact schema:
{
  "title": "string",
  "summary": "string",
  "estimated_duration": "string",
  "estimated_budget": "string",
  "stops": [
    {
      "name": "string",
      "description": "string",
      "latitude": number,
      "longitude": number
    }
  ]
}

Rules:
- 2 to 4 stops
- concise UI-friendly descriptions
- plausible coordinates near the provided context

Request type: initial_plan
Request context JSON:
${requestJson}`;
}

function buildPlanRefinementPrompt(requestContext) {
  const requestJson = JSON.stringify(requestContext);
  return `You are a travel guide planner for WakeMap.
You are refining an existing plan.
Return ONLY valid JSON.
No markdown.
No backticks.
No explanation.

Use this exact schema:
{
  "title": "string",
  "summary": "string",
  "estimated_duration": "string",
  "estimated_budget": "string",
  "stops": [
    {
      "name": "string",
      "description": "string",
      "latitude": number,
      "longitude": number
    }
  ]
}

Rules:
- 2 to 4 stops
- concise UI-friendly descriptions
- ensure the revised plan remains coherent as one consistent plan

Request type: refine_plan
Request context JSON:
${requestJson}`;
}
