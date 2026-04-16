import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../models/alarm_model.dart';
import '../models/app_mode.dart';
import '../models/chat_message_model.dart';
import '../models/guide_session_state.dart';
import '../models/mock_plan_model.dart';
import '../services/alarm_service.dart';
import '../services/gemini_guide_service.dart';
import '../services/local_notification_service.dart';
import '../services/location_service.dart';
import '../services/mock_guide_service.dart';
import '../services/storage_service.dart';

class AppStateProvider extends ChangeNotifier {
  static const String _tag = '[AppState]';
  static const String _geminiTag = '[GeminiGuide]';
  static const String _guideTag = '[Guide]';

  final StorageService _storage;
  final LocationService _location;
  late final AlarmService _alarmService;
  final MockGuideService _guideService = MockGuideService();
  final GeminiGuideService _geminiGuideService = GeminiGuideService();

  // ── Mode ──
  AppMode? _mode;
  AppMode? get mode => _mode;

  // ── Alarms ──
  List<AlarmModel> _alarms = [];
  List<AlarmModel> get alarms => List.unmodifiable(_alarms);

  // ── Triggered alarm (for navigation) ──
  AlarmModel? _triggeredAlarm;
  AlarmModel? get triggeredAlarm => _triggeredAlarm;

  // ── Guide state (traveller only) ──
  List<ChatMessageModel> _chatMessages = [];
  List<ChatMessageModel> get chatMessages => List.unmodifiable(_chatMessages);

  MockPlanModel? _currentPlan;
  MockPlanModel? get currentPlan => _currentPlan;

  GuideSessionState _guideSession = const GuideSessionState();
  GuideSessionState get guideSession => _guideSession;

  // ── Arrival coordinates for guide plan generation ──
  double? _arrivalLat;
  double? _arrivalLng;

  // ── Navigation tab indices ──
  int _commuterTabIndex = 0;
  int get commuterTabIndex => _commuterTabIndex;

  int _travellerTabIndex = 0;
  int get travellerTabIndex => _travellerTabIndex;

  // ── Location tracking ──
  StreamSubscription<Position>? _positionSub;
  Position? _currentPosition;
  Position? get currentPosition => _currentPosition;

  /// True once the stream subscription is live.
  bool _isTrackingActive = false;

  /// True while startLocationTracking() is executing (async guard).
  /// Prevents a second concurrent call from doing duplicate work.
  bool _isStartingTracking = false;

  /// Cached so we don't re-request after first grant.
  bool _permissionGranted = false;

  /// True once we've fetched an initial position.
  bool _hasFetchedInitialPosition = false;

  // ── Alarm trigger guards ──
  bool _isAlarmScreenShowing = false;
  bool _isNavigatingToTrigger = false;

  // ── Toggle debounce + reentrance guard ──
  bool _isTogglingAlarm = false;
  DateTime? _lastToggleTime;
  static const _toggleDebounce = Duration(milliseconds: 300);

  // ── Callback for shells to receive trigger events ──
  VoidCallback? _onAlarmTriggeredCallback;

  // ── Permission state ──
  LocationPermissionStatus? _permissionStatus;
  LocationPermissionStatus? get permissionStatus => _permissionStatus;

  AppStateProvider(this._storage, this._location) {
    _alarmService = AlarmService(_storage, _location);
    _loadInitialState();
  }

  /// Expose the LocationService so screens can reuse it
  /// instead of creating their own instances.
  LocationService get locationService => _location;

  void _loadInitialState() {
    _mode = _storage.getSavedMode();
    _alarms = _alarmService.loadAlarms();
    debugPrint('$_tag Loaded ${_alarms.length} alarms, mode=$_mode');
    debugPrint('$_tag Active alarms: $_activeAlarmCount');
    notifyListeners();
  }

  int get _activeAlarmCount =>
      _alarms.where((a) => a.isActive && !a.hasTriggered).length;

