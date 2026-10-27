import 'dart:async';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class CameraTimerPage extends StatefulWidget {
  final String? sessionId;

  // TimerPage와 동일하게 전달받음
  final double? initialLat;
  final double? initialLng;
  final int durationMinutes;
  final DateTime? startTime;
  final DateTime? endTime;
  final String title;
  final bool forceMode;

  const CameraTimerPage({
    super.key,
    this.sessionId,
    this.initialLat,
    this.initialLng,
    required this.durationMinutes,
    this.startTime,
    this.endTime,
    this.title = '공부',
    this.forceMode = false,
  });


  @override
  State<CameraTimerPage> createState() => _CameraTimerPageState();
}

class _CameraTimerPageState extends State<CameraTimerPage> with WidgetsBindingObserver {
  CameraController? _cameraController;
  PoseDetector? _poseDetector;
  List<CameraDescription> _cameras = [];

  DateTime _lastMovementTime = DateTime.now(); // 추가: 오류 해결을 위한 변수
  late int _remainingSeconds;
  final double _allowedRadius = 100.0; // 100m 이탈 시 경고

  double? _baselineLat;
  double? _baselineLng;

  bool _locationVerified = false;
  bool _isOutOfRange = false;
  bool _isAlarmPlaying = false;
  bool _isDepartureDialogShowing = false;
  bool _isDialogShowing = false;

  Timer? _checkTimer; // 추가: 활동 감지 타이머
  Timer? _locationCheckTimer;
  Timer? _inactiveTimer; // 5분 카운트다운용
  Timer? _inactivityCheckTimer;
  Timer? _countDownTimer;
  Timer? _locationOutTimer; // 10분 카운트다운용

