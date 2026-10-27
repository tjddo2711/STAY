import 'package:device_calendar/device_calendar.dart';
import 'package:device_calendar/device_calendar.dart' as tz;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import 'package:stayapp/add_schedule_bottom_sheet.dart';
import 'package:stayapp/point_page.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'Welcome.dart';
import 'camera_timer_page.dart';
import 'firebase_options.dart';
import 'letter_page.dart';
import 'login_page.dart';
import 'map.dart';
import 'timetable_page.dart';
import 'diary_page.dart';
import 'timer_page.dart';
import 'stats_page.dart';
import 'menu.dart';

const Color pointColor = Color(0xFF6FD0F1);
const Color bgColor = Color(0xFFF0F4F8);
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.light);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await MobileAds.instance.initialize();

  await FlutterNaverMap().init(
    clientId: 'gcoze7lkvx',
  );
  final prefs = await SharedPreferences.getInstance();
  final bool isDarkMode = prefs.getBool('isDarkMode') ?? false;

  themeModeNotifier.value =
  isDarkMode ? ThemeMode.dark : ThemeMode.light;

  runApp(const StayApp());



}

class StayApp extends StatelessWidget {
  const StayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, currentMode, child) {
        return MaterialApp(
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('ko', 'KR'),
            Locale('en', 'US'),
          ],
          locale: const Locale('ko', 'KR'),
          debugShowCheckedModeBanner: false,

          themeMode: currentMode,

          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFF0F4F8),
            canvasColor: const Color(0xFFF0F4F8),
            cardColor: Colors.white,

            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              foregroundColor: Color(0xFF1E293B),
              elevation: 0,
            ),

            dialogTheme: const DialogThemeData(
              backgroundColor: Colors.white,
            ),

            bottomSheetTheme: const BottomSheetThemeData(
              backgroundColor: Colors.white,
            ),

            colorScheme: ColorScheme.fromSeed(
              seedColor: pointColor,
              brightness: Brightness.light,
            ),
          ),

          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,

            scaffoldBackgroundColor: const Color(0xFF121212),
            canvasColor: const Color(0xFF121212),
            cardColor: const Color(0xFF1E1E1E),

            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFF1E1E1E),
              foregroundColor: Colors.white,
              elevation: 0,
            ),

            dialogTheme: const DialogThemeData(
              backgroundColor: Color(0xFF1E1E1E),
            ),

            bottomSheetTheme: const BottomSheetThemeData(
              backgroundColor: Color(0xFF1E1E1E),
            ),

            colorScheme: ColorScheme.fromSeed(
              seedColor: pointColor,
              brightness: Brightness.dark,
            ),

            inputDecorationTheme: const InputDecorationTheme(
              filled: true,
              fillColor: Color(0xFF2A2A2A),
            ),
          ),

          home: const SplashCheckScreen(),
        );
      },
    );
  }
}

class SplashCheckScreen extends StatefulWidget {
  const SplashCheckScreen({super.key});

  @override
  State<SplashCheckScreen> createState() => _SplashCheckScreenState();
}

class _SplashCheckScreenState extends State<SplashCheckScreen> {
  bool _isDarkMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkUser();
    });
  }

  Future<void> toggleDarkMode(bool value) async {
    setState(() {
      _isDarkMode = value;
    });

    // 앱 전체 테마 변경
    themeModeNotifier.value =
    value ? ThemeMode.dark : ThemeMode.light;

    // 다크모드 설정 저장
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', value);
  }
  Future<void> _checkUser() async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      // 1. 로그인이 안 되어 있다면 무조건 로그인 페이지로 이동
      if (user == null) {
        _go(const LoginPage());
        return;
      }

      // 2. 로그인은 되어 있으나 웰컴페이지(온보딩: 이름, 목표)를 완료했는지 확인
      final profileDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('user_profile')
          .doc('current')
          .get();

      final data = profileDoc.data();

      // 프로필 문서가 없거나, 이름 또는 목표가 비어있다면 웰컴 페이지로 이동
      final bool onboardingCompleted = profileDoc.exists &&
          (data?['name']?.toString().trim().isNotEmpty ?? false) &&
          (data?['goal']?.toString().trim().isNotEmpty ?? false);

      if (!onboardingCompleted) {
        _go(const WelcomePage());
      } else {
        // 로그인도 되어 있고 웰컴 온보딩까지 완료된 경우에만 메인 페이지(RootScreen)로 이동
        _go(const RootScreen());
      }
    } catch (e) {
      debugPrint("초기 라우팅 오류: $e");
      _go(const LoginPage());
    }
  }

  void _go(Widget page) {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }


  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(color: pointColor),
      ),
    );
  }
}



class RootScreen extends StatefulWidget {
  const RootScreen({super.key});
  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  bool _isNavigating = false;
  bool _isTimerOpen = false;
  StreamSubscription<QuerySnapshot>? _scheduleSubscription;
  List<Map<String, dynamic>> _cachedSchedules = [];
  final Set<String> _triggeredSchedules = {};
  List<Map<String, dynamic>> _allSchedules = [];
  late final List<Widget> _pages;
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  Timer? _secondTimer;


