import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stayapp/point_page.dart';

enum DepartureState {
  normal,
  alarm,
}
enum AlarmState {
  off,
  playing,
}

class TimerPage extends StatefulWidget {

  final double? initialLat;
  final double? initialLng;

  final int durationMinutes;
  final int? durationMinutesFromSchedule;

  final bool forceMode;
  final bool autoStarted;

  final DateTime? startTime;
  final DateTime? endTime;
  final String? title;
  final String? placeName;
  final String? sessionId;


  const TimerPage({
    super.key,
    required this.sessionId,
    required this.initialLat,
    required this.initialLng,
    required this.durationMinutes,
    this.durationMinutesFromSchedule,
    this.forceMode = false,
    this.autoStarted = false,
    this.startTime,
    this.endTime,
    this.title,
    this.placeName,
  });

  @override
  State<TimerPage> createState() => _TimerPageState();
}

class _TimerPageState extends State<TimerPage> with WidgetsBindingObserver {

  bool _isForceExited = false;
  bool _isAlarmRunning = false;
  bool _isTimerOpen = false;
  bool _isNavigating = false;
  bool _isDepartureDialogShowing = false;
  bool _isTimerRunning = false;
  bool _isWaitingForArrival = true;
  bool _isLocationDialogShowing = false;
  bool _isInitializing = true;
  bool _isBannerAdReady = false;
  bool _isAlarmPlaying = false;
  bool _isSessionFinished = false;
  bool _isSnoozing = false;
  bool _isPausedByAction = false; // 미루기/포기/광고 상태 전체 통제
  bool _notificationInitialized = false;
  bool _isAppExitHandling = false;

  List<Map<String, dynamic>> _cachedSchedules = [];
  Timer? _snoozeTimer;
  Timer? _mainTimer;
  Timer? _locationTimer;
  Timer? _alarmRepeatTimer;

  int _snoozeRemainingSeconds = 0;
  int _remainingSeconds = 0;
  int _departureCounter = 0;
  int _outOfRangeSeconds = 0;
  int _targetMinutes = 1;

  final Color pointColor = const Color(0xFF6FD0F1);
  final Color bgColor = const Color(0xFFF0F4F8);
  final Set<String> _triggeredSchedules = {};
  final double _allowedRadius = 100.0; // 오차 허용 반경(교수님 피드백 반영)
  final FlutterRingtonePlayer _ringtonePlayer = FlutterRingtonePlayer();
  final String bannerAdUnitId = 'ca-app-pub-1806802501961110/2044317820';
  final TextEditingController _reasonController = TextEditingController();
  final User? user = FirebaseAuth.instance.currentUser;
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();


  late final String dateKey;
  late final String _prefsKey;
  static const int _locationAlarmDelaySeconds = 5;

  DateTime? _outOfRangeStartedAt;
  double? _targetLat;
  double? _targetLng;
  double _progress = 1.0;
  double _movementDistance = 0;
  double _calibratedLat = 0;
  double _calibratedLng = 0;

  String _timeLeft = '00:00:00';
  String _activeTitle = '집중 세션';
  String? _sessionId;

  DateTime? _outStartTime;
  DateTime? _alarmSnoozeUntil;
  DateTime? _sessionStartTime;
  DateTime? _sessionEndTime; // 추가
  Position? _startPosition;

  // Undefined name 오류 해결
  bool _isCalibrated = false;
  Timer? _departureTimer;
  RewardedAd? _rewardedAd;
  BannerAd? _bannerAd;
  Position? _lastPosition;
  int _elapsedSeconds = 0;

  StreamSubscription<Position>? _positionStream;


  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _initializeNotifications();

    _activeTitle = widget.title ?? '집중 세션';
    _isAlarmPlaying = false;
    _isInitializing = true;
    _isSessionFinished = false;

    _sessionId = widget.sessionId ??
        DateTime.now().millisecondsSinceEpoch.toString();

    _prefsKey = _sessionId!;

    dateKey = DateFormat('yyyy-MM-dd').format(DateTime.now());

    _targetMinutes = widget.durationMinutes > 0
        ? widget.durationMinutes
        : (widget.durationMinutesFromSchedule ?? 1);

    _remainingSeconds = _targetMinutes * 60;
    _timeLeft = _formatTime(_remainingSeconds);

    FlutterRingtonePlayer().stop();

    _targetLat = widget.initialLat;
    _targetLng = widget.initialLng;