  int _cameraIndex = 0;
  int _outOfRangeSeconds = 0;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
    );

    _inactivityCheckTimer = Timer.periodic(
      const Duration(minutes: 1),
          (_) => _checkInactivity(),
    );

    // TimerPage와 동일하게 전달받은 durationMinutes 사용
    _remainingSeconds = widget.durationMinutes * 60;

    debugPrint('======================================');
    debugPrint('🚀 CameraTimerPage 초기화');
    debugPrint('sessionId    : ${widget.sessionId}');
    debugPrint('title        : ${widget.title}');
    debugPrint('duration     : ${widget.durationMinutes}');
    debugPrint('startTime    : ${widget.startTime}');
    debugPrint('endTime      : ${widget.endTime}');
    debugPrint('initialLat   : ${widget.initialLat}');
    debugPrint('initialLng   : ${widget.initialLng}');
    debugPrint('forceMode    : ${widget.forceMode}');
    debugPrint('======================================');

    _initializeCamera();

    if (!widget.forceMode) {
      _locationVerified = true;
      _startCountDown();
    }

    _checkLocationLogic();

    _locationCheckTimer = Timer.periodic(
      const Duration(seconds: 5),
          (_) => _checkLocationLogic(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _inactiveTimer?.cancel();
    _inactivityCheckTimer?.cancel();
    _checkTimer?.cancel();
    _locationCheckTimer?.cancel();
    _locationOutTimer?.cancel();
    _countDownTimer?.cancel();

    _stopAlarm();

    _cameraController?.dispose();
    _poseDetector?.close();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
    );

    super.dispose();
  }


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (!widget.forceMode) return;

    // 강제모드에서 백그라운드로 나가면
    // 최대한 즉시 STAY 앱으로 복귀시킨다.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _returnToStayApp();
    }

    // 다시 STAY 앱으로 돌아온 경우 카메라 상태 확인
    if (state == AppLifecycleState.resumed) {
      _restoreForceMode();
    }
  }

  @override
  Future<bool> didPopRoute() async {
    if (widget.forceMode) {
      // 강제모드에서는 뒤로가기를 절대 허용하지 않음
      return true;
    }

    return false;
  }


  Future<void> _returnToStayApp() async {
    if (!widget.forceMode || !mounted) return;

    try {
      // Android에서 현재 앱을 다시 전면으로 가져오기 위한 호출
      const MethodChannel channel =
      MethodChannel('stay/force_mode');

      await channel.invokeMethod('bringToFront');
    } catch (e) {
      debugPrint('STAY 앱 전면 복귀 오류: $e');
    }
  }


  Future<void> _restoreForceMode() async {
    if (!widget.forceMode || !mounted) return;

    try {
      // 화면이 다시 활성화되었을 때 immersive 유지
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
      );

      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);

      // 카메라가 중단된 경우 다시 초기화
      if (_cameraController == null ||
          !_cameraController!.value.isInitialized) {
        await _initializeCamera();
      }
    } catch (e) {
      debugPrint('강제모드 복구 오류: $e');
    }
  }

  Future<void> _checkLocationLogic() async {
    try {
      if (widget.initialLat == null || widget.initialLng == null) {
        debugPrint('기준 위치 정보 없음: 위치 확인 생략');

        if (!_locationVerified) {
          _locationVerified = true;

          if (_countDownTimer == null || !_countDownTimer!.isActive) {
            _startCountDown();
          }
        }

        return;
      }

      final Position currentPosition =
      await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // ============================================================
      // 1. 최초 지정 장소 도착 확인
      // ============================================================
      if (!_locationVerified) {
        final double distanceToTarget = Geolocator.distanceBetween(
          currentPosition.latitude,
          currentPosition.longitude,
          widget.initialLat!,
          widget.initialLng!,
        );

        debugPrint(
          '타이머 시작 전 지정 장소까지 거리: '
              '${distanceToTarget.toStringAsFixed(1)}m',
        );

        if (distanceToTarget <= _allowedRadius) {
          _locationVerified = true;

          _baselineLat = currentPosition.latitude;
          _baselineLng = currentPosition.longitude;

          _isOutOfRange = false;
          _outOfRangeSeconds = 0;

          _stopAlarm();

          // ★ 중요:
          // CameraTimerPage 자체를 pop하지 않음.
          // 실제 위치 이탈 Dialog가 열려 있을 때만 Dialog를 닫음.
          if (mounted && _isDepartureDialogShowing) {
            Navigator.of(context).pop();
          }

          if (_countDownTimer == null ||
              !_countDownTimer!.isActive) {
            _startCountDown();
          }

          debugPrint(
            '✅ 장소 도착 확인 → 기준 GPS 저장: '
                '$_baselineLat, $_baselineLng',
          );

          return;
        }

        _countDownTimer?.cancel();

        if (!_isDepartureDialogShowing) {
          await _startAlarmAndDialog();
        }

        return;
      }

      // ============================================================
      // 2. 기준 GPS가 없으면 현재 위치를 기준점으로 저장
      // ============================================================
      if (_baselineLat == null || _baselineLng == null) {
        _baselineLat = currentPosition.latitude;
        _baselineLng = currentPosition.longitude;

        debugPrint('기준 GPS가 없어 현재 GPS를 기준점으로 저장');

        return;
      }

      final double distanceFromBaseline = Geolocator.distanceBetween(
        currentPosition.latitude,
        currentPosition.longitude,
        _baselineLat!,
        _baselineLng!,
      );

      debugPrint(
        '기준 GPS로부터 거리: '
            '${distanceFromBaseline.toStringAsFixed(1)}m',
      );

      // ============================================================
      // 3. 기준 위치로 복귀
      // ============================================================
      if (distanceFromBaseline <= _allowedRadius) {
        _outOfRangeSeconds = 0;

        if (_isOutOfRange ||
            _isDepartureDialogShowing ||
            _isAlarmPlaying) {
          debugPrint('✅ 기준 위치로 복귀 → 알람/팝업 종료');

          _isOutOfRange = false;

          _stopAlarm();

          // ★ CameraTimerPage를 pop하지 않음.
          // 실제 경고 Dialog가 열려 있을 때만 닫음.
          if (mounted && _isDepartureDialogShowing) {
            Navigator.of(context).pop();
          }
        }

        return;
      }

      // ============================================================
      // 4. 100m 이상 이탈
      // ============================================================
      _outOfRangeSeconds += 5;

      debugPrint(
        '100m 이상 이탈 지속시간: $_outOfRangeSeconds초',
      );

      if (_outOfRangeSeconds >= 40) {
        if (!_isOutOfRange) {
          _isOutOfRange = true;

          debugPrint(
            '🚨 100m 이상 40초 지속 → 실제 위치 이탈 판정',
          );
        }

        if (!_isDepartureDialogShowing) {
          await _startAlarmAndDialog();
        }
      }
    } catch (e) {
      debugPrint('위치 확인 오류: $e');
    }
  }



  // [메서드 수정: 위치 이탈 시 10분 경고창]
  Future<void> _startAlarmAndDialog() async {
    if (_isDepartureDialogShowing) return;
    if (!mounted) return;

    setState(() {
      _isDepartureDialogShowing = true;
    });

    _isAlarmPlaying = true;

    FlutterRingtonePlayer().playAlarm(
      looping: true,
      asAlarm: true,
    );

    _locationOutTimer?.cancel();

    int remainingSeconds = 600;

    final TextEditingController reasonController =
    TextEditingController();

    _locationOutTimer = Timer.periodic(
      const Duration(seconds: 1),
          (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        if (!_isDepartureDialogShowing || !_isOutOfRange) {
          timer.cancel();
          return;
        }

        if (remainingSeconds > 0) {
          remainingSeconds--;
        } else {
          timer.cancel();
          _handleLocationFailure();
        }
      },
    );

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    try {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) {
          final bool isDark =
              Theme.of(context).brightness == Brightness.dark;

          final Color dialogBackground =
          isDark ? const Color(0xFF1E1E1E) : Colors.white;

          final Color primaryText =
          isDark ? Colors.white : const Color(0xFF1F2937);

          final Color secondaryText =
          isDark ? Colors.white70 : const Color(0xFF6B7280);

          final Color sectionText =
          isDark ? Colors.white : const Color(0xFF374151);

          final Color inputBackground =
          isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF7F8FA);

          final Color inputBorder =
          isDark ? Colors.white24 : const Color(0xFFE5E7EB);

          final Color countdownBackground =
          isDark ? const Color(0xFF3A2020) : const Color(0xFFFFF5F5);

          final Color hintColor =
          isDark ? Colors.white54 : const Color(0xFF9CA3AF);

          return PopScope(
            canPop: false,
            child: StatefulBuilder(
              builder: (context, setDialogState) {
                Future.delayed(
                  const Duration(seconds: 1),
                      () {
                    if (mounted && _isDepartureDialogShowing) {
                      setDialogState(() {});
                    }
                  },
                );

                return Dialog(
                  backgroundColor: dialogBackground,
                  insetPadding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 24,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      24,
                      26,
                      24,
                      20,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.location_off_rounded,
                            color: Colors.redAccent,
                            size: 32,
                          ),
                        ),

                        const SizedBox(height: 16),

                        Text(
                          '장소 이탈 경고',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: primaryText,
                          ),
                        ),

                        const SizedBox(height: 10),

                        Text(
                          '지정된 장소에서 벗어났습니다.\n'
                              '기준 위치로 돌아와 주세요.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: secondaryText,
                            height: 1.5,
                          ),
                        ),

                        const SizedBox(height: 20),

                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: countdownBackground,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              Text(
                                '자동 차감까지',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: hintColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),

                              const SizedBox(height: 4),

                              Text(
                                '${remainingSeconds ~/ 60}분 '
                                    '${(remainingSeconds % 60).toString().padLeft(2, '0')}초',
                                style: const TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.redAccent,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '중도 해제 사유',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: sectionText,
                            ),
                          ),
                        ),

                        const SizedBox(height: 9),

                        TextField(
                          controller: reasonController,
                          autofocus: true,
                          maxLines: 4,
                          minLines: 3,
                          style: TextStyle(
                            color: primaryText,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            hintText: '해제 사유를 입력해주세요 (선택)',
                            hintStyle: TextStyle(
                              color: hintColor,
                              fontSize: 14,
                            ),
                            filled: true,
                            fillColor: inputBackground,
                            contentPadding:
                            const EdgeInsets.all(16),
                            border: OutlineInputBorder(
                              borderRadius:
                              BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius:
                              BorderRadius.circular(16),
                              borderSide: BorderSide(
                                color: inputBorder,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius:
                              BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: Colors.redAccent,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: () async {
                              FocusScope.of(context).unfocus();

                              _locationOutTimer?.cancel();
                              _stopAlarm();

                              await _recordSessionFailure(
                                isCancelled: true,
                                reason: reasonController.text
                                    .trim()
                                    .isEmpty
                                    ? '위치 이탈 중도 해제'
                                    : reasonController.text.trim(),
                              );

                              if (mounted) {
                                Navigator.of(context).popUntil(
                                      (route) => route.isFirst,
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                BorderRadius.circular(15),
                              ),
                            ),
                            child: const Text(
                              '중도 해제하고 종료하기',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      );
    } finally {
      reasonController.dispose();

      if (mounted && widget.forceMode) {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);

        await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.immersiveSticky,
        );
      }
    }
  }
  void _stopAlarm() {
    _isAlarmPlaying = false;
    _isDepartureDialogShowing = false;

    _locationOutTimer?.cancel();
    _locationOutTimer = null;

    FlutterRingtonePlayer().stop();
  }

  Future<void> _handleLocationFailure() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null || widget.sessionId == null) return;

    final firestore = FirebaseFirestore.instance;

    final sessionId = widget.sessionId!;

    final batch = firestore.batch();

    // ─────────────────────────────────────
    // 1. 사용자 프로필
    // users/{uid}/user_profile/current
    // ─────────────────────────────────────
    final userRef = firestore
        .collection('users')
        .doc(user.uid)
        .collection('user_profile')
        .doc('current');

    // ─────────────────────────────────────
    // 2. 실제 공부 세션
    // users/{uid}/study_sessions/{sessionId}
    // ─────────────────────────────────────
    final sessionRef = firestore
        .collection('users')
        .doc(user.uid)
        .collection('study_sessions')
        .doc(sessionId);

    // ─────────────────────────────────────
    // 3. 포인트 차감
    // DB 설계: point
    // ─────────────────────────────────────
    batch.update(userRef, {
      'point': FieldValue.increment(-500),
      'updated_at': FieldValue.serverTimestamp(),
    });

    // ─────────────────────────────────────
    // 4. 공부 세션 실패 처리
    // ─────────────────────────────────────
    batch.update(sessionRef, {
      'is_success': false,
      'is_failed': true,

      'give_up_reason': '위치 이탈',

      'stop_time': FieldValue.serverTimestamp(),

      'created_at': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    // ─────────────────────────────────────
    // 5. 타이머 종료
    // ─────────────────────────────────────
    if (mounted) {
      _stopAlarm();

      Navigator.of(context).popUntil(
            (route) => route.isFirst,
      );
    }
  }
  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;

    _cameraIndex =
        (_cameraIndex + 1) % _cameras.length;

    try {
      await _cameraController?.dispose();
      _cameraController = null;

      if (mounted) {
        setState(() {});
      }

      await _initializeCamera();
    } catch (e) {
      debugPrint('카메라 전환 오류: $e');
    }
  }



  void _startCountDown() {
    _countDownTimer?.cancel();

    _countDownTimer = Timer.periodic(
      const Duration(seconds: 1),
          (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        if (_remainingSeconds <= 0) {
          timer.cancel();
          _countDownTimer = null;
          return;
        }

        setState(() {
          _remainingSeconds--;
        });
      },
    );
  }

  String get _formattedTime {
    final hours = _remainingSeconds ~/ 3600;
    final minutes = (_remainingSeconds % 3600) ~/ 60;
    final seconds = _remainingSeconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }


  // 통계 및 세션 기록 업데이트 (공통 로직)
  Future<void> _recordSessionFailure({
    required bool isCancelled,
    required String reason,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || widget.sessionId == null) return;

    final firestore = FirebaseFirestore.instance;

    final batch = firestore.batch();

    // 1. 실제 공부 세션
    // users/{uid}/study_sessions/{sessionId}
    final sessionRef = firestore
        .collection('users')
        .doc(user.uid)
        .collection('study_sessions')
        .doc(widget.sessionId);

    batch.update(sessionRef, {
      'is_success': false,
      'is_failed': true,
      'stop_time': FieldValue.serverTimestamp(),
      'give_up_reason': reason,
    });

    // 2. 포인트 500P 차감
    // users/{uid}/user_profile/current
    final userRef = firestore
        .collection('users')
        .doc(user.uid)
        .collection('user_profile')
        .doc('current');

    batch.update(userRef, {
      'point': FieldValue.increment(-500),
    });

    await batch.commit();
  }