  // ══════════════════════════════════════════
  //  Mode
  // ══════════════════════════════════════════

  Future<void> setMode(AppMode mode) async {
    final previousMode = _mode;
    _mode = mode;
    await _storage.saveMode(mode);
    _commuterTabIndex = 0;
    _travellerTabIndex = 0;

    // Clear stale guide state when switching away from traveller
    if (previousMode == AppMode.traveller && mode != AppMode.traveller) {
      _chatMessages = [];
      _currentPlan = null;
      _arrivalLat = null;
      _arrivalLng = null;
      _guideSession = const GuideSessionState();
      debugPrint('$_tag Cleared traveller guide state on mode switch');
    }

    debugPrint('$_tag Mode set to $mode');
    notifyListeners();
  }

  // ══════════════════════════════════════════
  //  Tab navigation
  // ══════════════════════════════════════════

  void setCommuterTab(int index) {
    _commuterTabIndex = index;
    notifyListeners();
  }

  void setTravellerTab(int index) {
    _travellerTabIndex = index;
    notifyListeners();
  }

  // ══════════════════════════════════════════
  //  Alarm trigger callback registration
  // ══════════════════════════════════════════

  void registerAlarmTriggerCallback(VoidCallback callback) {
    _onAlarmTriggeredCallback = callback;
  }

  void unregisterAlarmTriggerCallback() {
    _onAlarmTriggeredCallback = null;
  }

  void acknowledgeTriggerNavigation() {
    _isNavigatingToTrigger = false;
  }

  // ══════════════════════════════════════════
  //  Alarm CRUD
  // ══════════════════════════════════════════

  Future<void> createAlarm({
    required String name,
    required String locationLabel,
    required double latitude,
    required double longitude,
    required double radiusMeters,
  }) async {
    await _alarmService.createAlarm(
      name: name,
      locationLabel: locationLabel,
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
    );
    _alarms = _alarmService.loadAlarms();
    debugPrint(
      '$_tag Alarm created: "$name". Active count: $_activeAlarmCount',
    );
    notifyListeners();
    _restartTrackingIfNeeded();
  }

  Future<void> updateAlarm(AlarmModel alarm) async {
    await _alarmService.updateAlarm(alarm);
    _alarms = _alarmService.loadAlarms();
    debugPrint(
      '$_tag Alarm updated: "${alarm.name}". Active count: $_activeAlarmCount',
    );
    notifyListeners();
    _restartTrackingIfNeeded();
  }

  Future<void> deleteAlarm(String id) async {
    await _alarmService.deleteAlarm(id);
    _alarms = _alarmService.loadAlarms();
    debugPrint('$_tag Alarm deleted: $id. Active count: $_activeAlarmCount');
    notifyListeners();
    _restartTrackingIfNeeded();
  }

  Future<void> toggleAlarm(String id) async {
    // Debounce: ignore taps within 300ms of the last accepted toggle
    final now = DateTime.now();
    if (_lastToggleTime != null &&
        now.difference(_lastToggleTime!) < _toggleDebounce) {
      debugPrint('$_tag Toggle debounced (too fast)');
      return;
    }
    // Reentrance guard: drop if a toggle is still in progress
    if (_isTogglingAlarm) {
      debugPrint('$_tag Toggle already in progress, ignoring duplicate tap');
      return;
    }
    _lastToggleTime = now;
    _isTogglingAlarm = true;
    try {
      await _alarmService.toggleAlarm(id);
      _alarms = _alarmService.loadAlarms();
      final alarm = _alarms.where((a) => a.id == id).firstOrNull;
      debugPrint(
        '$_tag Alarm toggled: "${alarm?.name}" isActive=${alarm?.isActive}. Active count: $_activeAlarmCount',
      );
      notifyListeners();
      _restartTrackingIfNeeded();
    } finally {
      _isTogglingAlarm = false;
    }
  }

  // ══════════════════════════════════════════
  //  Location tracking — SINGLE SOURCE OF TRUTH
  // ══════════════════════════════════════════