    _initializeAppState();
  }

  @override
  Future<bool> didPopRoute() async {
    // 강제모드 공부 중에는 뒤로가기 버튼으로 TimerPage를 나갈 수 없음
    if (widget.forceMode &&
        !_isSessionFinished &&
        !_isWaitingForArrival) {
      return true;
    }

    return false;
  }



  Future<void> _initializeNotifications() async {
    if (_notificationInitialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const settings = InitializationSettings(
      android: androidSettings,
    );

    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        // 알림 클릭 시 앱으로 복귀
      },
    );

    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.requestNotificationsPermission();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'study_timer_channel',
        '공부 타이머',
        description: '공부 세션 타이머 알림',
        importance: Importance.high,
        playSound: false,
        enableVibration: false,
        showBadge: false,
      ),
    );

    _notificationInitialized = true;
  }

  Future<void> _showTimerNotification() async {
    if (!_notificationInitialized) {
      await _initializeNotifications();
    }

    if (_isSessionFinished) {
      await _notifications.cancel(9999);
      return;
    }

    if (_isWaitingForArrival ||
        _isSnoozing ||
        !_isTimerRunning ||
        _remainingSeconds <= 0) {
      return;
    }

    final String remainingTime = _formatTime(_remainingSeconds);

    final AndroidNotificationDetails androidDetails =
    AndroidNotificationDetails(
      'study_timer_channel',
      '공부 타이머',
      channelDescription: '공부 세션 타이머 알림',
      importance: Importance.high,
      priority: Priority.high,

      // 알림을 스와이프로 제거하지 못하게 함
      ongoing: true,
      autoCancel: false,

      onlyAlertOnce: true,
      playSound: false,
      enableVibration: false,
      showWhen: false,

      category: AndroidNotificationCategory.progress,
      visibility: NotificationVisibility.public,
      icon: '@mipmap/ic_launcher',
      ticker: remainingTime,
      subText: _activeTitle, // ★ '집중 세션' 고정 문구에서 일정 제목변수로 수정
    );

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    await _notifications.show(
      9999,
      _activeTitle,
      '남은 시간 $remainingTime',
      details,
    );
  }
  Future<void> _failSessionForTampering(String reason) async {
    if (_isSessionFinished || !widget.forceMode) return;

    _isSessionFinished = true;
    _isPausedByAction = true;

    _mainTimer?.cancel();
    _mainTimer = null;
    _snoozeTimer?.cancel();
    _snoozeTimer = null;
    _positionStream?.cancel();
    _positionStream = null;
    _locationTimer?.cancel();
    _locationTimer = null;
    _departureTimer?.cancel();
    _alarmRepeatTimer?.cancel();
    _alarmRepeatTimer = null;
    _alarmLoopTimer?.cancel();
    _alarmLoopTimer = null;

    _stopAlarm();
    await _cancelTimerNotification();

    final uid = FirebaseAuth.instance.currentUser?.uid;
    final sessionId = _sessionId;

    if (uid == null || sessionId == null) return;

    // 패널티 차감 및 DB 세션 정보 최종 갱신
    await _updateUserPoints(-100);
    await _saveSessionResult(true, reason);

    _forceCleanupAll();

    if (mounted) {
      Navigator.of(context).pop(false);
    }
  }
  Future<void> _checkNotificationPermission() async {
    if (_isSessionFinished || !widget.forceMode) return;

    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    final bool? enabled =
    await androidPlugin?.areNotificationsEnabled();

    if (enabled == false) {
      await _failSessionForTampering(
        '공부 중 알림 권한 해제',
      );
    }
  }


  Future<void> _checkLocationPermissionAndService() async {
    if (_isSessionFinished || !widget.forceMode) return;

    final serviceEnabled =
    await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      await _failSessionForTampering(
        '공부 중 GPS 위치 서비스 해제',
      );
      return;
    }

    final permission =
    await Geolocator.checkPermission();

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      await _failSessionForTampering(
        '공부 중 GPS 위치 권한 해제',
      );
    }
  }


  Future<void> _checkSessionIntegrity() async {
    if (_isSessionFinished ||
        _isWaitingForArrival ||
        !_isCalibrated) {
      return;
    }

    await _checkNotificationPermission();

    if (_isSessionFinished) return;

    await _checkLocationPermissionAndService();
  }


  Future<void> _cancelTimerNotification() async {
    try {
      await _notifications.cancel(9999);
    } catch (e) {
      debugPrint(
        '타이머 알림 제거 오류: $e',
      );
    }
  }

  Future<void> _initializeAppState() async {
    await _initAds();

    // ★ 타이머 화면에서 스케줄을 DB에서 다시 찾지 않음
    // ★ 메인 화면에서 전달받은 initialLat / initialLng만 사용
    await _initializeSession();

    if (!mounted || _isSessionFinished) return;

    _initLocationTracking();
  }

  Future<void> _initializeSession() async {
    try {
      if (user == null) {
        if (mounted) {
          setState(() {
            _isInitializing = false;
          });
        }
        _showSnack('로그인이 필요합니다.');
        return;
      }

      double? lat = widget.initialLat;
      double? lng = widget.initialLng;

      // 전달된 좌표가 없을 경우 세션 문서에서 장소 좌표 복구
      if (lat == null ||
          lng == null ||
          !lat.isFinite ||
          !lng.isFinite ||
          (lat == 0.0 && lng == 0.0)) {
        try {
          final doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user!.uid)
              .collection('study_schedules')
              .doc(widget.sessionId)
              .get();

          if (doc.exists) {
            final data = doc.data() ?? {};

            lat = (data['lat'] as num?)?.toDouble() ??
                (data['latitude'] as num?)?.toDouble() ??
                (data['gps_lat'] as num?)?.toDouble() ??
                (data['place_lat'] as num?)?.toDouble() ??
                (data['location_lat'] as num?)?.toDouble();

            lng = (data['lng'] as num?)?.toDouble() ??
                (data['longitude'] as num?)?.toDouble() ??
                (data['gps_lng'] as num?)?.toDouble() ??
                (data['place_lng'] as num?)?.toDouble() ??
                (data['location_lng'] as num?)?.toDouble();

            final place = data['place'];

            if ((lat == null || lng == null) && place is Map) {
              lat ??= (place['lat'] as num?)?.toDouble() ??
                  (place['latitude'] as num?)?.toDouble() ??
                  (place['gps_lat'] as num?)?.toDouble();

              lng ??= (place['lng'] as num?)?.toDouble() ??
                  (place['longitude'] as num?)?.toDouble() ??
                  (place['gps_lng'] as num?)?.toDouble();
            }
          }
        } catch (e) {
          debugPrint('일정 장소 좌표 복구 오류: $e');
        }
      }

      if (lat == null ||
          lng == null ||
          !lat.isFinite ||
          !lng.isFinite ||
          (lat == 0.0 && lng == 0.0)) {
        if (mounted) {
          setState(() {
            _isInitializing = false;
            _isWaitingForArrival = true;
          });
        }

        _showSnack('공부 장소 위치 정보가 없습니다.');
        return;
      }

      _targetLat = lat;
      _targetLng = lng;

      debugPrint(
        'TimerPage 장소 좌표 확정: '
            'lat=$_targetLat, lng=$_targetLng',
      );

      final bool serviceEnabled =
      await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _isInitializing = false;
            _isWaitingForArrival = true;
          });
        }

        _showSnack('휴대폰 위치 서비스를 켜주세요.');
        return;
      }

      LocationPermission permission =
      await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _isInitializing = false;
            _isWaitingForArrival = true;
          });
        }

        _showSnack('위치 권한이 필요합니다.');
        return;
      }

      Position? currentPosition;

      try {
        currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.bestForNavigation,
          timeLimit: const Duration(seconds: 10),
        );
      } catch (e) {
        debugPrint('최초 GPS 획득 실패: $e');

        if (mounted) {
          setState(() {
            _isInitializing = false;
            _isWaitingForArrival = true;
            _isTimerRunning = false;
          });
        }

        _initLocationTracking();
        return;
      }

      if (!mounted || _isSessionFinished) return;

      _lastPosition = currentPosition;

      final double distanceFromTarget =
      Geolocator.distanceBetween(
        _targetLat!,
        _targetLng!,
        currentPosition.latitude,
        currentPosition.longitude,
      );

      _movementDistance = distanceFromTarget;

      if (distanceFromTarget <= _allowedRadius) {
        await _startArrivalAndTimer(currentPosition);
        return;
      }

      if (mounted) {
        setState(() {
          _isInitializing = false;
          _isWaitingForArrival = true;
          _isTimerRunning = false;
        });
      }

      _initLocationTracking();
    } catch (e, stackTrace) {
      debugPrint('TimerPage 초기화 오류: $e');
      debugPrint('$stackTrace');

      if (!mounted) return;

      setState(() {
        _isInitializing = false;
        _isWaitingForArrival = true;
        _isTimerRunning = false;
      });

      _initLocationTracking();
    }
  }


  @override
  void dispose() {
    _stopAlarm();

    _mainTimer?.cancel();
    _mainTimer = null;

    _snoozeTimer?.cancel();
    _snoozeTimer = null;

    _positionStream?.cancel();
    _positionStream = null;

    _locationTimer?.cancel();
    _locationTimer = null;

    _departureTimer?.cancel();
    _departureTimer = null;

    _alarmRepeatTimer?.cancel();
    _alarmRepeatTimer = null;

    _alarmLoopTimer?.cancel();
    _alarmLoopTimer = null;

    _cancelTimerNotification();

    _bannerAd?.dispose();
    _rewardedAd?.dispose();

    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  Future<void> _startArrivalAndTimer(Position position) async {
    if (_isSessionFinished ||
        _isForceExited ||
        _isCalibrated) {
      return;
    }

    // ============================================================
    // 최초 도착 GPS를 기준점으로 확정
    // ============================================================

    _calibratedLat = position.latitude;
    _calibratedLng = position.longitude;

    _startPosition = position;

    _isCalibrated = true;
    _isWaitingForArrival = false;

    _outOfRangeStartedAt = null;
    _outStartTime = null;
    _outOfRangeSeconds = 0;

    // ============================================================
    // 알람 제거
    // ============================================================

    _stopAlarm();

    _alarmRepeatTimer?.cancel();
    _alarmRepeatTimer = null;

    // ============================================================
    // 미루기 상태 제거
    // ============================================================

    _snoozeTimer?.cancel();
    _snoozeTimer = null;

    _snoozeRemainingSeconds = 0;
    _isSnoozing = false;
    _isPausedByAction = false;

    // ============================================================
    // 위치 팝업 제거
    // ============================================================

    if (_isDepartureDialogShowing &&
        mounted &&
        Navigator.of(
          context,
          rootNavigator: true,
        ).canPop()) {
      Navigator.of(
        context,
        rootNavigator: true,
      ).pop();
    }

    _isDepartureDialogShowing = false;

    // ============================================================
    // 화면 상태 초기화
    // ============================================================

    if (mounted) {
      setState(() {
        _isInitializing = false;
        _isWaitingForArrival = false;
        _isTimerRunning = false;
        _isAlarmRunning = false;
        _isAlarmPlaying = false;
        _isSnoozing = false;
        _isPausedByAction = false;
        _movementDistance = 0;
      });
    }

    // ============================================================
    // 최초 도착 위치 저장
    // DB:
    // users/{uid}/study_sessions/{sessionId}
    // ============================================================

    final user = FirebaseAuth.instance.currentUser;

    if (user != null && _sessionId != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('study_sessions')
            .doc(_sessionId)
            .set(
          {
            'gps_lat': position.latitude,
            'gps_lng': position.longitude,
            'arrival_verified': true,
          },
          SetOptions(merge: true),
        );
      } catch (e) {
        debugPrint('도착 위치 저장 오류: $e');
      }
    }

    // ============================================================
    // 자동 타이머 시작
    // ============================================================

    if (!_isSessionFinished) {
      _startStudyTimer();
    }
  }
  Future<void> _initAds() async {
    await MobileAds.instance.initialize();
    _loadBannerAd();
    _loadRewardedAd();
  }

  Widget _buildPointDisplay(String uid) {
    final bool isDarkMode =
        Theme.of(context).brightness == Brightness.dark;

    final Color cardColor =
    isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;

    final Color pointTextColor =
    isDarkMode ? const Color(0xFFFFB74D) : const Color(0xFFE58B00);

    final Color starBackgroundColor =
    isDarkMode
        ? Colors.orange.withOpacity(0.18)
        : Colors.orange.withOpacity(0.11);

    final Color borderColor =
    isDarkMode
        ? Colors.orange.withOpacity(0.22)
        : Colors.orange.withOpacity(0.12);

    final Color shadowColor =
    isDarkMode
        ? Colors.black.withOpacity(0.20)
        : Colors.black.withOpacity(0.035);

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('user_profile')
          .doc('current')
          .snapshots(),
      builder: (context, snapshot) {
        int point = 0;

        if (snapshot.hasData && snapshot.data!.exists) {
          final profile =
          snapshot.data!.data() as Map<String, dynamic>?;

          final dynamic rawPoint = profile?['point'];

          if (rawPoint is num) {
            point = rawPoint.toInt();
          } else {
            point = int.tryParse(
              rawPoint?.toString() ?? '0',
            ) ??
                0;
          }
        }

        return Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PointPage(),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: borderColor,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: shadowColor,
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: starBackgroundColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.stars_rounded,
                        color: Colors.orange,
                        size: 17,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      "${NumberFormat('#,###').format(point)} P",
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: pointTextColor,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (_isSessionFinished ||
        _isAppExitHandling) {
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _handleAppExit();
    }
  }

  Future<void> _handleAppExit() async {
    if (_isSessionFinished ||
        _isAppExitHandling) {
      return;
    }

    if (_sessionId == null ||
        _sessionId!.isEmpty) {
      return;
    }

    _isAppExitHandling = true;

    try {
      await _markForceSessionFailed(
        '앱 종료 또는 백그라운드 이탈',
        _sessionId!,
      );

      _forceCleanupAll();
    } catch (e) {
      debugPrint(
        '앱 종료 실패 처리 오류: $e',
      );
    }
  }


  Future<void> _saveTimerState() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt(
      'remain_$_prefsKey',
      _remainingSeconds,
    );

    await prefs.setInt(
      'elapsed_$_prefsKey',
      _elapsedSeconds,
    );

    await prefs.setInt(
      'target_$_prefsKey',
      _targetMinutes,
    );

    await prefs.setString(
      'last_time_$_prefsKey',
      DateTime.now().toIso8601String(),
    );

    if (!_isSessionFinished &&
        !_isWaitingForArrival &&
        _isTimerRunning &&
        !_isSnoozing &&
        _remainingSeconds > 0) {
      await _showTimerNotification();
    }
  }

  Future<void> _restoreTimerState() async {
    if (_isWaitingForArrival || !_isCalibrated) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    final remain = prefs.getInt('remain_$_prefsKey');
    final elapsed = prefs.getInt('elapsed_$_prefsKey');
    final target = prefs.getInt('target_$_prefsKey');
    final lastTime = prefs.getString('last_time_$_prefsKey');

    if (remain == null ||
        elapsed == null ||
        target == null ||
        lastTime == null) {
      return;
    }

    final pausedDuration =
    DateTime.now().difference(
      DateTime.parse(lastTime),
    );

    final diffSeconds = pausedDuration.inSeconds;

    _targetMinutes = target;

    _remainingSeconds =
        (remain - diffSeconds).clamp(0, 999999);

    _elapsedSeconds =
        elapsed + diffSeconds;

    if (!mounted) return;

    setState(() {
      _timeLeft =
          _formatTime(_remainingSeconds);

      _progress =
          (_remainingSeconds /
              (_targetMinutes * 60))
              .clamp(0.0, 1.0);
    });

    if (_remainingSeconds <= 0) {
      await _cancelTimerNotification();

      if (!_isSessionFinished) {
        _showSuccessDialog();
      }

      return;
    }

    if (!_isWaitingForArrival &&
        _isCalibrated) {
      _isTimerRunning = false;
      _startStudyTimer();
    }
  }


  // [추가된 함수] 포인트 업데이트 로직 (Firestore 트랜잭션)
  Future<void> _updateUserPoints(int amount) async {
    if (user == null) return;
    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .collection('user_profile')
        .doc('current');

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(userRef);

        int currentPoints = 0;
        if (snapshot.exists) {
          final data = snapshot.data();
          currentPoints = ((data?['point'] ?? data?['point'] ?? 0) as num).toInt();
        }

        final updatedPoints = currentPoints + amount;

        transaction.set(
          userRef,
          {
            'point': updatedPoints < 0 ? 0 : updatedPoints,
            'updated_at': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });
    } catch (e) {
      debugPrint("포인트 변동 오류: $e");
    }
  }
  // [수정된 함수] 포기 사유 입력 다이얼로그
  // 포기 사유 입력 다이얼로그
  Future<String?> _showReasonInputDialog({
    required int penaltyPoints,
  }) async {
    final bool isDarkMode =
        Theme.of(context).brightness == Brightness.dark;

    final Color dialogBackground =
    isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
    final Color titleColor =
    isDarkMode ? Colors.white : const Color(0xFF202124);
    final Color contentColor =
    isDarkMode ? Colors.white70 : const Color(0xFF888888);
    final Color inputBackground =
    isDarkMode ? const Color(0xFF2A2A2A) : const Color(0xFFF7F8FA);
    final Color inputTextColor =
    isDarkMode ? Colors.white : const Color(0xFF202124);
    final Color hintColor =
    isDarkMode ? Colors.white38 : const Color(0xFFAAAAAA);
    final Color cancelTextColor =
    isDarkMode ? Colors.white70 : const Color(0xFF555555);
    final Color cancelBorderColor =
    isDarkMode ? Colors.white24 : const Color(0xFFE1E4E8);
    final Color disabledButtonColor =
    isDarkMode ? const Color(0xFF3A3A3A) : const Color(0xFFE8EAED);

    final TextEditingController controller = TextEditingController();

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.45),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: dialogBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: StatefulBuilder(
                builder: (builderContext, setStateModal) {
                  final bool isValid = controller.text.trim().isNotEmpty;

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '포기하시겠습니까?',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$penaltyPoints P가 차감됩니다.',
                        style: TextStyle(
                          fontSize: 13,
                          color: contentColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: controller,
                        autofocus: true,
                        maxLines: 2,
                        minLines: 2,
                        textInputAction: TextInputAction.done,
                        style: TextStyle(
                          fontSize: 14,
                          color: inputTextColor,
                        ),
                        onChanged: (_) {
                          setStateModal(() {});
                        },
                        decoration: InputDecoration(
                          hintText: '포기 사유를 입력해주세요',
                          hintStyle: TextStyle(
                            color: hintColor,
                            fontSize: 14,
                          ),
                          filled: true,
                          fillColor: inputBackground,
                          contentPadding: const EdgeInsets.all(12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFF6FD0F1),
                              width: 1.2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 44,
                              child: OutlinedButton(
                                onPressed: () {
                                  Navigator.of(dialogContext).pop(null);
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: cancelTextColor,
                                  side: BorderSide(
                                    color: cancelBorderColor,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text(
                                  '취소',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SizedBox(
                              height: 44,
                              child: ElevatedButton(
                                onPressed: isValid
                                    ? () {
                                  final String result =
                                  controller.text.trim();
                                  Navigator.of(dialogContext).pop(result);
                                }
                                    : null,
                                style: ElevatedButton.styleFrom(
                                  elevation: 0,
                                  backgroundColor: const Color(0xFF6FD0F1),
                                  disabledBackgroundColor: disabledButtonColor,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: Text(
                                  '포기하기 ($penaltyPoints P)',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  void _initLocationTracking() {
    if (_isSessionFinished ||
        _isForceExited) {
      return;
    }

    if (_targetLat == null ||
        _targetLng == null ||
        !_targetLat!.isFinite ||
        !_targetLng!.isFinite ||
        (_targetLat == 0.0 &&
            _targetLng == 0.0)) {
      return;
    }

    _positionStream?.cancel();

    const LocationSettings locationSettings =
    LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );

    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: locationSettings,
        ).listen(
              (Position position) async {
            if (!mounted ||
                _isSessionFinished ||
                _isForceExited) {
              return;
            }

            _lastPosition = position;

            try {
              await _checkLocationLogic(position);

              if (!_isSessionFinished &&
                  _isCalibrated &&
                  !_isWaitingForArrival) {
                await _checkLocationPermissionAndService();
              }
            } catch (e) {
              debugPrint(
                '위치 처리 오류: $e',
              );
            }
          },
          onError: (error) async {
            debugPrint(
              '위치 스트림 오류: $error',
            );

            if (!_isSessionFinished &&
                _isCalibrated) {
              await _failSessionForTampering(
                '공부 중 GPS 위치 추적 중단',
              );
            }
          },
          cancelOnError: false,
        );
  }

  // 1. 포인트 체크 후 액션 수행 (미루기/포기 통합 로직)
  Future<void> _checkPointsAndExecute(int requiredPoints, Function onSuccess) async {
    final currentPoints = await _getCurrentPoints();
    if (currentPoints >= requiredPoints) {
      onSuccess();
    } else {
      _showNeedPointDialog(requiredPoint: requiredPoints, onAction: onSuccess);
    }
  }


// 중도 해제 버튼을 눌렀을 때 실행되는 함수
  Future<void> _onCancelBeforeStart() async {
    if (_isSessionFinished) return;

    final reason =
    await _showReasonInputDialog(
      penaltyPoints: 200,
    );

    if (reason == null) return;

    await _checkPointsAndExecute(
      200,
          () async {
        await _updateUserPoints(-200);

        await _forceFailSession(
          "시작 전 포기: $reason",
          pointDeduction: -200,
        );
      },
    );
  }


  Future<void> _forceFailSession(
      String reason, {
        required int pointDeduction,
      }) async {
    if (user == null || _isSessionFinished) {
      return;
    }

    _isSessionFinished = true;

    _stopAlarm();
    _mainTimer?.cancel();
    _mainTimer = null;
    _snoozeTimer?.cancel();
    _snoozeTimer = null;

    await _cancelTimerNotification();

    // DB에 실패 상태 및 포기 사유 저장
    await _saveSessionResult(
      true,
      reason,
    );

    _forceCleanupAll();

    if (mounted) {
      Navigator.of(context).pop(false);
    }
  }  // 광고 시청 후 포인트 2배 적립 함수

  Future<void> _checkLocationLogic(Position position) async {
    if (_isForceExited || _isSessionFinished) {
      return;
    }

    _lastPosition = position;

    // ============================================================
    // ① 아직 지정 장소에 도착하지 않은 상태
    // 메인 화면에서 전달받은 _targetLat / _targetLng와 비교
    // ============================================================

    if (!_isCalibrated) {
      if (_targetLat == null ||
          _targetLng == null ||
          !_targetLat!.isFinite ||
          !_targetLng!.isFinite ||
          (_targetLat == 0.0 && _targetLng == 0.0)) {
        return;
      }

      final double targetDistance = Geolocator.distanceBetween(
        _targetLat!,
        _targetLng!,
        position.latitude,
        position.longitude,
      );

      if (mounted) {
        setState(() {
          _movementDistance = targetDistance;
          _isWaitingForArrival = targetDistance > 10.0;
          _isTimerRunning = false;
        });
      }

      debugPrint(
        '지정 장소와 현재 GPS 거리: '
            '${targetDistance.toStringAsFixed(1)}m',
      );

      // ==========================================================
      // ★ 지정 장소 도착
      // 현재 핸드폰 GPS를 "최초 기준 위치"로 저장
      // ==========================================================

      if (targetDistance <= 10.0) {
        // 도착 전 타이머는 항상 중지
        _mainTimer?.cancel();
        _mainTimer = null;
        _isTimerRunning = false;

        // 현재 핸드폰 GPS를 기준점으로 확정
        _calibratedLat = position.latitude;
        _calibratedLng = position.longitude;
        _isCalibrated = true;

        _outOfRangeStartedAt = null;
        _outStartTime = null;
        _outOfRangeSeconds = 0;

        // 기존 알람 완전히 중지
        _stopAlarm();

        _alarmLoopTimer?.cancel();
        _alarmLoopTimer = null;

        _alarmRepeatTimer?.cancel();
        _alarmRepeatTimer = null;

        // 기존 위치 이탈 팝업이 열려 있으면 닫기
        if (_isDepartureDialogShowing ||
            _isLocationDialogShowing) {
          if (mounted &&
              Navigator.of(
                context,
                rootNavigator: true,
              ).canPop()) {
            Navigator.of(
              context,
              rootNavigator: true,
            ).pop();
          }
        }

        _isDepartureDialogShowing = false;
        _isLocationDialogShowing = false;

        _isAlarmRunning = false;
        _isAlarmPlaying = false;
        _isWaitingForArrival = false;
        _isPausedByAction = false;

        if (mounted) {
          setState(() {
            _movementDistance = 0.0;
            _isWaitingForArrival = false;
            _isTimerRunning = false;
            _isAlarmRunning = false;
            _isAlarmPlaying = false;
          });
        }

        debugPrint(
          '===== 최초 도착 기준 GPS 확정 =====\n'
              'lat=$_calibratedLat\n'
              'lng=$_calibratedLng',
        );

        // 도착한 순간부터 공부 타이머 시작
        if (!_isSessionFinished &&
            !_isSnoozing &&
            !_isPausedByAction) {
          _startStudyTimer();
        }

        return;
      }

      // ==========================================================
      // ★ 아직 지정 장소에 도착하지 않음
      // 타이머 시작 금지
      // ==========================================================

      _mainTimer?.cancel();
      _mainTimer = null;
      _isTimerRunning = false;

      // 알람 + 기존 선택창 표시
      if (!_isSessionFinished &&
          !_isDepartureDialogShowing &&
          !_isSnoozing &&
          !_isPausedByAction) {
        _startAlarm();
        _showPointActionDialog();
      }

      return;
    }

    // ============================================================
    // ② 최초 도착 이후
    //
    // ★ 메인에서 받은 위치값은 더 이상 사용하지 않음
    // ★ 최초 도착 순간의 핸드폰 GPS를 기준점으로 사용
    // ============================================================

    if (!_calibratedLat.isFinite ||
        !_calibratedLng.isFinite ||
        (_calibratedLat == 0.0 &&
            _calibratedLng == 0.0)) {
      return;
    }

    final double distanceFromBaseline =
    Geolocator.distanceBetween(
      _calibratedLat,
      _calibratedLng,
      position.latitude,
      position.longitude,
    );

    if (mounted) {
      setState(() {
        _movementDistance = distanceFromBaseline;
      });
    }

    debugPrint(
      '최초 도착 GPS 기준 현재 거리: '
          '${distanceFromBaseline.toStringAsFixed(1)}m',
    );

    // ============================================================
    // ③ 기준점에서 100m 이내
    // ============================================================

    if (distanceFromBaseline <= _allowedRadius) {
      _outOfRangeStartedAt = null;
      _outStartTime = null;
      _outOfRangeSeconds = 0;

      // 알람 즉시 중지
      _stopAlarm();

      _alarmLoopTimer?.cancel();
      _alarmLoopTimer = null;

      _alarmRepeatTimer?.cancel();
      _alarmRepeatTimer = null;

      // 열려 있는 위치 이탈 팝업 제거
      if (_isDepartureDialogShowing ||
          _isLocationDialogShowing) {
        if (mounted &&
            Navigator.of(
              context,
              rootNavigator: true,
            ).canPop()) {
          Navigator.of(
            context,
            rootNavigator: true,
          ).pop();
        }
      }

      _isDepartureDialogShowing = false;
      _isLocationDialogShowing = false;

      if (mounted) {
        setState(() {
          _isAlarmRunning = false;
          _isAlarmPlaying = false;
          _isWaitingForArrival = false;
        });
      }

      // 다시 들어왔으면 타이머 재시작
      if (!_isTimerRunning &&
          !_isSessionFinished &&
          !_isSnoozing &&
          !_isPausedByAction) {
        _startStudyTimer();
      }

      return;
    }

    // ============================================================
    // ④ 기준점에서 100m 초과
    // ============================================================

    _outOfRangeStartedAt ??= DateTime.now();
    _outStartTime ??= _outOfRangeStartedAt;

    _outOfRangeSeconds = DateTime.now()
        .difference(_outOfRangeStartedAt!)
        .inSeconds;

    debugPrint(
      '최초 도착 기준 100m 이탈 상태: '
          '$_outOfRangeSeconds초',
    );

    // ============================================================
    // ★ 40초 이상 이탈
    // ============================================================

    if (_outOfRangeSeconds >= 40) {
      _mainTimer?.cancel();
      _mainTimer = null;

      if (mounted) {
        setState(() {
          _isTimerRunning = false;
        });
      }

      // 미루기 중에는 팝업/알람 새로 띄우지 않음
      if (_isSnoozing ||
          _isPausedByAction ||
          _isSessionFinished) {
        return;
      }

      // 이미 팝업이 떠 있으면 중복 생성하지 않음
      if (!_isDepartureDialogShowing) {
        _startAlarm();
        _showPointActionDialog();
      }
    }
  }

  Future<bool> _onWillPop() async {
    if (widget.forceMode &&
        !_isSessionFinished &&
        !_isWaitingForArrival) {
      return false;
    }

    return true;
  }


  Future<void> _saveSessionResult(bool isFailed, String reason) async {
    final uid = user?.uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _sessionId == null) return;

    final sessionRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('study_sessions')
        .doc(_sessionId);

    final now = DateTime.now();
    final actualMinutes = _elapsedSeconds ~/ 60;

    // 시작 시간이 없으면 현재 시간 기준 시작 혹은 계산된 시간으로 대체
    final startTimeStr = _sessionStartTime?.toIso8601String() ??
        now.subtract(Duration(seconds: _elapsedSeconds)).toIso8601String();
    final endTimeStr = now.toIso8601String();

    await sessionRef.set({
      'schedule_id': _sessionId,                     // 연결된 일정 ID
      'date': dateKey,                               // yyyy-MM-dd
      'subject': _activeTitle,                       // 공부 과목
      'place_name': widget.placeName ?? '',          // 공부 장소명
      'place_address': '',                           // 장소 주소 (기본값 설정)
      'start_time': startTimeStr,                    // 시작 시간
      'end_time': endTimeStr,                        // 종료 시간
      'study_minutes': actualMinutes,                // 실제 공부시간 (분 단위)
      'gps_lat': _calibratedLat,                     // 실제 GPS 위도
      'gps_lng': _calibratedLng,                     // 실제 GPS 경도
      'distance_from_home': _movementDistance.toInt(), // 집/기준점과의 거리
      'departure_count': _departureCounter,          // 자리 이탈 횟수
      'arrival_verified': _isCalibrated,             // 도착 여부
      'is_success': !isFailed,                       // 성공 여부
      'is_failed': isFailed,                         // 실패 여부
      'stop_time': isFailed ? endTimeStr : null,     // 중단 시간
      'give_up_reason': isFailed ? reason : '',      // 포기/실패 이유
      'created_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  void _evaluateCachedSchedules() async {
    if (!mounted) return;
    if (_isTimerOpen || _isNavigating) return;
    if (_cachedSchedules.isEmpty) return;

    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);

    for (final data in _cachedSchedules) {
      final String docId =
          data['doc_id']?.toString() ??
              data['id']?.toString() ??
              data['event_id']?.toString() ??
              data['eventId']?.toString() ??
              '';

      if (docId.isEmpty) continue;
      if (_triggeredSchedules.contains(docId)) continue;

      final String status =
          data['status']?.toString() ?? '';

      if (status == 'completed' ||
          status == 'cancelled' ||
          status == 'deleted') {
        continue;
      }

      if (data['isFinished'] == true ||
          data['is_finished'] == true) {
        continue;
      }

      double? lat =
          (data['lat'] as num?)?.toDouble() ??
              (data['latitude'] as num?)?.toDouble() ??
              (data['gps_lat'] as num?)?.toDouble() ??
              (data['place_lat'] as num?)?.toDouble() ??
              (data['location_lat'] as num?)?.toDouble();

      double? lng =
          (data['lng'] as num?)?.toDouble() ??
              (data['longitude'] as num?)?.toDouble() ??
              (data['gps_lng'] as num?)?.toDouble() ??
              (data['place_lng'] as num?)?.toDouble() ??
              (data['location_lng'] as num?)?.toDouble();

      final dynamic placeData = data['place'];

      if ((lat == null || lng == null) && placeData is Map) {
        lat ??=
            (placeData['lat'] as num?)?.toDouble() ??
                (placeData['latitude'] as num?)?.toDouble() ??
                (placeData['gps_lat'] as num?)?.toDouble();

        lng ??=
            (placeData['lng'] as num?)?.toDouble() ??
                (placeData['longitude'] as num?)?.toDouble() ??
                (placeData['gps_lng'] as num?)?.toDouble();
      }

      if (lat == null || lng == null) {
        try {
          final scheduleDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user?.uid)
              .collection('study_schedules')
              .doc(docId)
              .get();

          if (scheduleDoc.exists) {
            final scheduleData = scheduleDoc.data() ?? {};

            lat ??=
                (scheduleData['lat'] as num?)?.toDouble() ??
                    (scheduleData['latitude'] as num?)?.toDouble() ??
                    (scheduleData['gps_lat'] as num?)?.toDouble() ??
                    (scheduleData['place_lat'] as num?)?.toDouble() ??
                    (scheduleData['location_lat'] as num?)?.toDouble();

            lng ??=
                (scheduleData['lng'] as num?)?.toDouble() ??
                    (scheduleData['longitude'] as num?)?.toDouble() ??
                    (scheduleData['gps_lng'] as num?)?.toDouble() ??
                    (scheduleData['place_lng'] as num?)?.toDouble() ??
                    (scheduleData['location_lng'] as num?)?.toDouble();

            final dynamic firestorePlace =
            scheduleData['place'];

            if ((lat == null || lng == null) &&
                firestorePlace is Map) {
              lat ??=
                  (firestorePlace['lat'] as num?)?.toDouble() ??
                      (firestorePlace['latitude'] as num?)?.toDouble() ??
                      (firestorePlace['gps_lat'] as num?)?.toDouble();

              lng ??=
                  (firestorePlace['lng'] as num?)?.toDouble() ??
                      (firestorePlace['longitude'] as num?)?.toDouble() ??
                      (firestorePlace['gps_lng'] as num?)?.toDouble();
            }
          }
        } catch (e) {
          debugPrint('일정 장소 좌표 조회 오류: $e');
        }
      }

      if (lat == null ||
          lng == null ||
          !lat.isFinite ||
          !lng.isFinite ||
          (lat == 0.0 && lng == 0.0)) {
        debugPrint('❌ 일정 장소 좌표 없음: docId=$docId');
        continue;
      }

      final bool isForceMode =
          data['force'] == true ||
              data['is_force_mode'] == true ||
              data['forceMode'] == true;

      String dateStr =
          data['date_str']?.toString() ??
              data['dateStr']?.toString() ??
              '';

      DateTime? dbStartDateTime;
      DateTime? dbEndDateTime;

      final dynamic rawStartDate =
          data['start_datetime'] ??
              data['startDateTime'];

      final dynamic rawEndDate =
          data['end_datetime'] ??
              data['endDateTime'];

      if (rawStartDate is Timestamp) {
        dbStartDateTime = rawStartDate.toDate();
      } else if (rawStartDate is DateTime) {
        dbStartDateTime = rawStartDate;
      }

      if (rawEndDate is Timestamp) {
        dbEndDateTime = rawEndDate.toDate();
      } else if (rawEndDate is DateTime) {
        dbEndDateTime = rawEndDate;
      }

      if (dateStr.isEmpty && dbStartDateTime != null) {
        dateStr =
            DateFormat('yyyy-MM-dd').format(dbStartDateTime);
      }

      if (dateStr.isNotEmpty &&
          dateStr != todayStr) {
        continue;
      }

      DateTime? startDT = dbStartDateTime;
      DateTime? endDT = dbEndDateTime;

      if (startDT == null) {
        final String startTimeStr =
            data['start_time']?.toString() ??
                data['startTime']?.toString() ??
                data['starttime']?.toString() ??
                '';

        if (startTimeStr.isEmpty) continue;

        try {
          startDT = DateTime.parse(
            '$todayStr ${_normalizeTime(startTimeStr)}',
          );
        } catch (_) {
          continue;
        }
      }

      if (endDT == null) {
        final String endTimeStr =
            data['end_time']?.toString() ??
                data['endTime']?.toString() ??
                data['endtime']?.toString() ??
                '';

        if (endTimeStr.isNotEmpty) {
          try {
            endDT = DateTime.parse(
              '$todayStr ${_normalizeTime(endTimeStr)}',
            );
          } catch (_) {}
        }
      }

      final diffSec =
          now.difference(startDT).inSeconds;

      if (diffSec < -5) continue;

      if (endDT != null && !endDT.isAfter(now)) {
        _triggeredSchedules.add(docId);
        continue;
      }

      int duration = 0;

      if (endDT != null) {
        duration =
            endDT.difference(startDT).inMinutes;
      }

      if (duration <= 0) {
        duration = _parseDurationMinutes(
          data['duration_minutes'] ??
              data['durationMinutes'] ??
              data['target_minutes'] ??
              data['targetMinutes'] ??
              data['duration'],
        );
      }

      if (duration <= 0) continue;

      int remainingSeconds;

      if (endDT != null) {
        remainingSeconds =
            endDT.difference(now).inSeconds;
      } else {
        remainingSeconds = duration * 60;
      }

      if (remainingSeconds <= 0) {
        _triggeredSchedules.add(docId);
        continue;
      }

      final String title =
          data['title']?.toString() ??
              data['subject']?.toString() ??
              '집중 세션';

      final String placeName =
          data['place_name']?.toString() ??
              data['placeName']?.toString() ??
              (data['place'] is String
                  ? data['place'].toString()
                  : '') ??
              '';

      _triggeredSchedules.add(docId);

      setState(() {
        _isNavigating = true;
        _isTimerOpen = true;
      });

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TimerPage(
            sessionId: docId,
            initialLat: lat,
            initialLng: lng,
            durationMinutes:
            (remainingSeconds ~/ 60)
                .clamp(1, 999999),
            durationMinutesFromSchedule: duration,
            startTime: startDT,
            endTime: endDT,
            title: title,
            placeName: placeName,
            forceMode: isForceMode,
            autoStarted: true,
          ),
        ),
      );

      if (!mounted) return;

      setState(() {
        _isTimerOpen = false;
        _isNavigating = false;
      });

      break;
    }
  }

  String _normalizeTime(String input) {
    // "9:5" → "09:05"
    final parts = input.split(':');
    if (parts.length != 2) return input;

    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;

    final hh = hour.toString().padLeft(2, '0');
    final mm = minute.toString().padLeft(2, '0');

    return '$hh:$mm';
  }

  int _parseDurationMinutes(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }


  void _startStudyTimer() {
    if (_isSessionFinished ||
        _isTimerRunning ||
        _isWaitingForArrival ||
        !_isCalibrated ||
        _isSnoozing ||
        _isPausedByAction) {
      return;
    }

    final int totalSeconds =
        _targetMinutes * 60;

    if (totalSeconds <= 0) {
      return;
    }

    _mainTimer?.cancel();

    _isTimerRunning = true;

    if (_sessionStartTime == null) {
      _sessionStartTime = DateTime.now();
    }

    if (mounted) {
      setState(() {
        _isTimerRunning = true;
      });
    }

    _showTimerNotification();

    _mainTimer = Timer.periodic(
      const Duration(seconds: 1),
          (timer) async {
        if (!mounted) {
          timer.cancel();
          _isTimerRunning = false;
          return;
        }

        if (_isSessionFinished ||
            _isWaitingForArrival ||
            !_isCalibrated ||
            _isSnoozing ||
            _isPausedByAction) {
          timer.cancel();
          _isTimerRunning = false;

          await _cancelTimerNotification();

          return;
        }

        if (_remainingSeconds <= 0) {
          timer.cancel();
          _mainTimer = null;
          _isTimerRunning = false;

          await _cancelTimerNotification();

          if (!_isSessionFinished) {
            await _showSuccessDialog();
          }

          return;
        }

        setState(() {
          _remainingSeconds--;
          _elapsedSeconds++;

          _timeLeft =
              _formatTime(_remainingSeconds);

          _progress =
              (_remainingSeconds / totalSeconds)
                  .clamp(0.0, 1.0);
        });

        await _showTimerNotification();
      },
    );
  }

  void _startAlarm() {
    if (_isSessionFinished ||
        _isPausedByAction) {
      return;
    }

    _isAlarmRunning = true;

    if (!_isAlarmPlaying) {
      _isAlarmPlaying = true;

      try {
        FlutterRingtonePlayer().playAlarm(
          asAlarm: true,
          looping: false,
          volume: 1.0,
        );
      } catch (e) {
        debugPrint(
          '알람 재생 오류: $e',
        );
      }
    }

    _alarmLoopTimer ??= Timer.periodic(
      const Duration(seconds: 30),
          (timer) {
        if (_isSessionFinished ||
            !_isAlarmRunning ||
            !_isAlarmPlaying ||
            _isPausedByAction) {
          timer.cancel();
          _alarmLoopTimer = null;
          return;
        }

        try {
          FlutterRingtonePlayer().playAlarm(
            asAlarm: true,
            looping: false,
            volume: 1.0,
          );
        } catch (e) {
          debugPrint(
            '반복 알람 재생 오류: $e',
          );
        }
      },
    );

    if (mounted) {
      setState(() {
        _isAlarmRunning = true;
        _isAlarmPlaying = true;
      });
    }
  }


  void _showPointActionDialog() {
    if (_isDepartureDialogShowing ||
        _isSessionFinished ||
        _isSnoozing ||
        !mounted) {
      return;
    }

    _isDepartureDialogShowing = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: const Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.redAccent,
                  size: 28,
                ),
                SizedBox(width: 10),
                Text(
                  '위치 이탈 경고!',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: Text(
              _isWaitingForArrival
                  ? '지정된 공부 장소에 도착하지 않았습니다.\n'
                  '장소에 도착하면 자동으로 공부가 시작됩니다.'
                  : '최초 도착 기준 위치에서 100m 이상 벗어났습니다.\n'
                  '공부 장소로 돌아가거나 아래에서 선택해주세요.',
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
              ),
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: pointColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    if (_isSessionFinished) return;

                    final int points =
                    await _getCurrentPoints();

                    if (!mounted ||
                        _isSessionFinished) {
                      return;
                    }

                    if (points >= 50) {
                      await _updateUserPoints(-50);

                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                      }

                      _isDepartureDialogShowing = false;

                      _stopAlarm();

                      await _startMiniTimer();

                      return;
                    }

                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                    }

                    _isDepartureDialogShowing = false;

                    _isPausedByAction = true;
                    _stopAlarm();

                    final bool adSuccess =
                    await _watchRewardedAd();

                    if (!mounted) return;

                    _isPausedByAction = false;

                    if (!adSuccess) {
                      _showSnack(
                        '광고 시청에 실패했습니다.',
                      );

                      if (!_isSessionFinished &&
                          !_isDepartureDialogShowing) {
                        _startAlarm();
                        _showPointActionDialog();
                      }

                      return;
                    }

                    await _forceFailSession(
                      '포인트 부족으로 광고 시청 후 종료',
                      pointDeduction: 0,
                    );
                  },
                  child: const Text(
                    '10분 미루기 (-50P)',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(
                      color: Colors.redAccent,
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    if (_isSessionFinished) return;

                    final int points =
                    await _getCurrentPoints();

                    if (!mounted ||
                        _isSessionFinished) {
                      return;
                    }

                    if (points >= 200) {
                      await _updateUserPoints(-200);

                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                      }

                      _isDepartureDialogShowing = false;

                      _stopAlarm();

                      await _forceFailSession(
                        '위치 이탈 후 사용자 포기',
                        pointDeduction: -200,
                      );

                      return;
                    }

                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                    }

                    _isDepartureDialogShowing = false;

                    _isPausedByAction = true;
                    _stopAlarm();

                    final bool adSuccess =
                    await _watchRewardedAd();

                    if (!mounted) return;

                    _isPausedByAction = false;

                    if (!adSuccess) {
                      _showSnack(
                        '광고 시청에 실패했습니다.',
                      );

                      if (!_isSessionFinished &&
                          !_isDepartureDialogShowing) {
                        _startAlarm();
                        _showPointActionDialog();
                      }

                      return;
                    }

                    await _forceFailSession(
                      '포인트 부족으로 광고 시청 후 종료',
                      pointDeduction: 0,
                    );
                  },
                  child: const Text(
                    '포기하기 (-200P)',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ).then((_) {
      _isDepartureDialogShowing = false;
    });
  }


  Future<void> _startMiniTimer() async {
    _snoozeTimer?.cancel();

    _mainTimer?.cancel();
    _mainTimer = null;

    _isTimerRunning = false;

    await _cancelTimerNotification();

    _stopAlarm();

    _outOfRangeStartedAt = null;
    _outStartTime = null;
    _outOfRangeSeconds = 0;

    _isSnoozing = true;
    _snoozeRemainingSeconds = 600;

    if (mounted) {
      setState(() {
        _isSnoozing = true;
        _snoozeRemainingSeconds = 600;
        _isTimerRunning = false;
      });
    }

    _snoozeTimer = Timer.periodic(
      const Duration(seconds: 1),
          (timer) async {
        if (!mounted ||
            _isSessionFinished) {
          timer.cancel();
          _snoozeTimer = null;
          return;
        }

        if (_snoozeRemainingSeconds > 0) {
          setState(() {
            _snoozeRemainingSeconds--;
          });
          return;
        }

        timer.cancel();
        _snoozeTimer = null;

        if (_isSessionFinished) return;

        _isSnoozing = false;

        if (mounted) {
          setState(() {
            _isSnoozing = false;
            _snoozeRemainingSeconds = 0;
            _isTimerRunning = false;
          });
        }

        try {
          final Position position =
          await Geolocator.getCurrentPosition(
            desiredAccuracy:
            LocationAccuracy.bestForNavigation,
            timeLimit:
            const Duration(seconds: 10),
          );

          if (!mounted ||
              _isSessionFinished) {
            return;
          }

          _lastPosition = position;

          await _checkLocationLogic(position);
        } catch (e) {
          debugPrint(
            '미루기 종료 후 위치 확인 오류: $e',
          );

          _isTimerRunning = false;
        }
      },
    );
  }

  void _handleReturnToArea() {
    _stopAlarm();

    _outOfRangeStartedAt = null;
    _outStartTime = null;
    _outOfRangeSeconds = 0;

    _alarmLoopTimer?.cancel();
    _alarmLoopTimer = null;

    _alarmRepeatTimer?.cancel();
    _alarmRepeatTimer = null;

    if (_isDepartureDialogShowing ||
        _isLocationDialogShowing) {
      if (mounted &&
          Navigator.of(
            context,
            rootNavigator: true,
          ).canPop()) {
        Navigator.of(
          context,
          rootNavigator: true,
        ).pop();
      }
    }

    _isDepartureDialogShowing = false;
    _isLocationDialogShowing = false;

    _snoozeTimer?.cancel();
    _snoozeTimer = null;

    _snoozeRemainingSeconds = 0;
    _isSnoozing = false;
    _isPausedByAction = false;

    if (mounted) {
      setState(() {
        _isAlarmRunning = false;
        _isAlarmPlaying = false;
        _isWaitingForArrival = false;
        _isSnoozing = false;
        _isTimerRunning = false;
      });
    }

    if (_isCalibrated &&
        !_isSessionFinished) {
      _startStudyTimer();
    }
  }


  void _startAlarmAndDialog() {
    if (_isSessionFinished ||
        _isPausedByAction ||
        _isDepartureDialogShowing) {
      return;
    }

    if (_isWaitingForArrival ||
        (_isCalibrated &&
            _outOfRangeStartedAt != null)) {
      _mainTimer?.cancel();
      _mainTimer = null;
      _isTimerRunning = false;
    }

    _startAlarm();

    if (mounted &&
        !_isDepartureDialogShowing &&
        !_isSessionFinished) {
      _showPointActionDialog();
    }
  }


// 5. 보상형 광고 로직 (반환 타입 수정 완료)
  Future<bool> _watchRewardedAd() async {
    final completer = Completer<bool>();

    if (_rewardedAd == null) {
      RewardedAd.load(
        adUnitId: 'ca-app-pub-3940256099942544/5224354917',
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            _rewardedAd = ad;
            _showAdInternal(completer);
          },
          onAdFailedToLoad: (error) {
            completer.complete(false);
          },
        ),
      );
    } else {
      _showAdInternal(completer);
    }

    return completer.future;
  }// 기존 _stopAlarm 함수 전체 삭제 후 교체

  void _showAdInternal(Completer<bool> completer) {
    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedAd = null;
        _loadRewardedAd();
        if (!completer.isCompleted) completer.complete(false);
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        ad.dispose();
        _rewardedAd = null;
        _loadRewardedAd();
        if (!completer.isCompleted) completer.complete(false);
      },
    );

    _rewardedAd!.show(
      onUserEarnedReward: (ad, reward) {
        if (!completer.isCompleted) completer.complete(true);
      },
    );
  }

  void _stopAlarm() {
    _isAlarmRunning = false;
    _isAlarmPlaying = false;

    _alarmLoopTimer?.cancel();
    _alarmLoopTimer = null;

    _alarmRepeatTimer?.cancel();
    _alarmRepeatTimer = null;

    try {
      FlutterRingtonePlayer().stop();
    } catch (e) {
      debugPrint(
        '알람 중지 오류: $e',
      );
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _pauseStudyTimer() {
    _mainTimer?.cancel();
    _mainTimer = null;

    _isTimerRunning = false;

    _saveTimerState();
  }

  void _cancelSnooze() {
    _snoozeTimer?.cancel();
    _snoozeTimer = null;

    if (mounted) {
      setState(() {
        _isSnoozing = false;
        _snoozeRemainingSeconds = 0;
      });
    }

    if (_isSessionFinished) return;

    Geolocator.getCurrentPosition(
      desiredAccuracy:
      LocationAccuracy.bestForNavigation,
    ).then((position) {
      if (!mounted ||
          _isSessionFinished) {
        return;
      }

      _lastPosition = position;

      _checkLocationLogic(position);
    }).catchError((e) {
      debugPrint(
        '미루기 취소 후 위치 확인 오류: $e',
      );
    });
  }


  Timer? _alarmLoopTimer;

  void _showNeedPointDialog({
    required int requiredPoint,
    required Function onAction,
  }) {
    final bool isDarkMode =
        Theme.of(context).brightness == Brightness.dark;

    final Color dialogBackground =
    isDarkMode
        ? const Color(0xFF1E1E1E)
        : Colors.white;

    final Color titleColor =
    isDarkMode
        ? Colors.white
        : Colors.black87;

    final Color contentColor =
    isDarkMode
        ? Colors.white70
        : Colors.grey.shade700;

    final Color cancelColor =
    isDarkMode
        ? Colors.white70
        : Colors.grey.shade600;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: dialogBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.0),
        ),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),

        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.monetization_on_rounded,
                color: Colors.amber,
                size: 26,
              ),
            ),

            const SizedBox(width: 12),

            Text(
              "포인트 부족",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: titleColor,
              ),
            ),
          ],
        ),

        content: Text(
          "해당 기능을 수행하기 위한 포인트가 부족합니다.\n"
              "광고를 시청하고 포인트를 충전하시겠습니까?",
          style: TextStyle(
            fontSize: 14,
            color: contentColor,
            height: 1.4,
          ),
        ),

        actions: [
          Row(
            children: [
              Expanded(
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: cancelColor,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    "취소",
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showRewardedAdAndReward(onAction);
                  },
                  child: const Text(
                    "광고 시청",
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  void _showRewardedAdAndReward(Function onAction) {
    if (_rewardedAd != null) {
      _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          _loadRewardedAd();
        },
        onAdFailedToShowFullScreenContent: (ad, err) {
          ad.dispose();
          _loadRewardedAd();
        },
      );
      _rewardedAd!.show(onUserEarnedReward: (ad, reward) async {
        await _updateUserPoints(200); // 광고 시청 보상 포인트 지급 (예시: 200p)
        onAction();
      });
    } else {
      _loadRewardedAd();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("광고가 준비되지 않았습니다. 잠시 후 다시 시도해주세요.")),
      );
    }
  }
  void _showRewardedAdAndExecute(Function onSuccess) {
    setState(() {
      _isPausedByAction = true;
    });
    _stopAlarm();

    _watchRewardedAd().then((success) {
      setState(() {
        _isPausedByAction = false;
      });
      if (success) {
        onSuccess();
      } else {
        _showSnack("광고 시청에 실패했거나 취소되었습니다.");
      }
    });
  }