// 1, 2, 4번에 대한 수정본 (CameraTimerPage 전체)
  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();

      if (_cameras.isEmpty || !mounted) return;

      if (_cameraIndex >= _cameras.length) {
        _cameraIndex = 0;
      }

      await _cameraController?.dispose();

      _cameraController = CameraController(
        _cameras[_cameraIndex],
        ResolutionPreset.ultraHigh,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      await _poseDetector?.close();
      _poseDetector = PoseDetector(
        options: PoseDetectorOptions(),
      );

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint("카메라 초기화 실패: $e");

      // 강제모드에서는 카메라 오류가 발생해도 화면을 유지
      if (widget.forceMode && mounted) {
        Future.delayed(
          const Duration(seconds: 1),
              () {
            if (mounted &&
                widget.forceMode &&
                (_cameraController == null ||
                    !_cameraController!.value.isInitialized)) {
              _initializeCamera();
            }
          },
        );
      }
    }
  }

  Future<void> _cancelSession() async {
    if (!mounted) return;

    final controller = TextEditingController();

    try {
      FocusManager.instance.primaryFocus?.unfocus();

      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);

      final bool? result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (dialogContext) {
          final bool isDark =
              Theme.of(dialogContext).brightness == Brightness.dark;

          final Color dialogBackground =
          isDark ? const Color(0xFF1E1E1E) : Colors.white;

          final Color primaryText =
          isDark ? Colors.white : const Color(0xFF1F2937);

          final Color inputBackground =
          isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF7F8FA);

          final Color inputBorder =
          isDark ? Colors.white24 : const Color(0xFFE5E7EB);

          final Color hintColor =
          isDark ? Colors.white54 : const Color(0xFF9CA3AF);

          final Color secondaryText =
          isDark ? Colors.white70 : const Color(0xFF6B7280);

          return PopScope(
            canPop: false,
            child: Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: dialogBackground,
                  borderRadius: BorderRadius.circular(25),
                ),
                padding: const EdgeInsets.all(25),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Text(
                          '집중 해제 사유',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: primaryText,
                          ),
                        ),
                      ),

                      const SizedBox(height: 22),

                      TextField(
                        controller: controller,
                        autofocus: true,
                        minLines: 4,
                        maxLines: 7,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        style: TextStyle(
                          color: primaryText,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: '사유를 입력해 주세요',
                          hintStyle: TextStyle(
                            color: hintColor,
                            fontSize: 14,
                          ),
                          filled: true,
                          fillColor: inputBackground,
                          contentPadding:
                          const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          border: OutlineInputBorder(
                            borderRadius:
                            BorderRadius.circular(15),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius:
                            BorderRadius.circular(15),
                            borderSide: BorderSide(
                              color: inputBorder,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius:
                            BorderRadius.circular(15),
                            borderSide: const BorderSide(
                              color: Color(0xFF6FD0F1),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () async {
                            FocusManager.instance.primaryFocus
                                ?.unfocus();

                            final reason =
                            controller.text.trim().isEmpty
                                ? '사용자 중도 해제'
                                : controller.text.trim();

                            try {
                              await _processSessionEnd(
                                isSuccess: false,
                                isCancelled: true,
                                reason: reason,
                              );

                              if (!dialogContext.mounted) {
                                return;
                              }

                              Navigator.of(dialogContext)
                                  .pop(true);
                            } catch (e, stackTrace) {
                              debugPrint(
                                '세션 종료 처리 오류: $e',
                              );
                              debugPrint('$stackTrace');
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                            const Color(0xFF6FD0F1),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius:
                              BorderRadius.circular(15),
                            ),
                          ),
                          child: const Text(
                            '제출 및 종료',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 5),

                      SizedBox(
                        width: double.infinity,
                        height: 45,
                        child: TextButton(
                          onPressed: () {
                            FocusManager.instance.primaryFocus
                                ?.unfocus();

                            Navigator.of(dialogContext)
                                .pop(false);
                          },
                          child: Text(
                            '취소하고 계속 공부하기',
                            style: TextStyle(
                              color: secondaryText,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );

      if (result == false) {
        if (!mounted) return;

        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);

        await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.immersiveSticky,
        );

        return;
      }

      if (result == true) {
        if (!mounted) return;

        await Future<void>.delayed(
          const Duration(milliseconds: 100),
        );

        if (!mounted) return;

        Navigator.of(context).popUntil(
              (route) => route.isFirst,
        );
      }
    } catch (e, stackTrace) {
      debugPrint('중도 해제 Dialog 오류: $e');
      debugPrint('$stackTrace');

      if (mounted) {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);

        await SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.immersiveSticky,
        );
      }
    } finally {
      controller.dispose();
    }
  }

  void _checkInactivity() {
    if (_isDialogShowing) return;
    // 15분 미활동 확인
    if (DateTime.now().difference(_lastMovementTime).inMinutes >= 15) {
      _showInactiveDialog();
    }
  }

  Future<void> _showInactiveDialog() async {
    if (!mounted) return;

    setState(() => _isDialogShowing = true);

    int remainingSeconds = 300;

    _inactiveTimer = Timer.periodic(
      const Duration(seconds: 1),
          (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
      },
    );

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        final bool isDark =
            Theme.of(context).brightness == Brightness.dark;

        final Color dialogBackground =
        isDark ? const Color(0xFF1E1E1E) : Colors.white;

        final Color primaryText =
        isDark ? Colors.white : const Color(0xFF1F2937);

        final Color secondaryText =
        isDark ? Colors.white70 : Colors.grey.shade700;

        final Color timerBackground =
        isDark ? const Color(0xFF3A2020) : Colors.transparent;

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
          },
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              Future.delayed(
                const Duration(seconds: 1),
                    () {
                  if (remainingSeconds > 0) {
                    if (mounted) {
                      setDialogState(
                            () => remainingSeconds--,
                      );
                    }
                  } else {
                    _inactiveTimer?.cancel();
                    _handleInactivityFailure();
                  }
                },
              );

              return Dialog(
                backgroundColor: dialogBackground,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24.0,
                      vertical: 32.0,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.timer_off_outlined,
                          color: Colors.redAccent,
                          size: 56,
                        ),

                        const SizedBox(height: 20),

                        Text(
                          "집중 중 이신가요?",
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: primaryText,
                          ),
                        ),

                        const SizedBox(height: 16),

                        Text(
                          "15분간 움직임이 감지되지 않았습니다.\n"
                              "5분 내에 확인하지 않으면\n"
                              "500P가 자동으로 차감됩니다.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: secondaryText,
                            height: 1.5,
                          ),
                        ),

                        const SizedBox(height: 24),

                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: timerBackground,
                            borderRadius:
                            BorderRadius.circular(12),
                          ),
                          child: Text(
                            "${remainingSeconds ~/ 60}분 "
                                "${remainingSeconds % 60}초",
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.redAccent,
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                              Colors.redAccent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                            onPressed: () {
                              _inactiveTimer?.cancel();

                              setState(
                                    () => _isDialogShowing = false,
                              );

                              _lastMovementTime =
                                  DateTime.now();

                              Navigator.pop(context);
                            },
                            child: const Text(
                              "공부 중입니다",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _processSessionEnd({
    required bool isSuccess,
    required bool isCancelled,
    required String reason,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || widget.sessionId == null) return;

    final firestore = FirebaseFirestore.instance;

    // 현재 날짜
    final dateKey = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final batch = firestore.batch();

    // 1. 사용자 프로필
    final userProfileRef = firestore
        .collection('users')
        .doc(user.uid)
        .collection('user_profile')
        .doc('current');

    // 2. 실제 공부 세션
    final sessionRef = firestore
        .collection('users')
        .doc(user.uid)
        .collection('study_sessions')
        .doc(widget.sessionId);

    // 3. 공부 세션 업데이트
    batch.set(
      sessionRef,
      {
        'date': dateKey,

        // 성공 여부
        'is_success': isSuccess,
        'is_failed': !isSuccess,

        // 중단 시간
        'stop_time': FieldValue.serverTimestamp(),

        // 포기/실패 이유
        'give_up_reason': reason,
      },
      SetOptions(merge: true),
    );

    // 4. 포인트 처리
    if (isSuccess) {
      // 성공: +100P
      batch.update(userProfileRef, {
        'point': FieldValue.increment(100),
      });
    } else {
      // 취소 또는 실패: -500P
      batch.update(userProfileRef, {
        'point': FieldValue.increment(-500),
      });
    }

    // 5. 한 번에 저장
    await batch.commit();
  }

  Future<void> _handleInactivityFailure() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('user_profile')
        .doc('current');

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      transaction.update(userRef, {'total_points': FieldValue.increment(-500)});
      // 로그 기록 로직은 기존과 동일...
    });

    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Widget _buildGlassmorphismContainer({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return PopScope(
        canPop: !widget.forceMode,
        child: const Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: CircularProgressIndicator(
              color: Colors.white,
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: !widget.forceMode,
      onPopInvokedWithResult: (didPop, result) {
        if (widget.forceMode && !didPop) {
          _returnToStayApp();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _cameraController!
                      .value
                      .previewSize!
                      .width,
                  height: _cameraController!
                      .value
                      .previewSize!
                      .height,
                  child: CameraPreview(
                    _cameraController!,
                  ),
                ),
              ),
            ),

            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    _buildGlassmorphismContainer(
                      child: Row(
                        children: [
                          const Icon(
                            Icons.timer_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formattedTime,
                            style: const TextStyle(
                              fontSize: 20,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontFeatures: [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _switchCamera,
                      icon: const Icon(
                        Icons.cameraswitch_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Positioned(
              bottom: 30,
              right: 20,
              child: FloatingActionButton.extended(
                onPressed: _cancelSession,
                backgroundColor:
                Colors.redAccent.withOpacity(0.8),
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                ),
                label: const Text(
                  "중도 해제",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}