  /// Start location monitoring.
  /// Guards:
  ///   1. _isTrackingActive — prevents call if stream already live
  ///   2. _isStartingTracking — prevents concurrent async calls
  ///   3. _activeAlarmCount — no-op if nothing to monitor
  Future<void> startLocationTracking() async {
    // Guard 1: already running
    if (_isTrackingActive) {
      debugPrint('$_tag Tracking already active, skipping');
      return;
    }
    // Guard 2: another start call is already in-flight
    if (_isStartingTracking) {
      debugPrint('$_tag Tracking startup already in progress, skipping');
      return;
    }
    // Guard 3: nothing to monitor
    if (_activeAlarmCount == 0) {
      debugPrint('$_tag No active alarms, skipping location tracking');
      return;
    }

    // ── Lock: set BEFORE any async work ──
    _isStartingTracking = true;
    debugPrint('$_tag Starting location tracking...');

    try {
      // Permission: only check if not already granted
      if (!_permissionGranted) {
        _permissionStatus = await _location.checkAndRequestPermission();
        if (_permissionStatus != LocationPermissionStatus.granted) {
          debugPrint(
            '$_tag Cannot start tracking: permission=$_permissionStatus',
          );
          notifyListeners();
          return; // finally block resets _isStartingTracking
        }
        _permissionGranted = true;
      }

      // Keep notification permission request close to alarm monitoring start.
      await LocalNotificationService.instance.requestPermissionsIfNeeded();

      // Initial position: only fetch once per app session
      if (!_hasFetchedInitialPosition) {
        _currentPosition = await _location.getPositionUnchecked();
        _hasFetchedInitialPosition = true;
        if (_currentPosition != null) {
          debugPrint(
            '$_tag Initial position: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}',
          );
          _checkAlarmsAgainstPosition(_currentPosition!);
        }
        notifyListeners();
      }

      // Clean up any leftover subscription
      _positionSub?.cancel();
      _positionSub = null;

      // Create the ONE subscription
      _positionSub = _location.getAlarmMonitoringStream().listen(
        (position) {
          _currentPosition = position;
          _checkAlarmsAgainstPosition(position);
          notifyListeners();
        },
        onError: (error) {
          debugPrint('$_tag Location stream error: $error');
        },
        onDone: () {
          debugPrint('$_tag Location stream ended');
          _isTrackingActive = false;
        },
      );

      _isTrackingActive = true;
      debugPrint('$_tag Location tracking STARTED (1 subscription)');
    } finally {
      _isStartingTracking = false;
    }
  }

  void stopLocationTracking() {
    if (!_isTrackingActive && _positionSub == null) return;
    _positionSub?.cancel();
    _positionSub = null;
    _isTrackingActive = false;
    debugPrint('$_tag Location tracking STOPPED');
  }

  /// Re-evaluate whether tracking should be running.
  /// Called after alarm CRUD operations.
  void _restartTrackingIfNeeded() {
    if (_activeAlarmCount > 0 && !_isTrackingActive && !_isStartingTracking) {
      debugPrint('$_tag Active alarms exist, starting tracking');
      startLocationTracking();
    } else if (_activeAlarmCount == 0 && _isTrackingActive) {
      debugPrint('$_tag No active alarms remain, stopping tracking');
      stopLocationTracking();
    }
  }

  // ══════════════════════════════════════════
  //  Alarm checking & triggering
  // ══════════════════════════════════════════

  void _checkAlarmsAgainstPosition(Position position) {
    if (_isAlarmScreenShowing || _isNavigatingToTrigger) return;

    final triggered = _alarmService.checkAlarms(
      position.latitude,
      position.longitude,
      _alarms,
    );

    if (triggered != null) {
      debugPrint(
        '$_tag 🔔 ALARM TRIGGERED: "${triggered.name}" '
        '(radius=${triggered.radiusMeters}m)',
      );
      _triggerAlarm(triggered);
    }
  }