  @override
  @override
  void initState() {
    super.initState();

    _pages = const [
      HomePage(),
      TimetablePage(),
      StatsPage(),
      DiaryPage(),
    ];

    WidgetsBinding.instance.addObserver(this);

    _initNotifications();
    _listenSchedules();
    _startTimerLoop();
  }
  @override
  void dispose() {
    _secondTimer?.cancel();
    _scheduleSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _schedule30MinuteNotification(
      Map<String, dynamic> schedule,
      ) async {
    try {
      final String scheduleId =
          schedule['doc_id']?.toString().trim() ?? '';

      if (scheduleId.isEmpty) {
        debugPrint('🔔 알림 취소: scheduleId 없음');
        return;
      }

      // 일정 시작 시간 파싱
      final DateTime? startTime = _parseScheduleDateTime(
        schedule['start_datetime'] ?? schedule['start_time'],
        dateStr: schedule['date_str']?.toString(),
      );

      if (startTime == null) {
        debugPrint('🔔 알림 취소: 시작 시간 파싱 실패');
        return;
      }

      // 시작 30분 전 시간 계산
      final DateTime notificationTime =
      startTime.subtract(const Duration(minutes: 30));

      // 이미 지난 알림은 예약하지 않음
      if (!notificationTime.isAfter(DateTime.now())) {
        debugPrint(
          '🔔 알림 취소: 이미 지난 시간 $notificationTime',
        );
        return;
      }

      // 1. 일정 제목 추출
      String title = '일정';
      final dynamic titleValue = schedule['title'] ?? schedule['subject'];
      if (titleValue != null && titleValue.toString().trim().isNotEmpty) {
        title = titleValue.toString().trim();
      }

      // 2. 선택된 장소명 추출 (다양한 장소 키값 대응)
      String location = '';
      final dynamic locValue = schedule['place_name'] ??
          schedule['location_name'] ??
          schedule['spot_name'] ??
          schedule['location'] ??
          schedule['place'] ??
          schedule['venue'];

      if (locValue != null && locValue.toString().trim().isNotEmpty) {
        location = locValue.toString().trim();
      }

      // 3. 시간 포맷팅 (예: 14:30)
      final String startText = DateFormat('HH:mm').format(startTime);

      // 4. 알림 메시지 본문 구성
      final String notificationTitle = '[30분 전] $title';
      final String notificationBody = location.isNotEmpty
          ? '시간: $startText\n장소: $location'
          : '시간: $startText';

      // 일정 ID 기반 알림 고유 ID 생성 (32비트 정수 범위 내)
      final int notificationId = scheduleId.hashCode.abs() % 2147483647;

      // 안드로이드 알림 세부 설정
      const NotificationDetails notificationDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          'schedule_reminder',
          '일정 알림',
          channelDescription: '일정 시작 30분 전 알림',
          importance: Importance.max,
          priority: Priority.high,
          icon: 'ic_notification',
          styleInformation: BigTextStyleInformation(''), // 줄바꿈 텍스트 전체 표시
          showWhen: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      // DateTime → local TZDateTime 변환
      final tz.TZDateTime scheduledDate = tz.TZDateTime.from(
        notificationTime,
        tz.local,
      );

      // 기존 동일 알림 ID 예약 취소 후 재등록
      await _notifications.cancel(notificationId);

      await _notifications.zonedSchedule(
        notificationId,
        notificationTitle,
        notificationBody,
        scheduledDate,
        notificationDetails,
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: scheduleId,
      );

      debugPrint(
        '🔔 30분 전 알림 예약 성공!\n'
            '제목: $title\n'
            '시간: $startText\n'
            '장소명: ${location.isNotEmpty ? location : "미지정"}\n'
            '예약 시각: $scheduledDate',
      );
    } catch (e, stackTrace) {
      debugPrint('❌ 30분 전 알림 예약 오류: $e');
      debugPrint('$stackTrace');
    }
  }

  Future<void> _initNotifications() async {
    tz.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(settings);

    // Android 13+
    await _notifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    // iOS
    await _notifications
        .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<bool> _isAtDesignatedLocation(
      double? targetLat,
      double? targetLng,
      ) async {
    // 지정 장소가 없는 일정이면 위치 제한 없음
    if (targetLat == null || targetLng == null) {
      return true;
    }

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        debugPrint('❌ 위치 서비스가 꺼져 있음');
        return false;
      }

      LocationPermission permission =
      await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('❌ 위치 권한 없음');
        return false;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      const double allowedDistance = 100.0; // 100m 이내를 같은 장소로 판단

      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        targetLat,
        targetLng,
      );

      debugPrint('==============================');
      debugPrint('📍 위치 검사');
      debugPrint('현재 위치: ${position.latitude}, ${position.longitude}');
      debugPrint('지정 위치: $targetLat, $targetLng');
      debugPrint('거리: ${distance.toStringAsFixed(1)}m');
      debugPrint('허용 거리: ${allowedDistance}m');
      debugPrint('현재 위치 일치: ${distance <= allowedDistance}');
      debugPrint('==============================');

      return distance <= allowedDistance;
    } catch (e) {
      debugPrint('❌ 위치 확인 오류: $e');

      // 위치 확인에 실패했으면 타이머를 실행하지 않음
      return false;
    }
  }


  void _startTimerLoop() {
    _secondTimer?.cancel();
    _secondTimer = Timer.periodic(
      const Duration(seconds: 1),
          (_) {
        if (!mounted) return;
        if (_isTimerOpen || _isNavigating) return;
        _evaluateCachedSchedules();
      },
    );
  }


  Future<void> _evaluateCachedSchedules() async {
    if (!mounted) return;
    if (_isTimerOpen || _isNavigating) return;
    if (_cachedSchedules.isEmpty) return;

    final now = DateTime.now();
    final todayDate = DateTime(
      now.year,
      now.month,
      now.day,
    );
    final todayStr = DateFormat('yyyy-MM-dd').format(now);

    for (final data in _cachedSchedules) {
      if (!mounted) return;
      if (_isTimerOpen || _isNavigating) return;

      final String scheduleId =
          data['doc_id']?.toString() ??
              data['calendar_event_id']?.toString() ??
              data['eventId']?.toString() ??
              data['event_id']?.toString() ??
              '';

      if (scheduleId.isEmpty) {
        continue;
      }

      if (_triggeredSchedules.contains(scheduleId)) {
        continue;
      }

      final String status =
          data['status']?.toString().toLowerCase().trim() ?? '';

      // ============================================================
      // 이미 타이머가 한 번 실행된 일정
      // ============================================================
      if (status == 'timer_started' ||
          status == 'completed' ||
          status == 'cancelled' ||
          status == 'deleted' ||
          status == 'failed' ||
          status == 'used') {
        _triggeredSchedules.add(scheduleId);

        debugPrint(
          '⏭️ 이미 사용된 일정 → 타이머 실행하지 않음\n'
              'scheduleId: $scheduleId\n'
              'status: $status',
        );

        continue;
      }

      // ============================================================
      // 한 번 포기한 일정
      // ============================================================
      final String giveUpReason =
          data['give_up_reason']?.toString().trim() ?? '';

      if (giveUpReason.isNotEmpty) {
        _triggeredSchedules.add(scheduleId);

        debugPrint(
          '⏭️ 이미 포기한 일정 → 타이머 실행하지 않음\n'
              'scheduleId: $scheduleId',
        );

        continue;
      }

      // ============================================================
      // 날짜 확인
      // ============================================================
      final String dateStr =
          data['date_str']?.toString() ??
              data['dateStr']?.toString() ??
              '';

      if (dateStr.isNotEmpty) {
        final DateTime? parsedDate =
        DateTime.tryParse(dateStr);

        if (parsedDate != null) {
          final DateTime targetDate = DateTime(
            parsedDate.year,
            parsedDate.month,
            parsedDate.day,
          );

          if (targetDate.isBefore(todayDate)) {
            _triggeredSchedules.add(scheduleId);
            continue;
          }

          if (targetDate.isAfter(todayDate)) {
            continue;
          }
        }
      }

      // ============================================================
      // 시작 시간
      // ============================================================
      final dynamic startValue =
          data['start_datetime'] ??
              data['start_time'] ??
              data['startTime'] ??
              data['starttime'] ??
              data['startTimeStr'];

      final DateTime? startTime =
      _parseScheduleDateTime(
        startValue,
        dateStr: dateStr.isNotEmpty
            ? dateStr
            : todayStr,
      );

      if (startTime == null) {
        debugPrint(
          '⚠️ 일정 시작시간 파싱 실패: $scheduleId',
        );
        continue;
      }

      // ============================================================
      // 종료 시간
      // ============================================================
      final dynamic endValue =
          data['end_datetime'] ??
              data['end_time'] ??
              data['endTime'] ??
              data['endtime'] ??
              data['endTimeStr'];

      final DateTime? endTime =
      _parseScheduleDateTime(
        endValue,
        dateStr: dateStr.isNotEmpty
            ? dateStr
            : todayStr,
      );

      if (now.isBefore(startTime)) {
        continue;
      }

      if (endTime != null &&
          !now.isBefore(endTime)) {
        _triggeredSchedules.add(scheduleId);
        continue;
      }

      // ============================================================
      // 장소
      // ============================================================
      double? readCoordinate(dynamic value) {
        if (value == null) return null;

        if (value is num) {
          final double result = value.toDouble();
          return result.isFinite ? result : null;
        }

        final double? result =
        double.tryParse(value.toString().trim());

        if (result == null || !result.isFinite) {
          return null;
        }

        return result;
      }

      final double? lat =
          readCoordinate(data['place_lat']) ??
              readCoordinate(data['placeLat']) ??
              readCoordinate(data['lat']) ??
              readCoordinate(data['gps_lat']) ??
              readCoordinate(data['gpsLat']) ??
              readCoordinate(data['latitude']);

      final double? lng =
          readCoordinate(data['place_lng']) ??
              readCoordinate(data['placeLng']) ??
              readCoordinate(data['lng']) ??
              readCoordinate(data['gps_lng']) ??
              readCoordinate(data['gpsLng']) ??
              readCoordinate(data['longitude']);

      // 장소 미지정이면 자동 실행하지 않음
      if (lat == null || lng == null) {
        debugPrint(
          '⏭️ 장소 미지정 → 자동 실행하지 않음\n'
              'scheduleId: $scheduleId',
        );
        continue;
      }

      // ============================================================
      // 공부 시간
      // ============================================================
      int duration = 0;

      if (endTime != null) {
        duration =
            endTime.difference(startTime).inMinutes;
      }

      if (duration <= 0) {
        duration = _parseDurationMinutes(
          data['target_minutes'] ??
              data['duration_minutes'] ??
              data['durationMinutes'] ??
              data['targetMinutes'],
        );
      }

      if (duration <= 0) {
        duration = 60;
      }

      // ============================================================
      // 강제모드
      // ============================================================
      final bool forceMode =
          data['force'] == true ||
              data['forceMode'] == true ||
              data['is_force_mode'] == true ||
              data['type']?.toString() == 'force';

      final String title =
          data['title']?.toString() ??
              data['subject']?.toString() ??
              data['name']?.toString() ??
              '공부';

      debugPrint('======================================');
      debugPrint('🚀 일정 타이머 실행');
      debugPrint('scheduleId : $scheduleId');
      debugPrint('title      : $title');
      debugPrint('startTime  : $startTime');
      debugPrint('endTime    : $endTime');
      debugPrint('duration   : $duration');
      debugPrint('forceMode  : $forceMode');
      debugPrint('latitude   : $lat');
      debugPrint('longitude  : $lng');
      debugPrint('======================================');

      // ============================================================
      // ★ 중요: ㅡㅡㅡ 처리를 없애고 상태를 timer_started로 기록하여
      // 이후 회색빛 처리 및 터치 방지(UI 연동)가 가능하도록 함
      // ============================================================
      _triggeredSchedules.add(scheduleId);

      try {
        final user = FirebaseAuth.instance.currentUser;

        if (user != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('schedules')
              .doc(scheduleId)
              .set({
            'status': 'timer_started',
            'timer_started': true,
            'timer_started_at': FieldValue.serverTimestamp(),
            'updated_at': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      } catch (e) {
        debugPrint(
          '⚠️ 타이머 실행 상태 저장 오류: $e',
        );
      }

      if (!mounted) return;

      setState(() {
        _isNavigating = true;
        _isTimerOpen = true;
      });

      try {
        if (!forceMode) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TimerPage(
                sessionId: scheduleId,
                initialLat: lat,
                initialLng: lng,
                durationMinutes: duration,
                startTime: startTime,
                endTime: endTime,
                title: title,
                forceMode: false,
              ),
            ),
          );
        } else {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CameraTimerPage(
                sessionId: scheduleId,
                initialLat: lat,
                initialLng: lng,
                durationMinutes: duration,
                startTime: startTime,
                endTime: endTime,
                title: title,
                forceMode: true,
              ),
            ),
          );
        }
      } catch (e, stackTrace) {
        debugPrint(
          '❌ 일정 타이머 화면 이동 오류: $e',
        );
        debugPrint('$stackTrace');
      }

      if (!mounted) return;

      setState(() {
        _isTimerOpen = false;
        _isNavigating = false;
      });

      break;
    }
  }  int _parseDurationMinutes(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      final cleaned = value.replaceAll(RegExp(r'[^0-9]'), '');
      return int.tryParse(cleaned) ?? 0;
    }
    return 0;
  }



  void _forceRefresh() {
    if (mounted) setState(() {});
  }

  Future<void> saveSchedule({
    required Map<String, dynamic> location,
    required DateTime startTime,
    required int duration,
    required String subject,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final uid = user.uid;

    // 장소 좌표 변환 (장소 정보가 없거나 비어있을 경우 현재 위치를 기본값으로 처리)
    double? latitude;
    double? longitude;
    String placeName = location["name"]?.toString().trim() ?? "";
    String placeAddress = location["address"]?.toString().trim() ?? "";

    if (placeName.isEmpty && placeAddress.isEmpty) {
      try {
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (serviceEnabled) {
          LocationPermission permission = await Geolocator.checkPermission();
          if (permission == LocationPermission.denied) {
            permission = await Geolocator.requestPermission();
          }
          if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
            debugPrint('❌ 위치 권한 없음');
          } else {
            final position = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high,
            );
            latitude = position.latitude;
            longitude = position.longitude;
            placeName = "현재 위치";
            placeAddress = "현재 위치 좌표 기준";
          }
        }
      } catch (e) {
        debugPrint('❌ 현재 위치 가져오기 오류: $e');
      }
    } else {
      final dynamic rawLat = location["latitude"] ?? location["lat"];
      final dynamic rawLng = location["longitude"] ?? location["lng"];

      if (rawLat is num) {
        latitude = rawLat.toDouble();
      } else {
        latitude = double.tryParse(rawLat?.toString() ?? '');
      }

      if (rawLng is num) {
        longitude = rawLng.toDouble();
      } else {
        longitude = double.tryParse(rawLng?.toString() ?? '');
      }
    }

    debugPrint('==============================');
    debugPrint('일정 저장');
    debugPrint('장소: $placeName');
    debugPrint('주소: $placeAddress');
    debugPrint('latitude: $latitude');
    debugPrint('longitude: $longitude');
    debugPrint('duration: $duration');
    debugPrint('==============================');

    await FirebaseFirestore.instance
        .collection("users")
        .doc(uid)
        .collection("schedules")
        .add({
      "title": subject,
      "subject": subject,

      // 장소
      "place_name": placeName,
      "place_address": placeAddress,

      // 장소 좌표
      "place_lat": latitude,
      "place_lng": longitude,

      // 목표 공부시간
      "target_minutes": duration,

      // 일정 시간
      "start_datetime": Timestamp.fromDate(startTime),
      "end_datetime": Timestamp.fromDate(
        startTime.add(
          Duration(minutes: duration),
        ),
      ),

      // 강제모드
      "force": false,

      "created_at": FieldValue.serverTimestamp(),
      "updated_at": FieldValue.serverTimestamp(),
    });
  }


  void _listenSchedules() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _scheduleSubscription?.cancel();
    _scheduleSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('schedules')
        .snapshots()
        .listen((snapshot) {
      final List<Map<String, dynamic>> schedules = snapshot.docs.map((doc) {
        return {
          ...doc.data(),
          'doc_id': doc.id,
        };
      }).toList();

      schedules.sort((a, b) {
        final aTime = _parseScheduleDateTime(
          a['start_time'] ?? a['start_datetime'],
          dateStr: a['date_str']?.toString(),
        ) ??
            DateTime(2099);

        final bTime = _parseScheduleDateTime(
          b['start_time'] ?? b['start_datetime'],
          dateStr: b['date_str']?.toString(),
        ) ??
            DateTime(2099);

        return aTime.compareTo(bTime);
      });

      _cachedSchedules = schedules;

      // 🔔 새로운 일정 목록이 들어올 때마다 30분 전 알림 자동 예약
      for (final schedule in schedules) {
        _schedule30MinuteNotification(schedule);
      }

      _evaluateCachedSchedules();
    });
  }
  DateTime? _parseScheduleDateTime(dynamic value, {String? dateStr}) {
    try {
      if (value == null) return null;
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;

      final String text = value.toString().trim();
      final iso = DateTime.tryParse(text);
      if (iso != null) return iso.toLocal();

      final targetDate = dateStr ?? DateFormat('yyyy-MM-dd').format(DateTime.now());

      if (RegExp(r'^\d{1,2}:\d{2}$').hasMatch(text)) {
        final parts = text.split(':');
        return DateTime(
          int.parse(targetDate.substring(0, 4)),
          int.parse(targetDate.substring(5, 7)),
          int.parse(targetDate.substring(8, 10)),
          int.parse(parts[0]),
          int.parse(parts[1]),
        );
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _evaluateCachedSchedules();
    }
  }


  Future<void> _deleteScheduleImmediately(String scheduleId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final bool isDark =
          Theme.of(context).brightness == Brightness.dark;

      final Color dialogBackground =
      isDark ? const Color(0xFF1E1E1E) : Colors.white;

      final Color primaryText =
      isDark ? Colors.white : const Color(0xFF111827);

      final Color secondaryText =
      isDark ? Colors.white70 : Colors.black87;

      final targetSchedule = _allSchedules.firstWhere(
            (item) => item['doc_id']?.toString() == scheduleId,
        orElse: () => {},
      );

      final String source = targetSchedule['source'] ?? '';

      if (source == 'calendar') {
        if (mounted) {
          setState(() {});

          showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                backgroundColor: dialogBackground,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: Text(
                  "캘린더 일정 삭제 안내",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: primaryText,
                  ),
                ),
                content: Text(
                  "삼성 캘린더 연동 일정은 삼성 캘린더 앱에서 삭제해 주세요.",
                  style: TextStyle(
                    fontSize: 14,
                    color: secondaryText,
                  ),
                ),
                actions: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: pointColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      "확인",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              );
            },
          );
        }
        return;
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('schedules')
          .doc(scheduleId)
          .delete();

      if (mounted) {
        setState(() {
          _allSchedules.removeWhere(
                (item) => item['doc_id']?.toString() == scheduleId,
          );
        });
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor:
          isDark ? const Color(0xFF2A2A2A) : null,
          content: Text(
            '일정이 삭제되었습니다.',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.white,
            ),
          ),
        ),
      );
    } catch (e) {
      debugPrint("일정 삭제 오류 : $e");
    }
  }


  @override
  Widget build(BuildContext context) {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color screenBackground =
    isDark ? const Color(0xFF121212) : bgColor;

    final Color navigationBackground =
    isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      extendBody: true,

      // 기존 bgColor → 테마에 따라 변경
      backgroundColor: screenBackground,

      body: _pages[_selectedIndex],

      floatingActionButtonLocation:
      FloatingActionButtonLocation.centerDocked,

      floatingActionButton: Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: pointColor,
          boxShadow: [
            BoxShadow(
              color: pointColor.withOpacity(0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: FloatingActionButton(
          elevation: 0,
          backgroundColor: Colors.transparent,
          shape: const CircleBorder(),
          onPressed: () async {
            await showAddScheduleBottomSheet(context);
          },
          child: const Icon(
            Icons.add_rounded,
            color: Colors.white,
            size: 32,
          ),
        ),
      ),

      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            // 기존 Colors.white → navigationBackground
            color: navigationBackground,
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withOpacity(0.35)
                    : Colors.black.withOpacity(0.07),
                blurRadius: 25,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: BottomAppBar(
            // 기존 Colors.white → navigationBackground
            color: navigationBackground,
            elevation: 0,
            shape: const CircularNotchedRectangle(),
            notchMargin: 8,
            child: SizedBox(
              height: 72,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNavButton(Icons.home_rounded, "홈", 0),
                  _buildNavButton(Icons.bar_chart_rounded, "통계", 2),
                  const SizedBox(width: 58),
                  _buildNavButton(Icons.calendar_month_rounded, "시간표", 1),
                  _buildNavButton(Icons.menu_book_rounded, "일기", 3),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildNavButton(
      IconData icon,
      String label,
      int index,
      ) {
    final bool isSelected = _selectedIndex == index;
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });
      },
      child: SizedBox(
        width: 58,
        height: 60,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: isSelected ? 42 : 34,
              height: 30,
              decoration: BoxDecoration(
                color: isSelected
                    ? pointColor.withOpacity(0.14)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(
                icon,
                color: isSelected
                    ? pointColor
                    : isDark
                    ? Colors.white54
                    : const Color(0xFF9AA5AE),
                size: isSelected ? 23 : 21,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? isDark
                    ? Colors.white
                    : const Color(0xFF303B43)
                    : isDark
                    ? Colors.white54
                    : const Color(0xFF9AA5AE),
                fontSize: 10,
                fontWeight:
                isSelected ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

}



class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}
class _HomePageState extends State<HomePage> {

  final PageController _pageController = PageController(initialPage: 1000);
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  DateTime _displayDate = DateTime.now();
  DateTime _baseDate = DateTime.now();

  List<Map<String, dynamic>> _allSchedules = [];
  final Set<String> _triggeredSchedules = {};
  bool _isLoadingSchedules = true;
  StreamSubscription<QuerySnapshot>? _scheduleStream;


  @override
  void initState() {
    super.initState();

    _startRealtimeScheduleSync();
  }

  @override
  void dispose() {
    _scheduleStream?.cancel();
    _pageController.dispose();
    super.dispose();
  }




  void _startRealtimeScheduleSync() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (mounted) {
        setState(() {
          _isLoadingSchedules = false;
          _allSchedules = [];
        });
      }
      return;
    }

    _scheduleStream?.cancel();

    _scheduleStream = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('schedules')
        .snapshots()
        .listen((snapshot) {
      final List<Map<String, dynamic>> firestoreSchedules = [];

      for (final doc in snapshot.docs) {
        final data = doc.data();

        if (data.isEmpty) continue;

        final Map<String, dynamic> schedule = {
          ...data,
          'doc_id': doc.id,
        };

        final dynamic rawLat =
            data['place_lat'] ??
                data['lat'] ??
                data['gps_lat'] ??
                data['latitude'];

        final dynamic rawLng =
            data['place_lng'] ??
                data['lng'] ??
                data['gps_lng'] ??
                data['longitude'];

        double? lat;
        double? lng;

        if (rawLat is num) {
          lat = rawLat.toDouble();
        } else if (rawLat != null) {
          lat = double.tryParse(rawLat.toString().trim());
        }

        if (rawLng is num) {
          lng = rawLng.toDouble();
        } else if (rawLng != null) {
          lng = double.tryParse(rawLng.toString().trim());
        }

        schedule['lat'] = lat;
        schedule['lng'] = lng;

        // 장소명도 하나의 필드로 통일
        schedule['place_name'] =
        data['place_name']?.toString().trim().isNotEmpty == true
            ? data['place_name']
            : data['location_name']?.toString().trim().isNotEmpty == true
            ? data['location_name']
            : data['place_address'] ?? '';

        firestoreSchedules.add(schedule);
      }

      firestoreSchedules.sort((a, b) {
        final aTime = _parseScheduleDateTime(
          a['start_time'] ?? a['start_datetime'],
          dateStr: a['date_str'],
        ) ??
            DateTime(2099);

        final bTime = _parseScheduleDateTime(
          b['start_time'] ?? b['start_datetime'],
          dateStr: b['date_str'],
        ) ??
            DateTime(2099);

        return aTime.compareTo(bTime);
      });

      if (!mounted) return;

      setState(() {
        _allSchedules = firestoreSchedules;
        _isLoadingSchedules = false;
      });
    }, onError: (error) {
      if (!mounted) return;

      setState(() {
        _isLoadingSchedules = false;
      });

      debugPrint('스케줄 동기화 중 오류 발생: $error');
    });
  }

  Future<void> _loadSamsungCalendar() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final permission = await Permission.calendar.request();
    if (!permission.isGranted) return;

    final DeviceCalendarPlugin calendarPlugin = DeviceCalendarPlugin();

    try {
      final calendarsResult = await calendarPlugin.retrieveCalendars();
      if (!calendarsResult.isSuccess || calendarsResult.data == null) return;

      final start = DateTime.now().subtract(const Duration(days: 3));
      final end = DateTime.now().add(const Duration(days: 30));

      for (final calendar in calendarsResult.data!) {
        final eventsResult = await calendarPlugin.retrieveEvents(
          calendar.id,
          RetrieveEventsParams(
            startDate: start,
            endDate: end,
          ),
        );

        if (!eventsResult.isSuccess || eventsResult.data == null) continue;

        for (final event in eventsResult.data!) {
          if (event.start == null || event.allDay == true) continue;

          final startTime = event.start!;
          final endTime =
              event.end ?? startTime.add(const Duration(hours: 1));

          final String title = event.title ?? "캘린더 일정";
          final String eventId =
              event.eventId ??
                  "${calendar.id}_${startTime.toIso8601String()}";

          final String locationName =
              event.location?.toString().trim() ?? '';

          final duplicateQuery = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('schedules')
              .where(
            'calendar_event_id',
            isEqualTo: eventId,
          )
              .limit(1)
              .get();

          if (duplicateQuery.docs.isNotEmpty) continue;

          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('schedules')
              .add({
            'title': title,
            'subject': '캘린더',

            // 삼성 캘린더 장소
            'location_name': locationName,
            'place_name': locationName,
            'place_address': locationName,

            'start_time': startTime.toIso8601String(),
            'end_time': endTime.toIso8601String(),
            'date_str': DateFormat('yyyy-MM-dd').format(startTime),
            'duration_minutes':
            endTime.difference(startTime).inMinutes,

            // 좌표는 없는 경우 null로 유지
            'lat': null,
            'lng': null,
            'place_lat': null,
            'place_lng': null,

            'forceMode': false,
            'type': 'normal',
            'status': 'scheduled',
            'repeat': false,
            'repeat_type': null,
            'source': 'calendar',
            'calendar_event_id': eventId,
            'created_at': FieldValue.serverTimestamp(),
            'updated_at': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (e) {
      debugPrint("삼성 캘린더 동기화 오류 : $e");
    }
  }

  Color _scheduleColor(dynamic value) {
    if (value is int) return Color(value);
    if (value is String) {
      if (value.startsWith('0x')) {
        return Color(int.parse(value));
      }
      final parsed = int.tryParse(value);
      if (parsed != null) return Color(parsed);
    }
    return pointColor;
  }

  Color _parseColor(dynamic data) {
    final rawColor = data['color'] ?? data['ui_color'] ?? data['calendar_color'] ?? data['calendar_event_color'];
    return _scheduleColor(rawColor);
  }

  double? _parseCoordinate(dynamic value) {
    if (value == null) return null;

    if (value is num) {
      final result = value.toDouble();

      if (result.isFinite) {
        return result;
      }

      return null;
    }

    final result = double.tryParse(
      value.toString().trim(),
    );

    if (result == null || !result.isFinite) {
      return null;
    }

    return result;
  }

  Future<void> _navigateToTimer(
      Map<String, dynamic> schedule, {
        bool startNow = false,
      }) async {
    if (!mounted) return;

    final String scheduleId =
        schedule['doc_id']?.toString().trim() ?? '';

    if (scheduleId.isEmpty) return;

    // ============================================================
    // 이미 포기/실패/취소한 일정인지 먼저 확인
    // → 한 번 포기한 일정은 다시 TimerPage로 보내지 않음
    // ============================================================

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        final firestore = FirebaseFirestore.instance;

        // ----------------------------------------------------------
        // 1. schedules 문서 상태 확인
        // ----------------------------------------------------------

        final scheduleDoc = await firestore
            .collection('users')
            .doc(user.uid)
            .collection('schedules')
            .doc(scheduleId)
            .get();

        if (scheduleDoc.exists) {
          final data = scheduleDoc.data();

          if (data != null) {
            final String status =
                data['status']?.toString().trim().toLowerCase() ?? '';

            final bool isFailedStatus =
                status == 'failed' ||
                    status == 'cancelled' ||
                    status == 'give_up' ||
                    status == 'given_up' ||
                    status == 'abandoned' ||
                    status == 'deleted';

            final bool isGivenUp =
                data['is_success'] == false ||
                    data['isSuccess'] == false ||
                    (data['isFinished'] == true &&
                        data['is_success'] == false) ||
                    (data['isFinished'] == true &&
                        data['isSuccess'] == false);

            if (isFailedStatus || isGivenUp) {
              debugPrint(
                '🚫 이미 포기/실패한 일정 → TimerPage 이동 차단\n'
                    'scheduleId: $scheduleId\n'
                    'status: $status',
              );

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('이미 포기한 일정입니다.'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }

              return;
            }
          }
        }

        // ----------------------------------------------------------
        // 2. study_sessions에도 이미 실패 기록이 있는지 확인
        // ----------------------------------------------------------

        final sessionDoc = await firestore
            .collection('users')
            .doc(user.uid)
            .collection('study_sessions')
            .doc(scheduleId)
            .get();

        if (sessionDoc.exists) {
          final sessionData = sessionDoc.data();

          if (sessionData != null) {
            final String sessionStatus =
                sessionData['status']?.toString().trim().toLowerCase() ?? '';

            final bool sessionFailed =
                sessionStatus == 'failed' ||
                    sessionStatus == 'cancelled' ||
                    sessionStatus == 'give_up' ||
                    sessionStatus == 'given_up' ||
                    sessionStatus == 'abandoned';

            final bool sessionNotSuccess =
                sessionData['is_success'] == false ||
                    sessionData['isSuccess'] == false;

            if (sessionFailed || sessionNotSuccess) {
              debugPrint(
                '🚫 study_sessions에 이미 포기 기록 존재 → '
                    'TimerPage 이동 차단\n'
                    'scheduleId: $scheduleId\n'
                    'status: $sessionStatus',
              );

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('이미 포기한 일정입니다.'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }

              return;
            }
          }
        }
      }
    } catch (e, stackTrace) {
      debugPrint('❌ 포기한 일정 확인 오류: $e');
      debugPrint('$stackTrace');
    }

    final int duration = _getDurationMinutes(schedule);

    double? parse(dynamic value) {
      if (value == null) return null;

      if (value is num) {
        final double v = value.toDouble();
        return v.isFinite ? v : null;
      }

      final double? v =
      double.tryParse(value.toString().trim());

      return v != null && v.isFinite ? v : null;
    }

    double? placeLat =
        parse(schedule['place_lat']) ??
            parse(schedule['placeLat']) ??
            parse(schedule['lat']) ??
            parse(schedule['gps_lat']) ??
            parse(schedule['gpsLat']) ??
            parse(schedule['latitude']);

    double? placeLng =
        parse(schedule['place_lng']) ??
            parse(schedule['placeLng']) ??
            parse(schedule['lng']) ??
            parse(schedule['gps_lng']) ??
            parse(schedule['gpsLng']) ??
            parse(schedule['longitude']);

    String placeName =
        schedule['place_name']?.toString().trim() ?? '';

    if (placeName.isEmpty) {
      placeName =
          schedule['location_name']?.toString().trim() ?? '';
    }

    if (placeName.isEmpty) {
      placeName =
          schedule['place_address']?.toString().trim() ?? '';
    }

    // ============================================================
    // Firestore에서 최신 장소 정보 확인
    // ============================================================

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('schedules')
            .doc(scheduleId)
            .get();

        if (doc.exists) {
          final data = doc.data();

          if (data != null) {
            final String status =
                data['status']?.toString().trim().toLowerCase() ?? '';

            final bool isFailedStatus =
                status == 'failed' ||
                    status == 'cancelled' ||
                    status == 'give_up' ||
                    status == 'given_up' ||
                    status == 'abandoned' ||
                    status == 'deleted';

            final bool isGivenUp =
                data['is_success'] == false ||
                    data['isSuccess'] == false;

            if (isFailedStatus || isGivenUp) {
              debugPrint(
                '🚫 최신 일정 상태가 포기 상태 → TimerPage 이동 차단',
              );

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('이미 포기한 일정입니다.'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }

              return;
            }

            placeLat ??= parse(data['place_lat']);
            placeLng ??= parse(data['place_lng']);

            placeLat ??= parse(data['placeLat']);
            placeLng ??= parse(data['placeLng']);

            placeLat ??= parse(data['lat']);
            placeLng ??= parse(data['lng']);

            placeLat ??= parse(data['gps_lat']);
            placeLng ??= parse(data['gps_lng']);

            placeLat ??= parse(data['latitude']);
            placeLng ??= parse(data['longitude']);

            if (placeName.isEmpty) {
              placeName =
                  data['place_name']?.toString().trim() ?? '';
            }

            if (placeName.isEmpty) {
              placeName =
                  data['location_name']?.toString().trim() ?? '';
            }

            if (placeName.isEmpty) {
              placeName =
                  data['place_address']?.toString().trim() ?? '';
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Firestore 일정 조회 오류: $e');
    }

    // ============================================================
    // [수정 핵심]
    // 1. startNow가 true인 경우 (시작하기 버튼 클릭 시):
    //    장소가 없으면 장소 선택창을 띄우고, 장소 지정 후 타이머 화면으로 바로 이동
    // 2. startNow가 false인 경우 (일정 항목 클릭 시):
    //    타이머 시작 없이 장소를 변경/지정할 수 있는 맵 모달/페이지 팝업
    // ============================================================

    if (!startNow) {
      if (!mounted) return;

      final DateTime? startTime = _parseScheduleDateTime(
        schedule['start_datetime'] ?? schedule['start_time'],
        dateStr: schedule['date_str']?.toString(),
      );

      final DateTime selectedDate = startTime ?? DateTime.now();

      final TimeOfDay selectedStartTime = startTime != null
          ? TimeOfDay(
        hour: startTime.hour,
        minute: startTime.minute,
      )
          : TimeOfDay.now();

      int colorValue = const Color(0xFF6FD0F1).value;

      final dynamic savedColor = schedule['ui_color'] ??
          schedule['color'] ??
          schedule['calendar_color'];

      if (savedColor is int) {
        colorValue = savedColor;
      } else if (savedColor != null) {
        colorValue = int.tryParse(savedColor.toString()) ??
            const Color(0xFF6FD0F1).value;
      }

      // 일정 클릭 시 바로 장소 지정/변경 지도 화면 오픈
      final dynamic result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MapSelectionPage(
            startTime: selectedStartTime,
            duration: duration,
            selectedDate: selectedDate,
            isFromCalendar: true,
            title: schedule['title']?.toString() ??
                schedule['subject']?.toString() ??
                '공부',
            colorValue: colorValue,
          ),
        ),
      );

      if (!mounted || result == null) return;

      if (result is! Map) {
        debugPrint('❌ 장소 선택 결과가 Map이 아닙니다.');
        return;
      }

      final dynamic rawLocation = result['location'];

      if (rawLocation is! Map) {
        debugPrint('❌ 장소 선택 결과에 location이 없습니다.');
        return;
      }

      final String selectedPlaceName =
          rawLocation['name']?.toString().trim() ?? '';

      final String selectedAddress =
          rawLocation['address']?.toString().trim() ?? '';

      final double? selectedLat = parse(rawLocation['latitude']);
      final double? selectedLng = parse(rawLocation['longitude']);

      if (selectedLat == null || selectedLng == null || selectedPlaceName.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('장소를 다시 선택해주세요.'),
            ),
          );
        }
        return;
      }

      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) return;

        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('schedules')
            .doc(scheduleId)
            .update({
          'place_name': selectedPlaceName,
          'location_name': selectedPlaceName,
          'location': selectedPlaceName,
          'place_address': selectedAddress,
          'place_lat': selectedLat,
          'place_lng': selectedLng,
          'lat': selectedLat,
          'lng': selectedLng,
          'updated_at': FieldValue.serverTimestamp(),
        });

        schedule['place_name'] = selectedPlaceName;
        schedule['location_name'] = selectedPlaceName;
        schedule['location'] = selectedPlaceName;
        schedule['place_address'] = selectedAddress;
        schedule['place_lat'] = selectedLat;
        schedule['place_lng'] = selectedLng;
        schedule['lat'] = selectedLat;
        schedule['lng'] = selectedLng;

        if (mounted) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('장소가 성공적으로 변경/지정되었습니다.'),
            ),
          );
        }
      } catch (e, stackTrace) {
        debugPrint('❌ 일정 장소 저장 오류: $e');
        debugPrint('$stackTrace');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('장소 저장에 실패했습니다.'),
            ),
          );
        }
      }
      // 단순히 일정을 눌렀을 때는 장소만 수정하고 함수 종료 (타이머 실행 X)
      return;
    }

    // ============================================================
    // startNow == true (시작하기 눌렀을 때 실행)
    // ============================================================

    // 장소가 지정되어 있지 않다면 장소 지정 팝업 진행 후 바로 타이머 시작
    if (placeLat == null || placeLng == null) {
      if (!mounted) return;

      final DateTime? startTime = _parseScheduleDateTime(
        schedule['start_datetime'] ?? schedule['start_time'],
        dateStr: schedule['date_str']?.toString(),
      );

      final DateTime selectedDate = startTime ?? DateTime.now();

      final TimeOfDay selectedStartTime = startTime != null
          ? TimeOfDay(
        hour: startTime.hour,
        minute: startTime.minute,
      )
          : TimeOfDay.now();

      int colorValue = const Color(0xFF6FD0F1).value;

      final dynamic savedColor = schedule['ui_color'] ??
          schedule['color'] ??
          schedule['calendar_color'];

      if (savedColor is int) {
        colorValue = savedColor;
      } else if (savedColor != null) {
        colorValue = int.tryParse(savedColor.toString()) ??
            const Color(0xFF6FD0F1).value;
      }

      final bool shouldSelectPlace = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          final bool isDark =
              Theme.of(dialogContext).brightness == Brightness.dark;

          return AlertDialog(
            backgroundColor:
            isDark ? const Color(0xFF1E1E1E) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              '장소 미지정',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF202124),
              ),
            ),
            content: Text(
              '타이머를 시작하려면 장소를 먼저 지정해야 합니다.\n장소를 지정하시겠습니까?',
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: isDark ? Colors.white70 : const Color(0xFF666666),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(
                  '취소',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.grey.shade700,
                  ),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6FD0F1),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  '장소 지정',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          );
        },
      ) ??
          false;

      if (!shouldSelectPlace || !mounted) return;

      final dynamic result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MapSelectionPage(
            startTime: selectedStartTime,
            duration: duration,
            selectedDate: selectedDate,
            isFromCalendar: true,
            title: schedule['title']?.toString() ??
                schedule['subject']?.toString() ??
                '공부',
            colorValue: colorValue,
          ),
        ),
      );

      if (!mounted || result == null || result is! Map) return;

      final dynamic rawLocation = result['location'];
      if (rawLocation is! Map) return;

      final String selectedPlaceName =
          rawLocation['name']?.toString().trim() ?? '';
      final String selectedAddress =
          rawLocation['address']?.toString().trim() ?? '';
      final double? selectedLat = parse(rawLocation['latitude']);
      final double? selectedLng = parse(rawLocation['longitude']);

      if (selectedLat == null || selectedLng == null || selectedPlaceName.isEmpty) {
        return;
      }

      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) return;

        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('schedules')
            .doc(scheduleId)
            .update({
          'place_name': selectedPlaceName,
          'location_name': selectedPlaceName,
          'location': selectedPlaceName,
          'place_address': selectedAddress,
          'place_lat': selectedLat,
          'place_lng': selectedLng,
          'lat': selectedLat,
          'lng': selectedLng,
          'updated_at': FieldValue.serverTimestamp(),
        });

        placeLat = selectedLat;
        placeLng = selectedLng;
        placeName = selectedPlaceName;

        if (mounted) setState(() {});
      } catch (e) {
        debugPrint('❌ 일정 장소 저장 오류: $e');
        return;
      }
    }

    // 장소 지정이 정상적으로 완료되었거나 이미 지정된 상태에서 시작하기 버튼 누름 -> TimerPage 오픈
    if (placeLat == null || placeLng == null) return;

    debugPrint('======================================');
    debugPrint('🚀 시작하기 실행 → TimerPage 이동');
    debugPrint('scheduleId : $scheduleId');
    debugPrint('placeName  : $placeName');
    debugPrint('latitude   : $placeLat');
    debugPrint('longitude  : $placeLng');
    debugPrint('======================================');

    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TimerPage(
            sessionId: scheduleId,
            initialLat: placeLat,
            initialLng: placeLng,
            durationMinutes: duration,
            durationMinutesFromSchedule: duration,
            forceMode: true,
            autoStarted: false,
            startTime: _parseScheduleDateTime(
              schedule['start_datetime'] ?? schedule['start_time'],
              dateStr: schedule['date_str']?.toString(),
            ),
            endTime: _parseScheduleDateTime(
              schedule['end_datetime'] ?? schedule['end_time'],
              dateStr: schedule['date_str']?.toString(),
            ),
            title: schedule['title']?.toString() ??
                schedule['subject']?.toString() ??
                '공부',
            placeName: placeName.isNotEmpty ? placeName : null,
          ),
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('❌ TimerPage 이동 오류: $e');
      debugPrint('$stackTrace');
    }
  }
  void _openDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  BoxDecoration _neuBox({
    Color? color,
    double radius = 25,
  }) {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color backgroundColor = color ??
        (isDark
            ? const Color(0xFF1E1E1E)
            : Colors.white);

    return BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: isDark
              ? Colors.black.withOpacity(0.35)
              : Colors.black.withOpacity(0.055),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  String _getDateTitle(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return "오늘 일정";
    }
    return "${DateFormat('M월 d일').format(date)} 일정";
  }


  int _getDurationMinutes(Map<String, dynamic> data) {
    final raw =
        data['target_minutes'] ??
            data['duration_minutes'] ??
            data['duration'] ??
            data['study_time'] ??
            data['time'] ??
            60;

    if (raw is int) return raw;
    if (raw is double) return raw.toInt();

    if (raw is String) {
      final cleaned = raw.replaceAll(RegExp(r'[^0-9]'), '');
      return int.tryParse(cleaned) ?? 60;
    }

    return 60;
  }


  DateTime? _parseScheduleDateTime(dynamic value, {String? dateStr}) {
    try {
      if (value == null) return null;
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;

      final String text = value.toString().trim();
      if (text.isEmpty) return null;

      final iso = DateTime.tryParse(text);
      if (iso != null) return iso.toLocal();

      return null;
    } catch (e) {
      debugPrint("시간 변환 오류 : $e");
      return null;
    }
  }