// [통합본] 현재 포인트 조회
  Future<int> _getCurrentPoints() async {
    if (user == null) return 0;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .collection('user_profile')
          .doc('current')
          .get();

      if (doc.exists) {
        final data = doc.data();

        return ((data?['point'] ?? 0) as num)
            .toInt();
      }
    } catch (e) {
      debugPrint(
        "포인트 조회 오류: $e",
      );
    }

    return 0;
  }



  void _forceCleanupAll() {
    _mainTimer?.cancel();
    _mainTimer = null;

    _snoozeTimer?.cancel();
    _snoozeTimer = null;

    _locationTimer?.cancel();
    _locationTimer = null;

    _departureTimer?.cancel();
    _departureTimer = null;

    _alarmRepeatTimer?.cancel();
    _alarmRepeatTimer = null;

    _alarmLoopTimer?.cancel();
    _alarmLoopTimer = null;

    _positionStream?.cancel();
    _positionStream = null;

    _stopAlarm();

    _cancelTimerNotification();

    _isTimerRunning = false;
    _isSnoozing = false;
    _isDepartureDialogShowing = false;
    _isLocationDialogShowing = false;
  }


  String _formatTime(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  int _calculatePoints(int minutes) {
    int hours = minutes ~/ 60; // 정수 나눗셈을 통해 시간 단위만 산출 (예: 119분 / 60 = 1시간)
    return hours * 100;
  }


  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }



  Future<void> _showSuccessDialog() async {
    if (_isSessionFinished) return;
    _isSessionFinished = true;

    _mainTimer?.cancel();
    _snoozeTimer?.cancel();
    _stopAlarm();
    await _cancelTimerNotification();

    // 1. DB에 성공 상태로 타이머 결과 기록
    await _saveSessionResult(false, '');

    // 2. 기본 보상 포인트 지급 (예: 완료 기본 포인트 100P)
    await _updateUserPoints(100);

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text('🎉 목표 달성!'),
        content: const Text('설정한 공부 시간을 모두 완료했습니다.\n포인트가 적립되었습니다.'),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: pointColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context, true);
            },
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }


  final uid = FirebaseAuth.instance.currentUser?.uid;

  Future<void> _markForceSessionFailed(
      String reason,
      String sessionId,
      ) async {
    if (_isSessionFinished) return;

    if (sessionId.isEmpty) return;

    final uid =
        FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) return;

    final sessionRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('study_sessions')
        .doc(sessionId);

    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('user_profile')
        .doc('current');

    try {
      await FirebaseFirestore.instance.runTransaction(
            (transaction) async {
          final sessionSnapshot =
          await transaction.get(sessionRef);

          if (!sessionSnapshot.exists) {
            return;
          }

          final data =
          sessionSnapshot.data() as Map<String, dynamic>;

          // 이미 성공/실패 처리된 세션이면
          // 절대로 다시 100P 차감하지 않음
          if (data['is_failed'] == true ||
              data['is_success'] == true) {
            return;
          }

          final userSnapshot =
          await transaction.get(userRef);

          final userData =
              userSnapshot.data()
              as Map<String, dynamic>? ??
                  {};

          final currentPoint =
              (userData['point'] as num?)
                  ?.toInt() ??
                  0;

          final newPoint =
          (currentPoint - 100)
              .clamp(0, 999999999);

          transaction.set(
            sessionRef,
            {
              'is_success': false,
              'is_failed': true,
              'stop_time':
              FieldValue.serverTimestamp(),
              'give_up_reason': reason,
              'failed_point': 100,
              'updated_at':
              FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );

          transaction.set(
            userRef,
            {
              'point': newPoint,
              'updated_at':
              FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        },
      );

      _isSessionFinished = true;

      _mainTimer?.cancel();
      _mainTimer = null;

      _snoozeTimer?.cancel();
      _snoozeTimer = null;

      _stopAlarm();

      await _cancelTimerNotification();

      debugPrint(
        '===== 강제 실패 처리 완료 =====',
      );
      debugPrint(
        '사유: $reason',
      );
      debugPrint(
        '차감 포인트: 100P',
      );
    } catch (e) {
      debugPrint(
        '강제 세션 실패 처리 오류: $e',
      );
    }
  }

  void _finishFinal() {
    _forceCleanupAll();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }


  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: 'ca-app-pub-1806802501961110/2044317820',
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) => setState(() => _isBannerAdReady = true),
        onAdFailedToLoad: (ad, err) {
          ad.dispose();
          _isBannerAdReady = false;
        },
      ),
    )..load();
  }

  Future<void> _loadRewardedAd() async {
    RewardedAd.load(
      adUnitId: 'ca-app-pub-3940256099942544/5224354917',
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => _rewardedAd = ad,
        onAdFailedToLoad: (_) => _rewardedAd = null,
      ),
    );
  }

  @override