  Future<void> _triggerAlarm(AlarmModel alarm) async {
    // Set ALL guards FIRST
    _isAlarmScreenShowing = true;
    _isNavigatingToTrigger = true;
    _triggeredAlarm = alarm;
    _arrivalLat = alarm.latitude;
    _arrivalLng = alarm.longitude;

    // Persist trigger state — awaited
    await _alarmService.markTriggered(alarm.id);
    _alarms = _alarmService.loadAlarms();

    debugPrint(
      '$_tag Alarm "${alarm.name}" marked as triggered. Active count: $_activeAlarmCount',
    );

    await LocalNotificationService.instance.showAlarmTriggered(
      title: 'You have arrived',
      body: alarm.locationLabel.trim().isNotEmpty
          ? 'Destination: ${alarm.locationLabel.trim()}'
          : alarm.name,
    );

    if (_activeAlarmCount == 0) {
      stopLocationTracking();
    }

    notifyListeners();
    _onAlarmTriggeredCallback?.call();
  }

  /// Called when the alarm trigger screen is dismissed.
  /// Guard prevents double-dismiss from rapid taps.
  bool _isDismissing = false;
  bool _isGuideInitializing = false;

  void dismissAlarmTrigger() {
    if (_isDismissing) {
      debugPrint('$_tag Dismiss already in progress, ignoring duplicate');
      return;
    }
    _isDismissing = true;

    debugPrint('$_tag Alarm trigger dismissed (mode=$_mode)');
    _isAlarmScreenShowing = false;
    _isNavigatingToTrigger = false;

    if (_mode == AppMode.traveller &&
        _arrivalLat != null &&
        _arrivalLng != null) {
      // Dedup: only generate guide if not already initialized
      if (_currentPlan == null && !_isGuideInitializing) {
        unawaited(_initializeTravellerGuidePlan());
      } else {
        debugPrint(
          '$_tag Traveller: guide already initialized, skipping duplicate',
        );
      }
      _travellerTabIndex = 1;
      debugPrint('$_tag Traveller: switching to Guide tab');
    }

    _triggeredAlarm = null;
    _isDismissing = false;
    notifyListeners();
  }

  // ══════════════════════════════════════════
  //  Guide / Chat
  // ══════════════════════════════════════════

  Future<void> _initializeTravellerGuidePlan() async {
    if (_isGuideInitializing || _currentPlan != null) return;
    _isGuideInitializing = true;

    try {
      final initialPlan = await _generateInitialPlanWithFallback();
      _currentPlan = initialPlan;
      _guideSession = _guideSession.copyWith(
        hasConfirmedPlan: true,
        lastConversationSummary: initialPlan.summary,
      );

      if (_chatMessages.isEmpty) {
        _chatMessages = [_guideService.createWelcomeMessage()];
      }

      debugPrint('$_guideTag Intent detected: plan_generation');
      debugPrint('$_guideTag Plan confirmed and loaded into map');
      debugPrint('$_tag Traveller: guide flow initialized');
      notifyListeners();
    } finally {
      _isGuideInitializing = false;
    }
  }

  Future<MockPlanModel> _generateInitialPlanWithFallback() async {
    final fallbackPlan = _guideService.generatePlan(
      _arrivalLat ?? _currentPosition?.latitude ?? 0,
      _arrivalLng ?? _currentPosition?.longitude ?? 0,
    );

    if (!_geminiGuideService.isConfigured) {
      debugPrint(
        '$_geminiTag Guide backend not configured, using mock fallback',
      );
      return fallbackPlan;
    }

    try {
      final requestContext = _buildGuideRequestContext(
        requestType: 'initial_plan',
      );
      final plan = await _geminiGuideService.generateInitialPlan(
        requestContext: requestContext,
      );
      debugPrint('$_guideTag Gemini plan JSON parse succeeded');
      return plan;
    } catch (e) {
      debugPrint('$_guideTag Falling back to mock plan because $e');
      return fallbackPlan;
    }
  }