//하단 리스트
//하단 리스트
// _buildScheduleTimeline 함수 전체 교체

// 날짜별 스케줄 타임라인 빌더
  Widget _buildScheduleTimeline(String uid, DateTime date) {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color cardColor =
    isDark ? const Color(0xFF1E1E1E) : Colors.white;

    final Color titleColor =
    isDark ? Colors.white : const Color(0xFF2D3436);

    final Color subTextColor =
    isDark ? Colors.white70 : Colors.grey.shade600;

    final Color emptyTextColor =
    isDark ? Colors.white60 : Colors.grey;

    final Color processedBackground =
    isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade100;

    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final targetDate = DateTime(date.year, date.month, date.day);

    final schedules = _allSchedules.where((s) {
      final rawStart = s['start_time'] ?? s['start_datetime'];

      final start = _parseScheduleDateTime(
        rawStart,
        dateStr: s['date_str']?.toString() ?? dateStr,
      );

      if (start == null) return false;

      final scheduleDate =
      DateTime(start.year, start.month, start.day);

      return DateFormat('yyyy-MM-dd').format(scheduleDate) == dateStr;
    }).toList();

    schedules.sort((a, b) {
      final aTime = _parseScheduleDateTime(
        a['start_time'] ?? a['start_datetime'],
        dateStr: a['date_str']?.toString() ?? dateStr,
      ) ?? DateTime(2099);

      final bTime = _parseScheduleDateTime(
        b['start_time'] ?? b['start_datetime'],
        dateStr: b['date_str']?.toString() ?? dateStr,
      ) ?? DateTime(2099);

      return aTime.compareTo(bTime);
    });

    if (schedules.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Text(
            "예정된 일정이 없습니다.",
            style: TextStyle(
              color: emptyTextColor,
              fontSize: 15,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: schedules.length,
      itemBuilder: (context, index) {
        final data = schedules[index];
        final docId = data['doc_id']?.toString() ?? '';

        final title =
        (data['title'] != null &&
            data['title'].toString().trim().isNotEmpty)
            ? data['title'].toString()
            : ((data['subject'] != null &&
            data['subject'].toString().trim().isNotEmpty)
            ? data['subject'].toString()
            : '제목 없음');

        final String locationName =
        (data['place_name'] != null && data['place_name'].toString().trim().isNotEmpty)
            ? data['place_name'].toString()
            : (data['location_name'] != null && data['location_name'].toString().trim().isNotEmpty)
            ? data['location_name'].toString()
            : (data['place_address'] != null && data['place_address'].toString().trim().isNotEmpty)
            ? data['place_address'].toString()
            : (data['location'] != null && data['location'].toString().trim().isNotEmpty)
            ? data['location'].toString()
            : '장소 미지정';

        final startTime = _parseScheduleDateTime(
          data['start_time'] ?? data['start_datetime'],
          dateStr: data['date_str']?.toString() ?? dateStr,
        );

        final endTime = _parseScheduleDateTime(
          data['end_time'] ?? data['end_datetime'],
          dateStr: data['date_str']?.toString() ?? dateStr,
        );

        final startTimeStr = startTime != null
            ? DateFormat('HH:mm').format(startTime)
            : '--:--';

        final endTimeStr = endTime != null
            ? DateFormat('HH:mm').format(endTime)
            : '--:--';

        final timeDisplay =
            "$startTimeStr ~ $endTimeStr";

        final bool isPastDate =
        targetDate.isBefore(todayDate);

        final bool isExpiredTime =
            targetDate.isAtSameMomentAs(todayDate) &&
                endTime != null &&
                now.isAfter(endTime);

        final String status =
            data['status']?.toString() ?? '';

        final bool isCompleted =
            status == 'completed' ||
                status == 'success' ||
                data['isFinished'] == true;

        final bool isCancelled =
            status == 'cancelled' ||
                status == 'failed' ||
                status == 'deleted';

        final bool isProcessed =
            isCompleted ||
                isCancelled ||
                isPastDate ||
                isExpiredTime;

        final Color accentColor =
        isProcessed ? Colors.grey : _parseColor(data);

        final Widget scheduleCard = Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: _neuBox(
            color: cardColor,
            radius: 18,
          ),
          child: Row(
            children: [
              Container(
                width: 5,
                height: 50,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        decoration: isProcessed
                            ? TextDecoration.lineThrough
                            : null,
                        color: isProcessed
                            ? Colors.grey
                            : titleColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "$locationName · $timeDisplay",
                      style: TextStyle(
                        color: subTextColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (isProcessed)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: processedBackground,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    color: Colors.grey,
                    size: 18,
                  ),
                ),
            ],
          ),
        );

        return Dismissible(
          key: Key(
            docId.isNotEmpty
                ? docId
                : index.toString(),
          ),
          direction:
          data['source']?.toString() == 'calendar'
              ? DismissDirection.none
              : DismissDirection.endToStart,
          confirmDismiss: (_) async {
            if (data['source']?.toString() == 'calendar') {
              await showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text("캘린더 일정 안내"),
                  content: const Text(
                    "삼성 캘린더 연동 일정은 앱 내에서 삭제할 수 없습니다.",
                  ),
                  actions: [
                    TextButton(
                      onPressed: () =>
                          Navigator.pop(context),
                      child: const Text("확인"),
                    ),
                  ],
                ),
              );
              return false;
            }

            return true;
          },
          onDismissed: (_) async {
            if (docId.isNotEmpty) {
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(
                FirebaseAuth.instance.currentUser?.uid,
              )
                  .collection('schedules')
                  .doc(docId)
                  .delete();
            }
          },
          background: Container(
            margin: const EdgeInsets.only(bottom: 12),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            decoration: BoxDecoration(
              color: Colors.redAccent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.delete_outline,
              color: Colors.white,
            ),
          ),
          child: isProcessed
              ? scheduleCard
              : GestureDetector(
            onTap: () =>
                _navigateToTimer(data),
            child: scheduleCard,
          ),
        );
      },
    );
  }


  bool _isPastScheduleDate(Map<String, dynamic> item) {
    try {
      final String dateStr =
          item['date_str']?.toString() ??
              item['dateStr']?.toString() ??
              '';

      if (dateStr.isEmpty) return false;

      final parsedDate = DateTime.tryParse(dateStr);

      if (parsedDate == null) return false;

      final today = DateTime.now();

      final targetDate = DateTime(
        parsedDate.year,
        parsedDate.month,
        parsedDate.day,
      );

      final todayDate = DateTime(
        today.year,
        today.month,
        today.day,
      );

      return targetDate.isBefore(todayDate);
    } catch (_) {
      return false;
    }
  }


  Future<void> _deleteScheduleImmediately(String scheduleId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // 1. 삭제하려는 일정이 '삼성 캘린더' 등 외부 캘린더에서 연동된 일정인지 확인합니다.
      final targetSchedule = _allSchedules.firstWhere(
            (item) => item['doc_id']?.toString() == scheduleId,
        orElse: () => {},
      );

      final String source = targetSchedule['source'] ?? '';

      // 2. 외부 캘린더 일정인 경우 앱 내 삭제를 막고 삼성 캘린더에서 지우도록 안내 팝업을 띄웁니다.
      if (source == 'calendar') {
        if (mounted) {
          // UI 강제 리프레시(스와이프 슬라이드 복구용)
          setState(() {});

          showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: const Text(
                  "캘린더 일정 삭제 안내",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                content: const Text(
                  "삼성 캘린더 연동 일정은 삼성 캘린더 앱에서 삭제해 주세요.",
                  style: TextStyle(fontSize: 14, color: Colors.black87),
                ),
                actions: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: pointColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text("확인", style: TextStyle(color: Colors.white)),
                  ),
                ],
              );
            },
          );
        }
        return; // 파이어스토어 및 로컬 삭제 로직 실행 중단
      }

      // 3. 일반 앱 내 생성 일정인 경우 정상적으로 파이어스토어에서 삭제합니다.
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('schedules')
          .doc(scheduleId)
          .delete();

      if (mounted) {
        setState(() {
          _allSchedules.removeWhere((item) => item['doc_id']?.toString() == scheduleId);
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('일정이 삭제되었습니다.')),
      );
    } catch (e) {
      debugPrint("일정 삭제 오류 : $e");
    }
  }


  String _normalizeTime(String time) {
    final t = time.trim();
    if (RegExp(r'^\d{1,2}:\d{2}$').hasMatch(t)) {
      final parts = t.split(':');
      return "${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}";
    }
    if (RegExp(r'^\d{3,4}$').hasMatch(t)) {
      final padded = t.padLeft(4, '0');
      return "${padded.substring(0, 2)}:${padded.substring(2, 4)}";
    }
    return t;
  }


  @override
  Widget build(BuildContext context) {
    final User? currentUser = FirebaseAuth.instance.currentUser;
    final String uid = currentUser?.uid ?? "current_user";
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final Color backgroundColor =
    isDark ? const Color(0xFF121212) : const Color(0xFFF0F4F8);

    final Color cardColor =
    isDark ? const Color(0xFF1E1E1E) : Colors.white;

    final Color primaryText =
    isDark ? Colors.white : const Color(0xFF111827);

    final Color secondaryText =
    isDark ? Colors.white70 : Colors.grey.shade600;

    final Color lightCard =
    isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF7F8FA);

    return Scaffold(
      key: _scaffoldKey,
      drawer: const AppDrawer(),
      backgroundColor: backgroundColor,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          // 하단 탭바와 FloatingActionButton 영역을 고려하여 충분한 여백 확보
          padding: const EdgeInsets.only(bottom: 140),
          child: Column(
            children: [
              _buildAppBar(),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Row(
                  children: [
                    _buildPointDisplay(uid),
                  ],
                ),
              ),

              const SizedBox(height: 4),

              SizedBox(
                height: 235,
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      _displayDate = _baseDate.add(
                        Duration(days: index - 1000),
                      );
                    });
                  },
                  itemBuilder: (context, index) {
                    final date = _baseDate.add(
                      Duration(days: index - 1000),
                    );

                    return _buildDynamicUpperCard(uid, date);
                  },
                ),
              ),

              const SizedBox(height: 8),

              // 하단 흰색 바탕 카드 컨테이너
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(32),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 4,
                            height: 20,
                            decoration: BoxDecoration(
                              color: pointColor,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 9),
                          Text(
                            _getDateTitle(_displayDate),
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF202A31),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      _buildScheduleTimeline(
                        uid,
                        _displayDate,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildPointDisplay(String uid) {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color cardColor =
    isDark ? const Color(0xFF1E1E1E) : Colors.white;

    final Color pointTextColor =
    isDark
        ? const Color(0xFFFFB74D)
        : const Color(0xFFE58B00);

    final Color shadowColor =
    isDark
        ? Colors.black.withOpacity(0.30)
        : Colors.black.withOpacity(0.035);

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('user_profile')
          .doc('current')
          .snapshots(),
      builder: (context, snapshot) {
        int points = 0;
        int streak = 0;

        if (snapshot.hasData && snapshot.data!.exists) {
          final profile = snapshot.data!.data() as Map<String, dynamic>?;

          points = profile?['point'] ?? 0;
          streak = profile?['current_streak'] ?? 0;
          final String lastAttendance = profile?['last_attendance_date']?.toString() ?? '';
          final String todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

          // 오늘 아직 출석 처리가 되지 않은 경우 study_sessions 조회하여 판단
          if (lastAttendance != todayStr) {
            FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .collection('study_sessions')
                .where('date', isEqualTo: todayStr)
                .where('is_success', isEqualTo: true)
                .get()
                .then((querySnapshot) {
              int totalStudyMinutes = 0;

              for (var doc in querySnapshot.docs) {
                final data = doc.data();
                totalStudyMinutes += (data['study_minutes'] as num?)?.toInt() ?? 0;
              }

              // 오늘 성공한 총 공부 시간이 60분 이상일 때 연속 출석 인정
              if (totalStudyMinutes >= 60) {
                final String yesterdayStr = DateFormat('yyyy-MM-dd')
                    .format(DateTime.now().subtract(const Duration(days: 1)));

                final int updatedStreak = (lastAttendance == yesterdayStr) ? streak + 1 : 1;

                FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .collection('user_profile')
                    .doc('current')
                    .set({
                  'current_streak': updatedStreak,
                  'last_attendance_date': todayStr,
                }, SetOptions(merge: true));
              }
            });
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
                    color: Colors.orange.withOpacity(0.12),
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
                        color: Colors.orange.withOpacity(0.11),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.stars_rounded,
                        color: Colors.orange,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      '$points P',
                      style: TextStyle(
                        color: pointTextColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // 불 아이콘 및 연속 출석일 표시 영역
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 13,
                vertical: 9,
              ),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.deepOrange.withOpacity(0.12),
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
                      color: Colors.deepOrange.withOpacity(0.11),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.local_fire_department_rounded,
                      color: Colors.deepOrange,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    '$streak일',
                    style: TextStyle(
                      color: isDark
                          ? const Color(0xFFFF8A65)
                          : const Color(0xFFD84315),
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
  Widget _buildAppBar() {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color cardColor =
    isDark ? const Color(0xFF1E1E1E) : Colors.white;

    final Color iconColor =
    isDark
        ? Colors.white
        : const Color(0xFF39454D);

    final Color titleColor =
    isDark
        ? Colors.white
        : const Color(0xFF303B43);

    final Color shadowColor =
    isDark
        ? Colors.black.withOpacity(0.30)
        : Colors.black.withOpacity(0.045);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        20,
        12,
        20,
        4,
      ),
      child: SizedBox(
        height: 54,
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius:
                BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: shadowColor,
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: _openDrawer,
                icon: Icon(
                  Icons.menu_rounded,
                  size: 23,
                  color: iconColor,
                ),
              ),
            ),

            Expanded(
              child: Center(
                child: RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: "STAY",
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius:
                BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: shadowColor,
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                      const ReportHistoryPage(),
                    ),
                  );
                },
                icon: Icon(
                  Icons.mail_outline_rounded,
                  size: 22,
                  color: iconColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildDynamicUpperCard(String uid, DateTime date) {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final targetDate = DateTime(date.year, date.month, date.day);

    // 과거 날짜
    if (targetDate.isBefore(todayDate)) {
      return _buildEmptyCard(date);
    }

    final validSchedules = _allSchedules.where((item) {
      // ============================================================
      // ★ 이미 처리된 일정은 무조건 제외
      // ============================================================

      final String status =
          item['status']?.toString().trim().toLowerCase() ?? '';

      final bool isFailed =
          status == 'failed' ||
              status == 'cancelled' ||
              status == 'give_up' ||
              status == 'given_up' ||
              status == 'abandoned' ||
              status == 'deleted';

      final bool isCompleted =
          status == 'completed' ||
              status == 'success';

      final bool isFinished =
          item['isFinished'] == true ||
              item['is_finished'] == true;

      final bool isNotSuccess =
          item['is_success'] == false ||
              item['isSuccess'] == false;

      // 포기 / 실패 / 취소 / 삭제 / 완료된 일정은
      // NEXT FOCUS에 절대 다시 나오지 않음
      if (isFailed ||
          isCompleted ||
          isFinished ||
          isNotSuccess) {
        return false;
      }

      final rawTime =
          item['start_datetime'] ?? item['start_time'];

      final start = _parseScheduleDateTime(
        rawTime,
        dateStr:
        item['date_str']?.toString() ?? dateStr,
      );

      if (start == null) return false;

      final scheduleDate =
      DateTime(start.year, start.month, start.day);

      if (DateFormat('yyyy-MM-dd').format(scheduleDate) !=
          dateStr) {
        return false;
      }

      // ============================================================
      // 종료 시간이 지난 일정 제외
      // ============================================================

      final dynamic endValue =
          item['end_time'] ??
              item['end_datetime'] ??
              item['endTime'] ??
              item['endtime'];

      final endTime = _parseScheduleDateTime(
        endValue,
        dateStr: dateStr,
      );

      if (endTime != null && now.isAfter(endTime)) {
        return false;
      }

      return true;
    }).toList();

    if (validSchedules.isEmpty) {
      return _buildEmptyCard(date);
    }

    validSchedules.sort((a, b) {
      final aRawTime =
          a['start_datetime'] ?? a['start_time'];

      final bRawTime =
          b['start_datetime'] ?? b['start_time'];

      final aTime =
          _parseScheduleDateTime(
            aRawTime,
            dateStr:
            a['date_str']?.toString() ?? dateStr,
          ) ??
              DateTime(2099);

      final bTime =
          _parseScheduleDateTime(
            bRawTime,
            dateStr:
            b['date_str']?.toString() ?? dateStr,
          ) ??
              DateTime(2099);

      return aTime.compareTo(bTime);
    });

    return _buildNextTaskModeCard(
      validSchedules.first,
    );
  }

  // 1. 누락되었던 _buildNextTaskModeCard 메서드 추가
  Widget _buildNextTaskModeCard(
      Map<String, dynamic> schedule,
      ) {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color cardColor =
    isDark ? const Color(0xFF1E1E1E) : Colors.white;

    final Color titleColor =
    isDark ? Colors.white : const Color(0xFF111827);

    final Color subTextColor =
    isDark ? Colors.white70 : Colors.grey.shade600;

    final Color timeBackground =
    isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF7F8FA);

    final Color timeIconColor =
    isDark ? Colors.white60 : Colors.grey.shade500;

    final String title =
        schedule['title']?.toString() ?? '공부';

    final String locationName =
    schedule['place_name']
        ?.toString()
        .trim()
        .isNotEmpty ==
        true
        ? schedule['place_name'].toString()
        : schedule['location_name']
        ?.toString()
        .trim()
        .isNotEmpty ==
        true
        ? schedule['location_name'].toString()
        : '장소 미지정';

    final DateTime? startTime =
    _parseScheduleDateTime(
      schedule['start_time'] ??
          schedule['start_datetime'],
      dateStr:
      schedule['date_str']?.toString(),
    );

    final DateTime? endTime =
    _parseScheduleDateTime(
      schedule['end_time'] ??
          schedule['end_datetime'],
      dateStr:
      schedule['date_str']?.toString(),
    );

    final String startTimeStr =
    startTime != null
        ? DateFormat('HH:mm').format(startTime)
        : '--:--';

    final String endTimeStr =
    endTime != null
        ? DateFormat('HH:mm').format(endTime)
        : '--:--';

    final Color dynamicCardColor =
    _parseColor(schedule);

    // 공통 처리 함수 (포기/완료 일정 검증)
    bool checkScheduleStatusAndNotify() {
      final String status =
          schedule['status']
              ?.toString()
              .trim()
              .toLowerCase() ??
              '';

      final bool isFailed =
          status == 'failed' ||
              status == 'cancelled' ||
              status == 'give_up' ||
              status == 'given_up' ||
              status == 'abandoned' ||
              status == 'deleted';

      final bool isCompleted =
          status == 'completed' ||
              status == 'success';

      final bool isFinished =
          schedule['isFinished'] == true ||
              schedule['is_finished'] == true;

      final bool isNotSuccess =
          schedule['is_success'] == false ||
              schedule['isSuccess'] == false;

      if (isFailed ||
          isCompleted ||
          isFinished ||
          isNotSuccess) {
        debugPrint(
          '🚫 포기/처리된 일정 → TimerPage 이동 차단',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('이미 포기하거나 완료한 일정입니다.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return false;
      }
      return true;
    }

    return GestureDetector(
      onTap: () async {
        // 카드 바탕 클릭 시: 장소 선택/변경 지도 이동
        if (!checkScheduleStatusAndNotify()) return;
        await _navigateToTimer(schedule, startNow: false);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(
                isDark ? 0.35 : 0.05,
              ),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color:
              dynamicCardColor.withOpacity(0.08),
              blurRadius: 30,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            children: [
              Positioned(
                right: -35,
                top: -45,
                child: Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                    dynamicCardColor.withOpacity(0.06),
                  ),
                ),
              ),

              Positioned(
                left: 0,
                top: 24,
                bottom: 24,
                child: Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: dynamicCardColor,
                    borderRadius:
                    const BorderRadius.only(
                      topRight: Radius.circular(5),
                      bottomRight:
                      Radius.circular(5),
                    ),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(
                  22,
                  20,
                  22,
                  20,
                ),
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment:
                      MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding:
                          const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color:
                            dynamicCardColor
                                .withOpacity(0.1),
                            borderRadius:
                            BorderRadius.circular(8),
                          ),
                          child: Text(
                            'NEXT FOCUS',
                            style: TextStyle(
                              color:
                              dynamicCardColor,
                              fontSize: 10,
                              fontWeight:
                              FontWeight.w900,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),

                        Container(
                          padding:
                          const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: timeBackground,
                            borderRadius:
                            BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize:
                            MainAxisSize.min,
                            children: [
                              Icon(
                                Icons
                                    .access_time_rounded,
                                size: 13,
                                color:
                                timeIconColor,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '$startTimeStr ~ $endTimeStr',
                                style: TextStyle(
                                  color:
                                  subTextColor,
                                  fontSize: 12,
                                  fontWeight:
                                  FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    Text(
                      title,
                      maxLines: 2,
                      overflow:
                      TextOverflow.ellipsis,
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.6,
                        height: 1.2,
                      ),
                    ),

                    const SizedBox(height: 14),

                    Row(
                      crossAxisAlignment:
                      CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(
                                Icons
                                    .location_on_rounded,
                                size: 16,
                                color:
                                dynamicCardColor,
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  locationName,
                                  maxLines: 1,
                                  overflow:
                                  TextOverflow
                                      .ellipsis,
                                  style: TextStyle(
                                    color:
                                    subTextColor,
                                    fontSize: 13,
                                    fontWeight:
                                    FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 12),

                        // ★ 시작하기 버튼 (GestureDetector로 감싸 바로 시작)
                        GestureDetector(
                          onTap: () async {
                            if (!checkScheduleStatusAndNotify()) return;
                            await _navigateToTimer(schedule, startNow: true);
                          },
                          child: Container(
                            height: 44,
                            padding:
                            const EdgeInsets.symmetric(
                              horizontal: 20,
                            ),
                            decoration: BoxDecoration(
                              color:
                              dynamicCardColor,
                              borderRadius:
                              BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                  dynamicCardColor
                                      .withOpacity(0.3),
                                  blurRadius: 10,
                                  offset:
                                  const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize:
                              MainAxisSize.min,
                              children: const [
                                Text(
                                  '시작하기',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight:
                                    FontWeight.w900,
                                  ),
                                ),
                                SizedBox(width: 6),
                                Icon(
                                  Icons
                                      .arrow_forward_rounded,
                                  color: Colors.white,
                                  size: 15,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  bool _isExpiredSchedule(Map<String, dynamic> item) {
    try {
      final dateStr = item['date_str']?.toString() ?? '';
      final endTime = item['end_time']?.toString() ?? '';

      if (dateStr.isEmpty || endTime.isEmpty) {
        return false;
      }

      final endDateTime = DateFormat(
        'yyyy-MM-dd HH:mm',
      ).parse('$dateStr $endTime');

      return endDateTime.isBefore(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  Widget _buildEmptyCard(DateTime date) {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color cardColor =
    isDark ? const Color(0xFF1E1E1E) : Colors.white;

    final Color textColor =
    isDark
        ? Colors.white70
        : const Color(0xFF7B8790);

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              isDark ? 0.30 : 0.045,
            ),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment:
          MainAxisAlignment.center,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: pointColor.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.event_available_rounded,
                color: pointColor,
                size: 27,
              ),
            ),
            const SizedBox(height: 13),
            Text(
              "일정이 없습니다.",
              style: TextStyle(
                color: textColor,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }// 🛠️ [타임라인 복구 완료]: 온전한 매듭 닫기 구성


  Future<void> completeStudySession({
    required String sessionId,
    required String scheduleId,
    required int studyMinutes,
    required bool isSuccess,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final uid = user.uid;

    final firestore = FirebaseFirestore.instance;

    final sessionRef = firestore
        .collection('users')
        .doc(uid)
        .collection('study_sessions')
        .doc(sessionId);

    final profileRef = firestore
        .collection('users')
        .doc(uid)
        .collection('user_profile')
        .doc('current');

    final scheduleRef = scheduleId.isNotEmpty
        ? firestore
        .collection('users')
        .doc(uid)
        .collection('schedules')
        .doc(scheduleId)
        : null;

    try {
      await firestore.runTransaction((transaction) async {
        // 1. 기존 프로필 정보 가져오기
        final profileSnap = await transaction.get(profileRef);

        final profileData =
            profileSnap.data() as Map<String, dynamic>? ?? {};

        final int currentPoints =
            (profileData['point'] as num?)?.toInt() ?? 0;

        final int currentStreak =
            (profileData['current_streak'] as num?)?.toInt() ?? 0;

        final String lastAttendanceDate =
            profileData['last_attendance_date']?.toString() ?? '';

        final DateTime now = DateTime.now();

        final String todayStr =
        DateFormat('yyyy-MM-dd').format(now);

        final String yesterdayStr =
        DateFormat('yyyy-MM-dd')
            .format(now.subtract(const Duration(days: 1)));

        // 2. 공부 성공 시 포인트 계산
        final int earnedPoints =
        isSuccess ? studyMinutes * 10 : 0;

        // 3. 공부 기록 업데이트
        transaction.set(
          sessionRef,
          {
            'study_minutes': studyMinutes,
            'is_success': isSuccess,
            'is_failed': !isSuccess,
            'arrival_verified': true,
            'end_time': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        // 4. 연결된 일정 상태 업데이트
        if (scheduleRef != null) {
          transaction.update(
            scheduleRef,
            {
              'status': isSuccess ? 'completed' : 'failed',
            },
          );
        }

        // 5. 출석 처리
        int updatedStreak = currentStreak;
        String updatedLastAttendance = lastAttendanceDate;

        // 60분 이상 성공적으로 완료했을 때만 출석 인정
        if (isSuccess && studyMinutes >= 60) {
          // 오늘 이미 출석 완료한 경우 중복 증가하지 않음
          if (lastAttendanceDate == todayStr) {
            updatedStreak = currentStreak;
          }

          // 어제 출석했다면 연속 출석 +1
          else if (lastAttendanceDate == yesterdayStr) {
            updatedStreak = currentStreak + 1;
          }

          // 하루라도 빠졌거나 첫 출석이면 1일로 초기화
          else {
            updatedStreak = 1;
          }

          updatedLastAttendance = todayStr;
        }

        // 6. 프로필 정보 업데이트
        transaction.set(
          profileRef,
          {
            'point': currentPoints + earnedPoints,
            'points': currentPoints + earnedPoints,
            'current_streak': updatedStreak,
            'last_attendance_date': updatedLastAttendance,
            'updated_at': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });

      debugPrint(
        '✅ 공부 기록 및 출석 처리 완료\n'
            '공부 시간: $studyMinutes분\n'
            '성공 여부: $isSuccess',
      );
    } catch (e, stackTrace) {
      debugPrint('❌ 공부 기록 및 출석 처리 오류: $e');
      debugPrint('$stackTrace');
    }
  }

  Widget _buildScheduleItem(
      String uid,
      String dateStr,
      String docId,
      Map<String, dynamic> data,
      ) {
    final String status =
        data['status']?.toString() ?? '';

    final bool isCompleted =
        status == 'completed' ||
            status == 'success' ||
            data['isFinished'] == true ||
            data['is_finished'] == true;

    final bool isCancelled =
        status == 'cancelled' ||
            status == 'failed' ||
            status == 'deleted';

    final bool isPastDate =
    _isPastScheduleDate(data);

    final bool isExpired =
    _isExpiredSchedule(data);

    final bool isProcessed =
        isCompleted ||
            isCancelled ||
            isPastDate ||
            isExpired;

    final String displayName =
    (data['location_name'] != null &&
        data['location_name']
            .toString()
            .trim()
            .isNotEmpty)
        ? data['location_name'].toString()
        : '위치 미지정';

    final String displaySubject =
        data['title']?.toString() ?? '제목 없음';

    final Color accentColor =
    isProcessed
        ? Colors.grey
        : _parseColor(data);

    final Widget card = Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.grey.withOpacity(0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 5,
              height: 48,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      decoration: isProcessed
                          ? TextDecoration.lineThrough
                          : null,
                      color: isProcessed
                          ? Colors.grey
                          : const Color(0xFF2D3436),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 14,
                        color: Colors.grey.shade500,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${data['start_time'] ?? '--:--'} ~ '
                              '${data['end_time'] ?? '--:--'}  •  '
                              '$displaySubject',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isProcessed)
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  color: Colors.grey,
                  size: 18,
                ),
              ),
          ],
        ),
      ),
    );

    return Dismissible(
      key: Key(docId),
      direction: data['source']?.toString() == 'calendar'
          ? DismissDirection.none
          : DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        final String source =
            data['source']?.toString() ?? '';

        if (source == 'calendar') {
          return false;
        }

        return await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('일정 삭제 경고'),
              content: const Text(
                '해당 일정의 모든 기록이 지워지며,\n'
                    'AI 피드백에 반영되지 않습니다.',
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.pop(context, false),
                  child: const Text('취소'),
                ),
                ElevatedButton(
                  onPressed: () =>
                      Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                    Colors.redAccent,
                  ),
                  child: const Text(
                    '삭제',
                    style: TextStyle(
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            );
          },
        ) ??
            false;
      },
      onDismissed: (_) {
        _deleteScheduleImmediately(docId);
      },
      background: Container(
        margin: const EdgeInsets.only(bottom: 14),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.9),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(
          Icons.delete_outline,
          color: Colors.white,
          size: 28,
        ),
      ),

      // 처리된 일정은 InkWell/GestureDetector 자체를 제거.
      // 따라서 터치해도 아무것도 실행되지 않음.
      child: card,
    );
  }}