Widget build(BuildContext context) {
final bool isDarkMode =
Theme.of(context).brightness == Brightness.dark;

final Color backgroundColor =
isDarkMode
? const Color(0xFF121212)
: bgColor;

final Color cardColor =
isDarkMode
? const Color(0xFF1E1E1E)
: Colors.white;

final Color primaryTextColor =
isDarkMode
? Colors.white
: Colors.black87;

final Color secondaryTextColor =
isDarkMode
? Colors.white70
: Colors.grey.shade500;

final Color borderColor =
isDarkMode
? Colors.white12
: Colors.grey.shade100;

final Color progressBackgroundColor =
isDarkMode
? Colors.white12
: Colors.grey.shade100;

final Color shadowColor =
isDarkMode
? Colors.black.withOpacity(0.25)
: Colors.black.withOpacity(0.03);

final Color cancelButtonBackgroundColor =
isDarkMode
? const Color(0xFF2A2020)
: Colors.white;

return PopScope(
canPop: false,
onPopInvokedWithResult: (
bool didPop,
dynamic result,
) {
debugPrint(
'집중 세션 중 뒤로가기 차단',
);
},
child: Scaffold(
backgroundColor: backgroundColor,
resizeToAvoidBottomInset: false,
appBar: AppBar(
automaticallyImplyLeading: false,

// ★ AppBar 타이틀: '집중 세션' 고정 문구 대신 일정 제목 변수 적용
title: Text(
_activeTitle,
style: TextStyle(
fontSize: 18,
fontWeight: FontWeight.bold,
color: primaryTextColor,
),
),

backgroundColor: cardColor,
foregroundColor: primaryTextColor,
elevation: 0,
centerTitle: true,

bottom: PreferredSize(
preferredSize: const Size.fromHeight(1),

child: Container(
color: borderColor,
height: 1,
),
),
),

body: _isInitializing
? Center(
child: CircularProgressIndicator(
valueColor:
AlwaysStoppedAnimation<Color>(
pointColor,
),
),
)
: SafeArea(
child: Padding(
padding: const EdgeInsets.symmetric(
horizontal: 24.0,
vertical: 24.0,
),

child: Column(
children: [
Container(
width: double.infinity,

padding: const EdgeInsets.all(16),

decoration: BoxDecoration(
color: cardColor,
borderRadius:
BorderRadius.circular(20),

border: Border.all(
color: borderColor,
),

boxShadow: [
BoxShadow(
color: shadowColor,
blurRadius: 12,
offset: const Offset(0, 4),
),
],
),

child: Row(
children: [
Container(
padding:
const EdgeInsets.all(10),

decoration: BoxDecoration(
color: _isSnoozing
? Colors.orange
.withOpacity(0.12)
: (_isWaitingForArrival
? Colors.redAccent
.withOpacity(0.12)
: pointColor
.withOpacity(0.12)),

shape: BoxShape.circle,
),

child: Icon(
_isSnoozing
? Icons.timer_off_rounded
: (_isWaitingForArrival
? Icons.location_pin
: Icons
.local_fire_department_rounded),

color: _isSnoozing
? Colors.orange
: (_isWaitingForArrival
? Colors.redAccent
: pointColor),

size: 22,
),
),

const SizedBox(width: 16),

Expanded(
child: Column(
crossAxisAlignment:
CrossAxisAlignment.start,

children: [
Text(
_isSnoozing
? "10분 미루기 작동 중"
: (_isWaitingForArrival
? "공부 장소 이동 대기 중"
: (widget.placeName ??
"집중된 장소")),

style: TextStyle(
fontSize: 15,
fontWeight:
FontWeight.bold,
color: primaryTextColor,
),
),

const SizedBox(height: 4),

Text(
"현재 장소와의 거리: "
"${_movementDistance.toStringAsFixed(1)}m",

style: TextStyle(
fontSize: 13,
color: secondaryTextColor,
fontWeight:
FontWeight.w500,
),
),
],
),
),
],
),
),

const Spacer(),

Center(
child: Stack(
alignment: Alignment.center,

children: [
SizedBox(
width: 280,
height: 280,

child: CircularProgressIndicator(
value: _isSnoozing
? (_snoozeRemainingSeconds /
600)
: _progress,

strokeWidth: 14,

backgroundColor:
progressBackgroundColor,

valueColor:
AlwaysStoppedAnimation<Color>(
_isSnoozing
? Colors.orange
: pointColor,
),

strokeCap: StrokeCap.round,
),
),

Column(
mainAxisSize: MainAxisSize.min,

children: [
if (_isSnoozing) ...[
Text(
"미루기 남은 시간",

style: TextStyle(
fontSize: 14,
fontWeight:
FontWeight.w600,
color:
isDarkMode
? Colors.orange.shade300
: Colors.orange.shade700,
),
),

const SizedBox(height: 6),
],

Text(
_isSnoozing
? _formatTime(
_snoozeRemainingSeconds,
)
: _timeLeft,

style: TextStyle(
fontSize: 46,
fontWeight:
FontWeight.w800,
color: primaryTextColor,
letterSpacing: -1.5,
),
),
],
),
],
),
),

const Spacer(),

Column(
crossAxisAlignment:
CrossAxisAlignment.stretch,

children: [
if (_isSnoozing) ...[
ElevatedButton(
style: ElevatedButton.styleFrom(
backgroundColor:
Colors.orange,

foregroundColor:
Colors.white,

elevation: 0,

padding:
const EdgeInsets.symmetric(
vertical: 16,
),

shape:
RoundedRectangleBorder(
borderRadius:
BorderRadius.circular(16),
),
),

onPressed: _cancelSnooze,

child: const Text(
"복귀함",

style: TextStyle(
fontSize: 16,
fontWeight:
FontWeight.bold,
),
),
),

const SizedBox(height: 12),
],

ElevatedButton(
style: ElevatedButton.styleFrom(
backgroundColor:
cancelButtonBackgroundColor,

foregroundColor:
Colors.redAccent,

elevation: 0,

side: BorderSide(
color: Colors.redAccent
.withOpacity(
isDarkMode ? 0.55 : 0.3,
),

width: 1.5,
),

padding:
const EdgeInsets.symmetric(
vertical: 16,
),

shape:
RoundedRectangleBorder(
borderRadius:
BorderRadius.circular(16),
),
),

onPressed:
_onCancelBeforeStart,

child: const Text(
"포기 하기",

style: TextStyle(
fontSize: 16,
fontWeight:
FontWeight.bold,
),
),
),
],
),
],
),
),
),
),
);
}}