  Future<String> _chatOnlyWithGeminiOrFallback(String text) async {
    final fallbackText = _guideService.conversationalFallback(
      userMessage: text,
      destination: _guideSession.conversationDestination,
      duration: _guideSession.conversationDuration,
      budget: _guideSession.conversationBudget,
      preferences: _guideSession.conversationPreferences,
    );

    if (!_geminiGuideService.isConfigured) {
      debugPrint(
        '$_guideTag Falling back to mock conversational response because guide backend is not configured',
      );
      return fallbackText;
    }

    try {
      final requestContext = _buildGuideRequestContext(
        requestType: 'chat_only',
        userMessage: text,
      );
      final response = await _geminiGuideService.chatOnlyResponse(
        requestContext: requestContext,
        userMessage: text,
      );
      debugPrint('$_guideTag Gemini chat response received');
      return response;
    } catch (e) {
      debugPrint(
        '$_guideTag Falling back to mock conversational response because $e',
      );
      return fallbackText;
    }
  }

  Future<MockPlanModel> _generatePlanFromConversationWithFallback(
    String text,
  ) async {
    final fallbackPlan = _guideService.generatePlanFromConversation(
      lat: _arrivalLat ?? _currentPosition?.latitude ?? 0,
      lng: _arrivalLng ?? _currentPosition?.longitude ?? 0,
      destination: _guideSession.conversationDestination,
      duration: _guideSession.conversationDuration,
      budget: _guideSession.conversationBudget,
      preferences: _guideSession.conversationPreferences,
    );

    if (!_geminiGuideService.isConfigured) {
      debugPrint(
        '$_guideTag Falling back to mock plan because guide backend is not configured',
      );
      return fallbackPlan;
    }

    try {
      final requestContext = _buildGuideRequestContext(
        requestType: 'initial_plan',
        userMessage: text,
      );
      final plan = await _geminiGuideService.generateInitialPlan(
        requestContext: requestContext,
      );
      debugPrint('$_guideTag Gemini plan JSON parse succeeded');
      return plan;
    } catch (e) {
      debugPrint('$_guideTag Falling back to mock plan because $e');
      return fallbackPlan;
    }
  }

  Future<({String response, MockPlanModel updatedPlan})>
  _refinePlanWithGeminiOrFallback(String text) async {
    final fallback = _guideService.refinePlanFallback(
      userMessage: text,
      currentPlan: _currentPlan!,
      arrivalLat: _arrivalLat ?? _currentPosition?.latitude ?? 0,
      arrivalLng: _arrivalLng ?? _currentPosition?.longitude ?? 0,
    );

    if (!_geminiGuideService.isConfigured) {
      debugPrint(
        '$_guideTag Falling back to mock plan because guide backend is not configured',
      );
      return fallback;
    }

    try {
      final requestContext = _buildGuideRequestContext(
        requestType: 'refine_plan',
        userMessage: text,
        currentPlan: _currentPlan,
      );
      final plan = await _geminiGuideService.refinePlan(
        requestContext: requestContext,
      );
      debugPrint('$_guideTag Gemini plan JSON parse succeeded');
      return (
        response: 'I updated your plan based on your request.',
        updatedPlan: plan,
      );
    } catch (e) {
      debugPrint('$_guideTag Falling back to mock plan because $e');
      return fallback;
    }
  }

