import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_secrets.dart';
import '../models/mock_plan_model.dart';

class GeminiGuideService {
  static const String _tag = '[GeminiGuide]';
  static const String _definedApiKey = String.fromEnvironment('GEMINI_API_KEY');
  static const String _definedModel = String.fromEnvironment('GEMINI_MODEL');

  bool get isConfigured => _resolveApiKey().value.isNotEmpty;

  Future<MockPlanModel> generateInitialPlan({
    required Map<String, dynamic> requestContext,
  }) async {
    debugPrint('$_tag Requesting initial guide plan');
    return _requestPlan(
      prompt: _buildPlanGenerationPrompt(requestContext),
    );
  }

  Future<MockPlanModel> refinePlan({
    required Map<String, dynamic> requestContext,
  }) async {
    debugPrint('$_tag Requesting plan refinement');
    return _requestPlan(
      prompt: _buildPlanRefinementPrompt(requestContext),
    );
  }

  Future<String> chatOnlyResponse({
    required Map<String, dynamic> requestContext,
    required String userMessage,
  }) async {
    debugPrint('$_tag Requesting chat-only guide response');

    final apiKeyResolution = _resolveApiKey();
    final modelResolution = _resolveModel();

    _logRuntimeConfig(
      apiKeyResolution: apiKeyResolution,
      modelResolution: modelResolution,
    );

    if (apiKeyResolution.value.isEmpty) {
      throw const GeminiGuideException('Missing API key');
    }

    final endpoint = Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/models/${modelResolution.value}:generateContent',
      {'key': apiKeyResolution.value},
    );
    debugPrint('$_tag Endpoint: ${_redactEndpoint(endpoint)}');

    final prompt = _buildChatOnlyPrompt(
      requestContext: requestContext,
      userMessage: userMessage,
    );

