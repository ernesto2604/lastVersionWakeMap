import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/mock_plan_model.dart';

class GeminiGuideService {
  static const String _tag = '[GeminiGuide]';
  static const Duration _timeout = Duration(seconds: 15);

  final http.Client _httpClient;

  GeminiGuideService({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  /// Guide backend availability.
  ///
  /// This is intentionally based on a non-secret backend URL only.
  bool get isConfigured => AppConfig.apiBaseUrl.isNotEmpty;

  Future<MockPlanModel> generateInitialPlan({
    required Map<String, dynamic> requestContext,
  }) async {
    debugPrint('$_tag Requesting initial guide plan via backend');
    final payload = await _postJson('/api/guide/initial-plan', {
      'requestContext': requestContext,
    });
    return _parsePlan(payload);
  }

  Future<MockPlanModel> refinePlan({
    required Map<String, dynamic> requestContext,
  }) async {
    debugPrint('$_tag Requesting guide plan refinement via backend');
    final payload = await _postJson('/api/guide/refine-plan', {
      'requestContext': requestContext,
    });
    return _parsePlan(payload);
  }

  Future<String> chatOnlyResponse({
    required Map<String, dynamic> requestContext,
    required String userMessage,
  }) async {
    debugPrint('$_tag Requesting chat-only response via backend');
    final payload = await _postJson('/api/guide/chat-only', {
      'requestContext': requestContext,
      'userMessage': userMessage,
    });

    final responseText = payload['response'];
    if (responseText is! String || responseText.trim().isEmpty) {
      throw const GeminiGuideException(
        'Guide backend returned an invalid chat response.',
      );
    }
    return responseText.trim();
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = _buildBackendUri(path);

    http.Response response;
    try {
      response = await _httpClient
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } catch (e) {
      throw GeminiGuideException('Guide backend unavailable: $e');
    }

    final decoded = _decodeResponseJson(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorMessage =
          _extractBackendError(decoded) ??
          'Guide backend request failed (${response.statusCode}).';
      throw GeminiGuideException(errorMessage);
    }

    if (decoded == null) {
      throw const GeminiGuideException(
        'Guide backend returned malformed JSON.',
      );
    }

    return decoded;
  }

  Uri _buildBackendUri(String path) {
    final baseUrl = AppConfig.apiBaseUrl;
    if (baseUrl.isEmpty) {
      throw const GeminiGuideException(
        'API_BASE_URL is not configured for guide backend access.',
      );
    }

    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;

    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath');
  }

  Map<String, dynamic>? _decodeResponseJson(String rawBody) {
    if (rawBody.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  String? _extractBackendError(Map<String, dynamic>? payload) {
    if (payload == null) return null;
    final error = payload['error'];
    if (error is String && error.trim().isNotEmpty) {
      return error.trim();
    }
    return null;
  }

  MockPlanModel _parsePlan(Map<String, dynamic> payload) {
    final plan = payload['plan'];
    if (plan is! Map<String, dynamic>) {
      throw const GeminiGuideException(
        'Guide backend returned an invalid plan payload.',
      );
    }

    try {
      return MockPlanModel.fromJson(plan);
    } catch (e) {
      throw GeminiGuideException('Guide plan schema validation failed: $e');
    }
  }
}

class GeminiGuideException implements Exception {
  final String message;

  const GeminiGuideException(this.message);

  @override
  String toString() => 'GeminiGuideException: $message';
}