  GuideIntent _detectGuideIntent(String text) {
    final msg = text.toLowerCase();
    final hasPlan = _currentPlan != null || _guideSession.hasConfirmedPlan;

    final generationPhrases = [
      'create the plan',
      'make the plan',
      'generate the plan',
      'build it',
      'build the plan',
      'load it',
      'put it into the map',
      'yes create',
      'yes, create',
      'yes generate',
      'generate plan',
    ];

    final refinementHints = [
      'cheaper',
      'budget',
      'less walking',
      'add food',
      'shorter',
      'refine',
      'update plan',
      'change plan',
      'modify plan',
      'fewer tourist',
      'move more things into day',
      'add more',
      'remove',
    ];

    final asksGeneration = generationPhrases.any(msg.contains);
    final asksRefinement = refinementHints.any(msg.contains);

    if (!hasPlan) {
      if (asksGeneration) {
        debugPrint('$_guideTag Intent detected: plan_generation');
        return GuideIntent.planGeneration;
      }
      debugPrint('$_guideTag Intent detected: chat_only');
      debugPrint('$_guideTag No confirmed plan yet, keeping conversation mode');
      return GuideIntent.chatOnly;
    }

    if (asksRefinement || asksGeneration) {
      debugPrint('$_guideTag Intent detected: plan_refinement');
      return GuideIntent.planRefinement;
    }

    debugPrint('$_guideTag Intent detected: chat_only');
    return GuideIntent.chatOnly;
  }

  void _updateGuideSessionFromUserMessage(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) return;

    var destination = _guideSession.conversationDestination;
    var duration = _guideSession.conversationDuration;
    var budget = _guideSession.conversationBudget;
    final prefs = <String>{..._guideSession.conversationPreferences};

    final lower = normalized.toLowerCase();

    final inMatch = RegExp(
      r'\bin\s+([a-zA-Z][a-zA-Z\s]{1,28})',
    ).firstMatch(normalized);
    if (inMatch != null) {
      destination = inMatch.group(1)?.trim();
    }

    final forMatch = RegExp(
      r'\bfor\s+([0-9]+\s*(day|days|hour|hours|weekend))',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (forMatch != null) {
      duration = forMatch.group(1)?.trim();
    }

    final budgetMatch = RegExp(
      r'(£\s?[0-9]+(?:\s?[-–]\s?£?\s?[0-9]+)?\s*(a day|per day)?)',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (budgetMatch != null) {
      budget = budgetMatch.group(1)?.replaceAll('  ', ' ').trim();
    }

    if (lower.contains('food')) prefs.add('food');
    if (lower.contains('museum')) prefs.add('museums');
    if (lower.contains('nightlife')) prefs.add('nightlife');
    if (lower.contains('relaxed') || lower.contains('relax')) {
      prefs.add('relaxed');
    }
    if (lower.contains('less walking')) prefs.add('less walking');

    _guideSession = _guideSession.copyWith(
      conversationDestination: destination,
      conversationDuration: duration,
      conversationBudget: budget,
      conversationPreferences: prefs.toList(),
    );
  }

  void _updateGuideSessionFromAssistantMessage(String text) {
    _guideSession = _guideSession.copyWith(
      lastConversationSummary: text.trim(),
    );
  }

  Map<String, dynamic> _buildGuideRequestContext({
    required String requestType,
    String? userMessage,
    MockPlanModel? currentPlan,
  }) {
    final now = DateTime.now();
    final locale = PlatformDispatcher.instance.locale;

    final map = <String, dynamic>{
      'request_type': requestType,
      'mode': 'traveller',
      'language': locale.languageCode,
      'current_date':
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      'current_time':
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
      'weekday': _weekdayName(now.weekday),
      'already_at_destination': _arrivalLat != null && _arrivalLng != null,
      'has_confirmed_plan': _guideSession.hasConfirmedPlan,
    };

    if (_guideSession.conversationDestination?.trim().isNotEmpty == true) {
      map['destination_name'] = _guideSession.conversationDestination!.trim();
    }
    if (_guideSession.conversationDuration?.trim().isNotEmpty == true) {
      map['time_available'] = _guideSession.conversationDuration!.trim();
    }
    if (_guideSession.conversationBudget?.trim().isNotEmpty == true) {
      map['budget_preference'] = _guideSession.conversationBudget!.trim();
    }
    if (_guideSession.conversationPreferences.isNotEmpty) {
      map['preferences'] = _guideSession.conversationPreferences;
    }
    if (_guideSession.lastConversationSummary?.trim().isNotEmpty == true) {
      map['last_conversation_summary'] = _guideSession.lastConversationSummary!
          .trim();
    }

    if (_currentPosition != null) {
      map['current_latitude'] = _currentPosition!.latitude;
      map['current_longitude'] = _currentPosition!.longitude;
    }

    if (_arrivalLat != null && _arrivalLng != null) {
      map['arrival_latitude'] = _arrivalLat;
      map['arrival_longitude'] = _arrivalLng;
    }

    if (userMessage != null && userMessage.trim().isNotEmpty) {
      map['user_message'] = userMessage.trim();
    }

    if (currentPlan != null) {
      map['current_plan'] = currentPlan.toJson();
    }

    return map;
  }

  String _weekdayName(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Monday';
      case DateTime.tuesday:
        return 'Tuesday';
      case DateTime.wednesday:
        return 'Wednesday';
      case DateTime.thursday:
        return 'Thursday';
      case DateTime.friday:
        return 'Friday';
      case DateTime.saturday:
        return 'Saturday';
      case DateTime.sunday:
        return 'Sunday';
      default:
        return 'Unknown';
    }
  }