    final body = {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt}
          ],
        }
      ],
      'generationConfig': {
        'temperature': 0.6,
      },
    };

    http.Response response;
    try {
      response = await http
          .post(
            endpoint,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw GeminiGuideException('Network or timeout failure: $e');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final excerpt = response.body.length > 240
          ? response.body.substring(0, 240)
          : response.body;
      debugPrint('$_tag HTTP ${response.statusCode} failure excerpt: $excerpt');
      throw GeminiGuideException('HTTP ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    final text = _extractModelText(decoded).trim();
    if (text.isEmpty) {
      throw const GeminiGuideException('Gemini returned empty chat response');
    }

    debugPrint('$_tag Gemini chat response received');
    return text;
  }

  Future<MockPlanModel> _requestPlan({
    required String prompt,
  }) async {
    final apiKeyResolution = _resolveApiKey();
    final modelResolution = _resolveModel();

    _logRuntimeConfig(
      apiKeyResolution: apiKeyResolution,
      modelResolution: modelResolution,
    );

    if (!isConfigured) {
      throw const GeminiGuideException('Missing API key');
    }

    final endpoint = Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/models/${modelResolution.value}:generateContent',
      {'key': apiKeyResolution.value},
    );
    debugPrint('$_tag Endpoint: ${_redactEndpoint(endpoint)}');

    final body = {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt}
          ],
        }
      ],
      'generationConfig': {
        'temperature': 0.35,
        'responseMimeType': 'application/json',
      },
    };

    http.Response response;
    try {
      response = await http
          .post(
            endpoint,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      throw GeminiGuideException('Network or timeout failure: $e');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final excerpt = response.body.length > 240
          ? response.body.substring(0, 240)
          : response.body;
      debugPrint('$_tag HTTP ${response.statusCode} failure excerpt: $excerpt');
      throw GeminiGuideException(
        'HTTP ${response.statusCode}: ${response.body}',
      );
    }

    debugPrint('$_tag Response received');

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (e) {
      throw GeminiGuideException('Invalid Gemini response JSON envelope: $e');
    }

    final text = _extractModelText(decoded);
    final rawPlanJson = _extractFirstJsonObject(text);

    dynamic planDecoded;
    try {
      planDecoded = jsonDecode(rawPlanJson);
    } catch (e) {
      throw GeminiGuideException('Invalid plan JSON body: $e');
    }

    if (planDecoded is! Map<String, dynamic>) {
      throw const GeminiGuideException('Plan payload is not a JSON object');
    }

    try {
      final parsed = MockPlanModel.fromJson(planDecoded);
      debugPrint('$_tag JSON parse succeeded');
      return parsed;
    } catch (e) {
      throw GeminiGuideException('Schema validation failed: $e');
    }
  }

  String _buildChatOnlyPrompt({
    required Map<String, dynamic> requestContext,
    required String userMessage,
  }) {
    final contextJson = jsonEncode(requestContext);
    return '''
You are WakeMap's human-like travel guide assistant.
Respond with natural, conversational text only.
Do NOT return JSON.
Do NOT use markdown code fences.

Your goals:
- Give practical and friendly suggestions.
- Ask clarifying questions when useful.
- Help the user shape a plan without creating one yet.
- Invite the user to confirm when they want a full plan generated.

User message:
$userMessage

Context JSON:
$contextJson
''';
  }

  String _buildPlanGenerationPrompt(Map<String, dynamic> requestContext) {
    final requestJson = jsonEncode(requestContext);
    return '''
You are a travel guide planner for WakeMap.
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
$requestJson
''';
  }

  String _buildPlanRefinementPrompt(Map<String, dynamic> requestContext) {
    final requestJson = jsonEncode(requestContext);
    return '''
You are a travel guide planner for WakeMap.
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
$requestJson
''';
  }

  String _extractModelText(dynamic decoded) {
    if (decoded is! Map<String, dynamic>) {
      throw const GeminiGuideException('Unexpected response shape');
    }

    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw const GeminiGuideException('No Gemini candidates returned');
    }

    final first = candidates.first;
    if (first is! Map<String, dynamic>) {
      throw const GeminiGuideException('Invalid candidate shape');
    }

    final content = first['content'];
    if (content is! Map<String, dynamic>) {
      throw const GeminiGuideException('Missing content in candidate');
    }

    final parts = content['parts'];
    if (parts is! List || parts.isEmpty) {
      throw const GeminiGuideException('Missing content parts in candidate');
    }

    final text = (parts.first as Map<String, dynamic>)['text'];
    if (text is! String || text.trim().isEmpty) {
      throw const GeminiGuideException('Missing text output from candidate');
    }

    return text;
  }

  String _extractFirstJsonObject(String text) {
    final trimmed = text.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      return trimmed;
    }

    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const GeminiGuideException('No JSON object found in model output');
    }
    return trimmed.substring(start, end + 1);
  }

  ({String value, String source, bool trimmedChanged}) _resolveApiKey() {
    final defineRaw = _definedApiKey;
    final defineTrimmed = defineRaw.trim();
    final defineChanged = defineRaw != defineTrimmed;

    if (defineTrimmed.isNotEmpty && !_looksLikePlaceholder(defineTrimmed)) {
      return (
        value: defineTrimmed,
        source: 'dart_define',
        trimmedChanged: defineChanged,
      );
    }

    final secretRaw = AppSecrets.geminiApiKey;
    final secretTrimmed = secretRaw.trim();
    final secretChanged = secretRaw != secretTrimmed;

    if (secretTrimmed.isNotEmpty && !_looksLikePlaceholder(secretTrimmed)) {
      return (
        value: secretTrimmed,
        source: 'app_secrets',
        trimmedChanged: secretChanged,
      );
    }

    if (defineTrimmed.isNotEmpty || secretTrimmed.isNotEmpty) {
      return (
        value: '',
        source: 'placeholder_or_invalid',
        trimmedChanged: defineChanged || secretChanged,
      );
    }

    return (value: '', source: 'empty', trimmedChanged: defineChanged || secretChanged);
  }

  ({String value, String source, bool trimmedChanged}) _resolveModel() {
    final defineRaw = _definedModel;
    final defineTrimmed = defineRaw.trim();
    final defineChanged = defineRaw != defineTrimmed;

    if (defineTrimmed.isNotEmpty) {
      return (
        value: defineTrimmed,
        source: 'dart_define',
        trimmedChanged: defineChanged,
      );
    }

    final secretRaw = AppSecrets.geminiModel;
    final secretTrimmed = secretRaw.trim();
    final secretChanged = secretRaw != secretTrimmed;
    final model = secretTrimmed.isEmpty ? 'gemini-2.0-flash' : secretTrimmed;

    return (
      value: model,
      source: 'app_secrets',
      trimmedChanged: defineChanged || secretChanged,
    );
  }

  bool _looksLikePlaceholder(String value) {
    final v = value.toUpperCase();
    return v.contains('PUT_YOUR') || v.contains('YOUR_GEMINI_API_KEY') || v == 'REPLACE_ME';
  }

  void _logRuntimeConfig({
    required ({String value, String source, bool trimmedChanged}) apiKeyResolution,
    required ({String value, String source, bool trimmedChanged}) modelResolution,
  }) {
    final key = apiKeyResolution.value;
    final prefix = key.isEmpty
        ? '(empty)'
        : key.substring(0, key.length >= 6 ? 6 : key.length);

    debugPrint('$_tag API key source: ${apiKeyResolution.source}');
    debugPrint('$_tag API key length: ${key.length}');
    debugPrint('$_tag API key prefix: $prefix');
    debugPrint('$_tag API key trimmed: ${apiKeyResolution.trimmedChanged ? 'yes' : 'no'}');
    debugPrint('$_tag Model: ${modelResolution.value} (source=${modelResolution.source})');
  }

  String _redactEndpoint(Uri endpoint) {
    return endpoint.replace(queryParameters: {
      ...endpoint.queryParameters,
      if (endpoint.queryParameters.containsKey('key')) 'key': 'REDACTED',
    }).toString();
  }
}

class GeminiGuideException implements Exception {
  final String message;

  const GeminiGuideException(this.message);

  @override
  String toString() => 'GeminiGuideException: $message';
}