  void sendGuideMessage(String text) {
    if (text.trim().isEmpty) return;

    _updateGuideSessionFromUserMessage(text);

    final userMsg = _guideService.createUserMessage(text);
    _chatMessages = [..._chatMessages, userMsg];
    notifyListeners();

    unawaited(_processGuideMessage(text));
  }

  Future<void> _processGuideMessage(String text) async {
    final intent = _detectGuideIntent(text);

    switch (intent) {
      case GuideIntent.chatOnly:
        final response = await _chatOnlyWithGeminiOrFallback(text);
        _updateGuideSessionFromAssistantMessage(response);
        _chatMessages = [
          ..._chatMessages,
          _guideService.createAssistantMessage(response),
        ];
        break;

      case GuideIntent.planGeneration:
        final plan = await _generatePlanFromConversationWithFallback(text);
        _currentPlan = plan;
        _guideSession = _guideSession.copyWith(
          hasConfirmedPlan: true,
          lastConversationSummary: plan.summary,
        );
        _chatMessages = [
          ..._chatMessages,
          _guideService.createAssistantMessage(
            'Great, I created your plan. You can now refine it anytime.',
          ),
        ];
        debugPrint('$_guideTag Plan confirmed and loaded into map');
        break;

      case GuideIntent.planRefinement:
        if (_currentPlan == null) {
          final response = await _chatOnlyWithGeminiOrFallback(text);
          _updateGuideSessionFromAssistantMessage(response);
          _chatMessages = [
            ..._chatMessages,
            _guideService.createAssistantMessage(response),
          ];
          break;
        }

        final result = await _refinePlanWithGeminiOrFallback(text);
        _currentPlan = result.updatedPlan;
        _guideSession = _guideSession.copyWith(
          hasConfirmedPlan: true,
          lastConversationSummary: result.updatedPlan.summary,
        );
        _chatMessages = [
          ..._chatMessages,
          _guideService.createAssistantMessage(result.response),
        ];
        debugPrint('$_guideTag Plan refined and map updated');
        break;
    }

    notifyListeners();
  }

  void clearGuideState() {
    _chatMessages = [];
    _currentPlan = null;
    _arrivalLat = null;
    _arrivalLng = null;
    _guideSession = const GuideSessionState();
    notifyListeners();
  }

  // ══════════════════════════════════════════
  //  Testing / Debug
  // ══════════════════════════════════════════

  void simulateAlarmTrigger(AlarmModel alarm) {
    debugPrint('$_tag [TEST] Simulating trigger for "${alarm.name}"');
    _triggerAlarm(alarm);
  }

  @override
  void dispose() {
    stopLocationTracking();
    _onAlarmTriggeredCallback = null;
    super.dispose();
  }
}
