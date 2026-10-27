import 'dart:async';
import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'camera_timer_page.dart';
import 'map.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:timezone/timezone.dart' as tz;

const Color pointColor = Color(0xFF6FD0F1);
const Color bgGrey = Color(0xFFF4F6F8);
const Color cardWhite = Colors.white;

// 공통 컬러 팔레트 통일 (16가지 색상)
const List<Color> kAppPaletteColors = [
  Color(0xFF6FD0F1), // 하늘색 (제시됨)
  Color(0xFFE57373), // 파스텔 레드/코랄 (제시됨)
  Color(0xFF66BB6A), // 파스텔 그린 (제시됨)
  Color(0xFFFF9500), // 오렌지 (제시됨)
  Color(0xFF7986CB), // 인디고/블루그레이 (제시됨)
  Color(0xFF5856D6), // 딥퍼플/블루 (제시됨
  Color(0xFF4DB6AC), // 파스텔 틸/청록
  Color(0xFFBA68C8), // 밝은 퍼플/라벤더
  Color(0xFF81C784), // 연두빛 그린
  Color(0xFFFF8A65), // 피치/살구색
  Color(0xFFF06292), // 파스텔 핑크
];

class TimetablePage extends StatefulWidget {
  const TimetablePage({super.key});

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage>
    with TickerProviderStateMixin {
  int _dataVersion = 0;
  final Map<String, int> _deviceEventColorCache = {};
  static const Color _mainStayColor = Color(0xFF6FD0F1);
  static const double _hourHeight = 50.0;
  static const double _timeColumnWidth = 45.0;
  static const int _initialPage = 1000;

  late PageController _pageController;
  late ScrollController _verticalScrollController;

  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance;

  final DeviceCalendarPlugin _calendarPlugin =
  DeviceCalendarPlugin();

  final List<Map<String, dynamic>>
  _deviceCalendarAllDay = [];

  final List<Map<String, dynamic>>
  _deviceCalendarTimed = [];

  String? uid;

  late DateTime _baseMonday;

  DateTime _currentBaseMonday =
  DateTime.now().subtract(
    Duration(days: DateTime.now().weekday - 1),
  );

  DateTime _getWeekStart(DateTime date) {
    final normalized = DateTime(
      date.year,
      date.month,
      date.day,
    );

    return normalized.subtract(
      Duration(days: normalized.weekday - 1),
    );
  }
  List<int> _selectedRepeatDays = []; // 1: 월, 2: 화, ..., 7: 일
  DateTime? _repeatEndDate; // 반복 종료 날짜

  // 전역으로 통일된 kAppPaletteColors 사용
  final List<Color> _availableColors = kAppPaletteColors;


  DateTime _normalizeEventTime(DateTime dateTime) {
    return tz.TZDateTime.from(
      dateTime,
      tz.getLocation('Asia/Seoul'),
    );
  }

  @override
  void initState() {
    super.initState();
    Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) _checkAndStartTimer();
    });
    uid = FirebaseAuth.instance.currentUser?.uid;

    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));

    _baseMonday = _getWeekStart(DateTime.now());
    _currentBaseMonday = _baseMonday;

    _pageController = PageController(initialPage: _initialPage);
    _verticalScrollController = ScrollController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSamsungCalendarEvents(_currentBaseMonday);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (uid != null && _deviceCalendarTimed.isEmpty) {
      _loadSamsungCalendarEvents(_currentBaseMonday);
    }
  }

  /// 제목별로 실제 배정된 색상을 저장
  final Map<String, Color> _titleColorCache = {};

  /// 일정 제목을 비교하기 위한 정규화
  String _normalizeEventTitle(String text) {
    return text
        .replaceAll(
      RegExp(
        r'(오전|오후)?\s*\d{1,2}\s*(:\s*\d{2}|시(\s*\d{1,2}\s*분)?)',
        caseSensitive: false,
      ),
      '',
    )
        .replaceAll(
      RegExp(r'\d{1,4}[-./]\d{1,2}[-./]\d{1,4}'),
      '',
    )
        .replaceAll(
      RegExp(r'[\(\[\{]\s*\d{1,2}\s*:\s*\d{2}\s*[\)\]\}]'),
      '',
    )
        .replaceAll(
      RegExp(r'[^\w\sㄱ-ㅎㅏ-ㅣ가-힣]'),
      '',
    )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
  }

  bool _isTitleSimilar(String title1, String title2) {
    final t1 = _normalizeEventTitle(title1);
    final t2 = _normalizeEventTitle(title2);

    if (t1.isEmpty || t2.isEmpty) {
      return title1.trim().toLowerCase() == title2.trim().toLowerCase();
    }

    if (t1 == t2) {
      return true;
    }

    final minLen = math.min(t1.length, t2.length);

    if (minLen >= 3) {
      if (t1.contains(t2) || t2.contains(t1)) {
        return true;
      }
    }

    final words1 = t1
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toSet();

    final words2 = t2
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toSet();

    if (words1.isNotEmpty && words2.isNotEmpty) {
      final intersection = words1.intersection(words2);

      for (final word in intersection) {
        if (word.length >= 2) {
          return true;
        }
      }
    }

    final maxLen = math.max(t1.length, t2.length);

    if (maxLen == 0) {
      return true;
    }

    final distance = _levenshteinDistance(t1, t2);
    final similarity = (maxLen - distance) / maxLen;

    return similarity >= 0.6;
  }

  int _levenshteinDistance(String s1, String s2) {
    if (s1 == s2) {
      return 0;
    }

    if (s1.isEmpty) {
      return s2.length;
    }

    if (s2.isEmpty) {
      return s1.length;
    }

    List<int> previous =
    List<int>.generate(s2.length + 1, (index) => index);

    List<int> current =
    List<int>.filled(s2.length + 1, 0);

    for (int i = 0; i < s1.length; i++) {
      current[0] = i + 1;

      for (int j = 0; j < s2.length; j++) {
        final cost = s1[i] == s2[j] ? 0 : 1;

        current[j + 1] = math.min(
          current[j] + 1,
          math.min(
            previous[j + 1] + 1,
            previous[j] + cost,
          ),
        );
      }

      final temp = previous;
      previous = current;
      current = temp;
    }

    return previous[s2.length];
  }

  Color _generateColorFromTitle(
      String title, [
        List<String>? existingTitles,
      ]) {
    if (title.trim().isEmpty) {
      return _mainStayColor;
    }

    final normalizedTitle = _normalizeEventTitle(title);

    if (normalizedTitle.isEmpty) {
      return _mainStayColor;
    }

    if (_titleColorCache.containsKey(normalizedTitle)) {
      return _titleColorCache[normalizedTitle]!;
    }

    for (final entry in _titleColorCache.entries) {
      if (_isTitleSimilar(normalizedTitle, entry.key)) {
        _titleColorCache[normalizedTitle] = entry.value;
        return entry.value;
      }
    }

    if (existingTitles != null) {
      for (final existingTitle in existingTitles) {
        final normalizedExisting =
        _normalizeEventTitle(existingTitle);

        if (normalizedExisting.isEmpty) {
          continue;
        }

        if (_isTitleSimilar(normalizedTitle, normalizedExisting)) {
          final existingColor =
          _titleColorCache[normalizedExisting];

          if (existingColor != null) {
            _titleColorCache[normalizedTitle] = existingColor;
            return existingColor;
          }
        }
      }
    }

    int hash = 0;

    for (final codeUnit in normalizedTitle.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0xFFFFFFFF;
    }

    final color =
    kAppPaletteColors[hash.abs() % kAppPaletteColors.length];

    _titleColorCache[normalizedTitle] = color;

    return color;
  }

  int _toColorInt(
      dynamic v, [
        String? title,
        List<String>? existingTitles,
      ]) {
    if (v != null) {
      if (v is int) {
        return v;
      }

      if (v is String) {
        if (v.startsWith('0x')) {
          final parsed = int.tryParse(v);

          if (parsed != null) {
            return parsed;
          }
        }

        final parsed = int.tryParse(v);

        if (parsed != null) {
          return parsed;
        }
      }

      if (v is Color) {
        return v.value;
      }
    }

    if (title != null && title.trim().isNotEmpty) {
      return _generateColorFromTitle(
        title,
        existingTitles,
      ).value;
    }

    return _mainStayColor.value;
  }

  Color _color(dynamic v, [String? title]) => Color(_toColorInt(v, title));
  @override
  void dispose() {
    _pageController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  String _p(int n) => n.toString().padLeft(2, '0');
  String _dateStr(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
  DateTime _getDateFromIdx(int idx) {
    return _baseMonday.add(Duration(days: (idx - _initialPage) * 7));
  }

  double? _readScheduleCoordinate(dynamic value) {
    if (value == null) return null;

    if (value is num) {
      final double result = value.toDouble();
      return result.isFinite ? result : null;
    }

    final double? result = double.tryParse(
      value.toString().trim(),
    );

    if (result == null || !result.isFinite) {
      return null;
    }

    return result;
  }

  DateTime? _parseScheduleDateTimeForRoot(
      dynamic value,
      String dateStr,
      ) {
    if (value == null) return null;

    if (value is DateTime) {
      return value;
    }

    if (value is Timestamp) {
      return value.toDate();
    }

    final String raw = value.toString().trim();

    if (raw.isEmpty) return null;

    // ISO 형식
    final DateTime? isoDateTime = DateTime.tryParse(raw);

    if (isoDateTime != null) {
      return isoDateTime;
    }

    // HH:mm 또는 HH:mm:ss
    final RegExp timeRegex = RegExp(
      r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$',
    );

    final match = timeRegex.firstMatch(raw);

    if (match == null) {
      return null;
    }

    final int hour =
        int.tryParse(match.group(1) ?? '') ?? 0;

    final int minute =
        int.tryParse(match.group(2) ?? '') ?? 0;

    final int second =
        int.tryParse(match.group(3) ?? '') ?? 0;

    final DateTime? baseDate =
    DateTime.tryParse(dateStr);

    if (baseDate == null) {
      return null;
    }

    return DateTime(
      baseDate.year,
      baseDate.month,
      baseDate.day,
      hour,
      minute,
      second,
    );
  }


  void _checkAndStartTimer() {
    final DateTime now = DateTime.now();
    final String todayStr = _dateStr(now);

    final todaySchedules = _deviceCalendarTimed.where(
          (schedule) =>
      schedule['dateStr']?.toString() == todayStr,
    );

    for (final schedule in todaySchedules) {
      final dynamic startValue =
          schedule['start_time'] ??
              schedule['start_datetime'] ??
              schedule['startTime'] ??
              schedule['starttime'];

      final DateTime? startTime =
      _parseScheduleDateTimeForRoot(
        startValue,
        todayStr,
      );

      if (startTime == null) {
        continue;
      }

      // 현재 시간의 "분"과 일치하는 일정만 실행
      final bool isSameMinute =
          startTime.year == now.year &&
              startTime.month == now.month &&
              startTime.day == now.day &&
              startTime.hour == now.hour &&
              startTime.minute == now.minute;

      if (!isSameMinute) {
        continue;
      }

      final String scheduleId =
          schedule['calendar_event_id']?.toString() ??
              schedule['docId']?.toString() ??
              schedule['doc_id']?.toString() ??
              schedule['eventId']?.toString() ??
              schedule['event_id']?.toString() ??
              '';

      if (scheduleId.isEmpty) {
        continue;
      }

      final int duration =
          int.tryParse(
            schedule['duration_minutes']?.toString() ?? '',
          ) ??
              int.tryParse(
                schedule['durationMinutes']?.toString() ?? '',
              ) ??
              int.tryParse(
                schedule['target_minutes']?.toString() ?? '',
              ) ??
              int.tryParse(
                schedule['targetMinutes']?.toString() ?? '',
              ) ??
              60;

      final double? latitude =
          _readScheduleCoordinate(
            schedule['place_lat'],
          ) ??
              _readScheduleCoordinate(
                schedule['placeLat'],
              ) ??
              _readScheduleCoordinate(
                schedule['lat'],
              ) ??
              _readScheduleCoordinate(
                schedule['gps_lat'],
              ) ??
              _readScheduleCoordinate(
                schedule['gpsLat'],
              ) ??
              _readScheduleCoordinate(
                schedule['latitude'],
              );

      final double? longitude =
          _readScheduleCoordinate(
            schedule['place_lng'],
          ) ??
              _readScheduleCoordinate(
                schedule['placeLng'],
              ) ??
              _readScheduleCoordinate(
                schedule['lng'],
              ) ??
              _readScheduleCoordinate(
                schedule['gps_lng'],
              ) ??
              _readScheduleCoordinate(
                schedule['gpsLng'],
              ) ??
              _readScheduleCoordinate(
                schedule['longitude'],
              );

      final String title =
          schedule['title']?.toString() ??
              schedule['name']?.toString() ??
              '공부';

      final DateTime? endTime =
      _parseScheduleDateTimeForRoot(
        schedule['end_time'] ??
            schedule['end_datetime'] ??
            schedule['endTime'] ??
            schedule['endtime'],
        todayStr,
      );

      debugPrint('======================================');
      debugPrint('🚀 캘린더 → CameraTimerPage');
      debugPrint('sessionId : $scheduleId');
      debugPrint('title     : $title');
      debugPrint('duration  : $duration');
      debugPrint('startTime : $startTime');
      debugPrint('endTime   : $endTime');
      debugPrint('latitude  : $latitude');
      debugPrint('longitude : $longitude');
      debugPrint('======================================');

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CameraTimerPage(
            sessionId: scheduleId,
            initialLat: latitude,
            initialLng: longitude,
            durationMinutes: duration,
            startTime: startTime,
            endTime: endTime,
            title: title,
            forceMode: true,
          ),
        ),
      );

      // 같은 분에 여러 번 실행되지 않도록 기존 동작 유지
      break;
    }
  }


  void _openScheduleDetail(
      Map<String, dynamic> data,
      ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return ScheduleDetailSheet(
          schedule: data,
          onUpdated: () async {
            await _loadSamsungCalendarEvents(
              _currentBaseMonday,
            );

            if (!mounted) return;

            setState(() {
              _dataVersion++;
            });
          },
        );
      },
    );
  }


  Future<void> _showManualTimetableSheet() async {
    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return const _TimetableAddSheet();
      },
    );

    if (result != true) {
      return;
    }

    await _loadSamsungCalendarEvents(
      _currentBaseMonday,
    );

    if (!mounted) return;

    setState(() {
      _dataVersion++;
    });
  }

  Future<void> _loadSamsungCalendarEvents(DateTime targetMonday) async {
    try {
      final permission = await _calendarPlugin.requestPermissions();
      if (!(permission.data ?? false)) return;

      final calendarsResult = await _calendarPlugin.retrieveCalendars();
      final calendars = calendarsResult.data;
      if (calendars == null) return;

      final allDay = <Map<String, dynamic>>[];
      final timed = <Map<String, dynamic>>[];

      final startDate = targetMonday;
      final endDate = targetMonday.add(const Duration(days: 7));

      // 1. 성능 최적화: 유저의 기존 스케줄 정보를 한 번만 비동기로 가져와 메모리에 맵핑
      final Map<String, DocumentSnapshot> existingDocsMap = {};
      if (uid != null) {
        final existingSnapshots = await _firestore
            .collection('users')
            .doc(uid)
            .collection('schedules')
            .get();

        for (final doc in existingSnapshots.docs) {
          final data = doc.data();
          if (data['calendar_event_id'] != null) {
            existingDocsMap[data['calendar_event_id'].toString()] = doc;
          }
        }
      }

      final batch = _firestore.batch();
      bool hasBatchWrites = false;

      for (final calendar in calendars) {
        final name = (calendar.name ?? "").toLowerCase();

        if (name.contains('holiday') ||
            name.contains('birthday') ||
            name.contains('공휴일') ||
            name.contains('생일') ||
            name.contains('korea')) {
          continue;
        }

        final eventsResult = await _calendarPlugin.retrieveEvents(
          calendar.id,
          RetrieveEventsParams(
            startDate: startDate,
            endDate: endDate,
          ),
        );

        final events = eventsResult.data;
        if (events == null) continue;

        for (final event in events) {
          if (event.start == null || event.end == null) continue;

          if (event.start!.isAfter(endDate) ||
              event.end!.isBefore(startDate)) {
            continue;
          }

          final start = _normalizeEventTime(event.start!);
          final end = _normalizeEventTime(event.end!);
          final title = (event.title ?? '').trim();

          final lowerTitle = title.toLowerCase();

          if (lowerTitle.contains('공휴일') ||
              lowerTitle.contains('대체') ||
              lowerTitle.contains('하지') ||
              lowerTitle.contains('단오') ||
              lowerTitle.contains('소서')) {
            continue;
          }

          final eventId = event.eventId ?? '';
          final dateStr = _dateStr(start);
          final startTime = "${_p(start.hour)}:${_p(start.minute)}";
          final endTime = "${_p(end.hour)}:${_p(end.minute)}";
          final durationMinutes = end.difference(start).inMinutes;

          if (event.allDay == true) {
            allDay.add({
              'calendar_event_id': eventId,
              'calendar_id': calendar.id,
              'is_device_calendar': true,
              'title': title,
              'start': start,
              'end': end,
              'startIndex': start.difference(targetMonday).inDays.clamp(0, 6),
              'endIndex': end.difference(targetMonday).inDays.clamp(0, 6),
            });
          } else {
            if (uid != null && eventId.isNotEmpty) {
              final docRef = _firestore
                  .collection('users')
                  .doc(uid)
                  .collection('schedules')
                  .doc(eventId);

              final existingDoc = existingDocsMap[eventId];

              if (existingDoc == null || !existingDoc.exists) {
                // 최초 등록일 때만 삼성 캘린더의 장소를 저장 (Batch 처리)
                batch.set(docRef, {
                  'title': title,
                  'subject': '',
                  'place_name': event.location ?? '',
                  'place_address': '',
                  'place_distance': null,
                  'target_minutes': durationMinutes > 0 ? durationMinutes : 60,
                  'start_datetime': '$dateStr $startTime:00',
                  'end_datetime': '$dateStr $endTime:00',
                  'force': false,
                  'place_lat': null,
                  'place_lng': null,
                  'calendar_event_id': eventId,
                  'calendar_id': calendar.id,
                  'is_calendar_sync': true,
                });
                hasBatchWrites = true;
              } else {
                // 이미 DB에 존재하는 일정은 장소를 덮어쓰지 않음 (Batch 처리)
                batch.set(docRef, {
                  'title': title,
                  'target_minutes': durationMinutes > 0 ? durationMinutes : 60,
                  'start_datetime': '$dateStr $startTime:00',
                  'end_datetime': '$dateStr $endTime:00',
                  'calendar_event_id': eventId,
                  'calendar_id': calendar.id,
                  'is_calendar_sync': true,
                }, SetOptions(merge: true));
                hasBatchWrites = true;
              }
            }

            timed.add({
              'calendar_event_id': eventId,
              'calendar_id': calendar.id,
              'is_device_calendar': true,
              'title': title,
              'dateStr': dateStr,
              'starttime': startTime,
              'endtime': endTime,
              'duration_minutes': durationMinutes > 0 ? durationMinutes : 60,
              'location_name': event.location ?? '',
            });
          }
        }
      }

      // 2. 누적된 데이터 일괄 커밋으로 로딩 속도 단축
      if (hasBatchWrites) {
        await batch.commit();
      }

      if (!mounted) return;

      setState(() {
        _deviceCalendarAllDay
          ..clear()
          ..addAll(allDay);

        _deviceCalendarTimed
          ..clear()
          ..addAll(timed);
      });
    } catch (e, stackTrace) {
      debugPrint("캘린더 오류: $e");
      debugPrint("$stackTrace");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (uid == null) {
      return const Scaffold(
        body: Center(
          child: Text("로그인 필요"),
        ),
      );
    }

    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color backgroundColor =
    isDark ? const Color(0xFF121212) : Colors.white;

    final Color appBarColor =
    isDark ? const Color(0xFF1E1E1E) : Colors.white;

    final Color primaryTextColor =
    isDark ? Colors.white : Colors.black;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: appBarColor,
        elevation: 0,
        title: Text(
          DateFormat('yyyy년 MM월').format(_currentBaseMonday),
          style: TextStyle(
            color: primaryTextColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.add,
              color: _mainStayColor,
            ),
            onPressed: _showManualTimetableSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildWeekdayHeader(),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (idx) {
                final newMonday = _getDateFromIdx(idx);

                setState(() {
                  _currentBaseMonday = newMonday;
                });

                _loadSamsungCalendarEvents(newMonday);
              },
              itemBuilder: (_, idx) =>
                  _buildGridScroll(_getDateFromIdx(idx)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekdayHeader() {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color normalTextColor =
    isDark ? Colors.white70 : Colors.black54;

    final Color dateTextColor =
    isDark ? Colors.white : Colors.black;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        children: [
          const SizedBox(
            width: _timeColumnWidth,
          ),
          ...List.generate(
            7,
                (i) {
              final day =
              _currentBaseMonday.add(
                Duration(days: i),
              );

              final labels = [
                '일',
                '월',
                '화',
                '수',
                '목',
                '금',
                '토',
              ];

              Color textColor = normalTextColor;

              if (i == 0) {
                textColor = Colors.red;
              } else if (i == 6) {
                textColor = Colors.blue;
              }

              return Expanded(
                child: Column(
                  children: [
                    Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 12,
                        color: textColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "${day.day}",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: dateTextColor,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }


  Widget _buildRepeatSummary() {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color textColor =
    isDark ? Colors.white : Colors.black87;

    if (_selectedRepeatDays.isEmpty) {
      return Text(
        '반복',
        style: TextStyle(
          fontSize: 16,
          color: textColor,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    const List<String> days = [
      '월',
      '화',
      '수',
      '목',
      '금',
      '토',
      '일',
    ];

    final String dayText = _selectedRepeatDays
        .map((day) => days[day - 1])
        .join(', ');

    final String endText = _repeatEndDate == null
        ? ''
        : ' ~ ${DateFormat('M월 d일').format(_repeatEndDate!)}';

    return Text(
      '매주 $dayText$endText',
      style: const TextStyle(
        fontSize: 16,
        color: _mainStayColor,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildGridScroll(DateTime monday) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('users')
          .doc(uid)
          .collection('schedules')
          .snapshots(),
      builder: (context, snapshot) {
        final List<Map<String, dynamic>> dbSchedules = [];

        if (snapshot.hasData) {
          final List<String> allTitles = snapshot.data!.docs
              .map((doc) => (doc.data() as Map<String, dynamic>)['title']?.toString().trim() ?? '')
              .where((t) => t.isNotEmpty)
              .toList();

          for (final doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;

            String dateStr = '';
            String startTime = '09:00';
            String endTime = '10:00';

            if (data['start_datetime'] is Timestamp) {
              final DateTime startDt = (data['start_datetime'] as Timestamp).toDate();
              final DateTime endDt = (data['end_datetime'] as Timestamp).toDate();
              dateStr = DateFormat('yyyy-MM-dd').format(startDt);
              startTime = DateFormat('HH:mm').format(startDt);
              endTime = DateFormat('HH:mm').format(endDt);
            } else if (data['start_datetime'] is String) {
              final startDtStr = data['start_datetime'].toString();
              final endDtStr = data['end_datetime']?.toString() ?? '';
              dateStr = startDtStr.isNotEmpty ? startDtStr.split(' ')[0] : '';
              startTime = startDtStr.contains(' ') ? startDtStr.split(' ')[1].substring(0, 5) : '09:00';
              endTime = endDtStr.contains(' ') ? endDtStr.split(' ')[1].substring(0, 5) : '10:00';
            } else if (data['dateStr'] != null) {
              dateStr = data['dateStr'];
              startTime = data['starttime'] ?? '09:00';
              endTime = data['endtime'] ?? '10:00';
            }

            int durationMinutes = data['target_minutes'] ?? 60;
            if (durationMinutes < 30) {
              durationMinutes = 30;
            }

            final title = data['title'] ?? '';
            final rawColor = data['color'] ?? data['ui_color'] ?? data['calendar_color'];

            // 유사한 제목은 같은 색상, 다른 일정은 겹치지 않게 팔레트 분산 적용
            final resolvedColor = _toColorInt(rawColor, title, allTitles);

            dbSchedules.add({
              ...data,
              'docId': doc.id,
              'dateStr': dateStr,
              'starttime': startTime,
              'endtime': endTime,
              'duration_minutes': durationMinutes,
              'ui_color': resolvedColor,
              'is_device_calendar': data['is_calendar_sync'] == true && data['calendar_event_id'] != null,
            });
          }
        }

        final weekDates = List.generate(7, (i) => _dateStr(monday.add(Duration(days: i))));
        final filteredDbSchedules = dbSchedules.where((s) => weekDates.contains(s['dateStr'])).toList();

        final List<String> timedTitles = [
          ...filteredDbSchedules.map((e) => e['title']?.toString() ?? ''),
          ..._deviceCalendarTimed.map((e) => e['title']?.toString() ?? ''),
        ].where((t) => t.isNotEmpty).toList();

        final processedDeviceCalendar = _deviceCalendarTimed.map((evt) {
          int duration = evt['duration_minutes'] ?? 60;
          if (duration < 30) {
            duration = 30;
          }

          final title = evt['title'] ?? '';
          final deviceColor = _toColorInt(evt['color'] ?? evt['ui_color'] ?? evt['calendar_color'], title, timedTitles);

          return {
            ...evt,
            'duration_minutes': duration,
            'ui_color': deviceColor,
          };
        }).toList();

        final dbCalendarEventIds = filteredDbSchedules
            .where((e) => e['calendar_event_id'] != null && e['calendar_event_id'].toString().isNotEmpty)
            .map((e) => e['calendar_event_id'].toString())
            .toSet();

        final dbKeys = filteredDbSchedules
            .map((e) => "${e['dateStr']}_${e['starttime']}_${e['title']}")
            .toSet();

        final List<Map<String, dynamic>> mergedSchedules = [
          ...filteredDbSchedules,
          ...processedDeviceCalendar.where((deviceEvt) {
            final devId = deviceEvt['calendar_event_id']?.toString() ?? '';
            final devKey = "${deviceEvt['dateStr']}_${deviceEvt['starttime']}_${deviceEvt['title']}";

            if (devId.isNotEmpty && dbCalendarEventIds.contains(devId)) return false;
            if (dbKeys.contains(devKey)) return false;
            return true;
          }),
        ];

        final contentHeight = 27 * _hourHeight;

        return SingleChildScrollView(
          controller: _verticalScrollController,
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: [
              _buildAllDayWeeklyBar(monday),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTimelineGuide(),
                  ...List.generate(7, (i) {
                    final targetDate = _dateStr(monday.add(Duration(days: i)));
                    final dayDocs = mergedSchedules.where((d) => d['dateStr'] == targetDate).toList();

                    return Expanded(
                      child: SizedBox(
                        height: contentHeight,
                        child: _buildDayStack(dayDocs),
                      ),
                    );
                  }),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  List<Map<String, dynamic>> _layoutDayEvents(List<Map<String, dynamic>> events) {
    final sorted = [...events]..sort((a, b) {
      final aStart = (a['starttime'] ?? "00:00").split(':');
      final bStart = (b['starttime'] ?? "00:00").split(':');
      final aMin = int.parse(aStart[0]) * 60 + int.parse(aStart[1]);
      final bMin = int.parse(bStart[0]) * 60 + int.parse(bStart[1]);
      return aMin.compareTo(bMin);
    });

    final List<List<Map<String, dynamic>>> lanes = [];

    for (final e in sorted) {
      final start = (e['starttime'] ?? "00:00").split(':');
      final end = (e['endtime'] ?? "00:00").split(':');
      final s = int.parse(start[0]) * 60 + int.parse(start[1]);
      final eMin = int.parse(end[0]) * 60 + int.parse(end[1]);

      bool placed = false;
      for (int i = 0; i < lanes.length; i++) {
        bool conflict = lanes[i].any((x) {
          final xs = (x['starttime'] ?? "00:00").split(':');
          final xe = (x['endtime'] ?? "00:00").split(':');
          final xsMin = int.parse(xs[0]) * 60 + int.parse(xs[1]);
          final xeMin = int.parse(xe[0]) * 60 + int.parse(xe[1]);
          return !((eMin <= xsMin) || (s >= xeMin));
        });

        if (!conflict) {
          lanes[i].add(e);
          e['lane'] = i;
          placed = true;
          break;
        }
      }

      if (!placed) {
        lanes.add([e]);
        e['lane'] = lanes.length - 1;
      }
    }
    return sorted;
  }

  List<Map<String, dynamic>> _layoutAllDayEvents(List<Map<String, dynamic>> events, DateTime monday) {
    final List<Map<String, dynamic>> normalized = [];

    for (final e in events) {
      final DateTime start = e['start'];
      final DateTime end = e['end'];
      int startOffset = start.difference(monday).inDays.clamp(0, 6);
      int endOffset = end.difference(monday).inDays.clamp(0, 6);
      normalized.add({...e, 'startIndex': startOffset, 'endIndex': endOffset});
    }

    normalized.sort((a, b) => a['startIndex'].compareTo(b['startIndex']));
    final List<List<Map<String, dynamic>>> lanes = [];

    for (final event in normalized) {
      bool placed = false;
      for (int i = 0; i < lanes.length; i++) {
        bool conflict = lanes[i].any((existing) =>
        !(event['endIndex'] < existing['startIndex'] || event['startIndex'] > existing['endIndex'])
        );

        if (!conflict) {
          event['lane'] = i;
          lanes[i].add(event);
          placed = true;
          break;
        }
      }
      if (!placed) {
        event['lane'] = lanes.length;
        lanes.add([event]);
      }
    }
    return normalized;
  }

  Widget _buildAllDayWeeklyBar(
      DateTime monday,
      ) {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color backgroundColor =
    isDark
        ? const Color(0xFF121212)
        : Colors.white;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double totalWidth =
            constraints.maxWidth;

        final double dayWidth =
            (totalWidth - _timeColumnWidth) / 7;

        final layout =
        _layoutAllDayEvents(
          _deviceCalendarAllDay,
          monday,
        );

        const double itemHeight = 22;
        const double gap = 4;

        int maxLane = 0;

        for (final e in layout) {
          final int lane = e['lane'] as int;

          if (lane > maxLane) {
            maxLane = lane;
          }
        }

        final double dynamicHeight =
        layout.isEmpty
            ? 0
            : ((maxLane + 1) *
            (itemHeight + gap)) +
            10;

        return Container(
          color: backgroundColor,
          child: SizedBox(
            height: dynamicHeight,
            child: Stack(
              children: layout.map(
                    (e) {
                  final int start =
                  e['startIndex'];

                  final int end =
                  e['endIndex'];

                  final int lane =
                      e['lane'] ?? 0;

                  final title =
                      e['title'] ?? "";

                  final colorVal =
                  _toColorInt(
                    e['ui_color'],
                    title,
                  );

                  return Positioned(
                    left:
                    _timeColumnWidth +
                        (start * dayWidth),
                    width:
                    ((end - start + 1) *
                        dayWidth) -
                        2.0,
                    top:
                    lane *
                        (itemHeight + gap),
                    height: itemHeight,
                    child: GestureDetector(
                      onTap: () =>
                          _openScheduleDetail(e),
                      child: Container(
                        decoration:
                        BoxDecoration(
                          color: Color(colorVal)
                              .withOpacity(0.9),
                          borderRadius:
                          BorderRadius.circular(
                            4,
                          ),
                        ),
                        padding:
                        const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        alignment:
                        Alignment.topLeft,
                        child: Text(
                          title,
                          maxLines: 3,
                          overflow:
                          TextOverflow.visible,
                          style:
                          const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight:
                            FontWeight.bold,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ).toList(),
            ),
          ),
        );
      },
    );
  }
  Widget _buildTimelineGuide() {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color timeTextColor =
    isDark ? Colors.white70 : Colors.grey[800]!;

    return Column(
      children: List.generate(
        24,
            (i) => Container(
          height: _hourHeight,
          width: _timeColumnWidth,
          alignment: Alignment.topCenter,
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            "${_p(i)}:00",
            style: TextStyle(
              fontSize: 11,
              color: timeTextColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
  Widget _buildDayStack(
      List<Map<String, dynamic>> dayDocs,
      ) {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color gridLineColor =
    isDark ? const Color(0xFF333333) : Colors.grey.shade100;

    final layouted = _layoutDayEvents(dayDocs);

    return LayoutBuilder(
      builder: (context, constraints) {
        final dayWidth = constraints.maxWidth;

        int maxLane = 0;

        for (final e in layouted) {
          final lane = e['lane'] ?? 0;

          if (lane > maxLane) {
            maxLane = lane;
          }
        }

        final totalLanes = maxLane + 1;

        return Stack(
          children: [
            Column(
              children: List.generate(
                24,
                    (i) => Container(
                  height: _hourHeight,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: gridLineColor,
                      ),
                      right: BorderSide(
                        color: gridLineColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ...layouted.map(
                  (data) {
                final start =
                (data['starttime'] ?? "00:00").split(':');

                final top = (double.parse(start[0]) +
                    double.parse(start[1]) / 60) *
                    _hourHeight;

                final durationMinutes =
                    data['duration_minutes'] ?? 60;

                final height =
                    (durationMinutes / 60.0) * _hourHeight;

                final lane = data['lane'] ?? 0;

                final itemWidth = dayWidth / totalLanes;

                final computedHeight =
                math.max(height - 2, 16.0);

                final title = data['title'] ?? "";

                final locationName = (data['place_name'] ??
                    data['location_name'] ??
                    data['location'] ??
                    '')
                    .toString()
                    .trim();

                final colorVal = _toColorInt(
                  data['ui_color'],
                  title,
                );

                final textAvailableHeight =
                    computedHeight - 4;

                final calculatedMaxLines =
                (textAvailableHeight / 12.5).floor();

                final allowedLines = math.max(
                  calculatedMaxLines,
                  1,
                );

                final showLocation = computedHeight > 36 &&
                    locationName.isNotEmpty;

                final titleMaxLines = showLocation
                    ? math.max(
                  allowedLines - 1,
                  1,
                )
                    : allowedLines;

                return Positioned(
                  top: top,
                  left: lane * itemWidth,
                  width: itemWidth - 3,
                  height: computedHeight,
                  child: GestureDetector(
                    onTap: () => _openScheduleDetail(data),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Color(colorVal),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      clipBehavior: Clip.hardEdge,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: titleMaxLines,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (showLocation) ...[
                            const SizedBox(height: 1),
                            SizedBox(
                              width: double.infinity,
                              child: Text(
                                locationName,
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }}

class _TimetableAddSheet extends StatefulWidget {
  const _TimetableAddSheet();

  @override
  State<_TimetableAddSheet> createState() => _TimetableAddSheetState();
}

class _TimetableAddSheetState extends State<_TimetableAddSheet> {
  static const Color _mainStayColor = Color(0xFF6FD0F1);
  List<int> _selectedRepeatDays = [];
  DateTime? _repeatEndDate;
  // 전역으로 통일된 kAppPaletteColors 사용
  final List<Color> _availableColors = kAppPaletteColors;

  Color _generateColorFromTitle(String title) {
    if (title.isEmpty) return _mainStayColor;
    int hash = 0;
    for (var c in title.trim().toLowerCase().codeUnits) {
      hash = (hash * 31 + c) & 0xFFFFFFFF;
    }
    return _availableColors[hash.abs() % _availableColors.length];
  }

  late final List<Map<String, dynamic>> _editingItems = [
    {
      'title': '',
      'subject': '',
      'dateStr': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      'starttime': '09:00',
      'endtime': '10:00',
      'location_name': '',
      'place_address': '',
      'place_type': '기타',
      'latitude': null,
      'longitude': null,
      'ui_color': _mainStayColor.value,
      'is_alarm_enabled': true,
      'is_all_day': false,
    }
  ];

  Future<void> _openMapSelection(
      Map<String, dynamic> item,
      ) async {
    final DateTime targetDate =
        DateTime.tryParse(
          item['dateStr']?.toString() ?? '',
        ) ??
            DateTime.now();

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapSelectionPage(
          startTime: const TimeOfDay(
            hour: 9,
            minute: 0,
          ),
          duration: 60,
          selectedDate: targetDate,
          isFromCalendar: true,
          title: item['title']?.toString() ?? '',
          colorValue:
          item['ui_color'] is int
              ? item['ui_color'] as int
              : const Color(0xFF6FD0F1).value,
        ),
      ),
    );

    if (!mounted || result == null) return;

    if (result is! Map) {
      debugPrint('❌ MapSelectionPage 결과가 Map이 아닙니다.');
      debugPrint('result = $result');
      return;
    }

    final dynamic rawLocation = result['location'];

    if (rawLocation is! Map) {
      debugPrint('❌ location 데이터가 없습니다.');
      debugPrint('result = $result');
      return;
    }

    final String placeName =
        rawLocation['name']?.toString() ?? '';

    final String placeAddress =
        rawLocation['address']?.toString() ?? '';

    final double? latitude =
    double.tryParse(
      rawLocation['latitude']?.toString() ?? '',
    );

    final double? longitude =
    double.tryParse(
      rawLocation['longitude']?.toString() ?? '',
    );

    debugPrint('========== 장소 선택 ==========');
    debugPrint('name: $placeName');
    debugPrint('address: $placeAddress');
    debugPrint('latitude: $latitude');
    debugPrint('longitude: $longitude');

    setState(() {
      item['place_name'] = placeName;
      item['place_address'] = placeAddress;
      item['place_lat'] = latitude;
      item['place_lng'] = longitude;

      item['location_name'] = placeName;
      item['location'] = placeName;
    });

    debugPrint('✅ 장소가 화면 데이터에 반영되었습니다.');
  }

  Future<DateTime?> _showCustomDatePicker(
      DateTime initialDate,
      ) async {
    DateTime tempDate = initialDate;

    return showDialog<DateTime>(
      context: context,
      builder: (context) {
        final bool isDark =
            Theme.of(context).brightness ==
                Brightness.dark;

        final Color dialogBackground =
        isDark
            ? const Color(0xFF1E1E1E)
            : Colors.white;

        final Color textColor =
        isDark
            ? Colors.white
            : Colors.black87;

        final Color cancelColor =
        isDark
            ? Colors.white70
            : Colors.grey;

        return Dialog(
          backgroundColor: dialogBackground,
          shape: RoundedRectangleBorder(
            borderRadius:
            BorderRadius.circular(20),
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            width: 320,
            decoration: BoxDecoration(
              color: dialogBackground,
              borderRadius:
              BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "날짜 선택",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),

                const SizedBox(height: 12),

                SizedBox(
                  height: 320,
                  child: CalendarDatePicker(
                    initialDate: tempDate,
                    firstDate: DateTime(2025),
                    lastDate: DateTime(2035),
                    onDateChanged: (picked) {
                      tempDate = picked;
                    },
                  ),
                ),

                Row(
                  mainAxisAlignment:
                  MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () =>
                          Navigator.pop(
                            context,
                            null,
                          ),
                      child: Text(
                        "취소",
                        style: TextStyle(
                          color: cancelColor,
                        ),
                      ),
                    ),

                    ElevatedButton(
                      style:
                      ElevatedButton.styleFrom(
                        backgroundColor:
                        _mainStayColor,
                      ),
                      onPressed: () =>
                          Navigator.pop(
                            context,
                            tempDate,
                          ),
                      child: const Text(
                        "확인",
                        style: TextStyle(
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<String?> _showCustomTimePicker(
      String initialTimeStr,
      ) async {
    final parts = initialTimeStr.split(':');

    int selectedHour =
    parts.isNotEmpty
        ? int.tryParse(parts[0]) ?? 9
        : 9;

    int selectedMinute =
    parts.length > 1
        ? int.tryParse(parts[1]) ?? 0
        : 0;

    selectedHour = selectedHour.clamp(0, 23);
    selectedMinute =
        (selectedMinute ~/ 5) * 5;

    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final isDark =
            Theme.of(dialogContext).brightness ==
                Brightness.dark;

        final dialogBackground = isDark
            ? const Color(0xFF1E1E1E)
            : Colors.white;

        final textColor = isDark
            ? Colors.white
            : Colors.black87;

        final iconColor = isDark
            ? Colors.white
            : Colors.black87;

        final cancelColor = isDark
            ? Colors.white70
            : Colors.grey;

        return StatefulBuilder(
          builder: (
              context,
              setDialogState,
              ) {
            final formattedHour =
            selectedHour
                .toString()
                .padLeft(2, '0');

            final formattedMinute =
            selectedMinute
                .toString()
                .padLeft(2, '0');

            return Dialog(
              backgroundColor: dialogBackground,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Container(
                width: 300,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: dialogBackground,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '시간 선택',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),

                    const SizedBox(height: 20),

                    Row(
                      mainAxisAlignment:
                      MainAxisAlignment.center,
                      children: [
                        Column(
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.keyboard_arrow_up,
                                color: iconColor,
                              ),
                              onPressed: () {
                                setDialogState(() {
                                  selectedHour =
                                      (selectedHour + 1) % 24;
                                });
                              },
                            ),
                            Text(
                              formattedHour,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.keyboard_arrow_down,
                                color: iconColor,
                              ),
                              onPressed: () {
                                setDialogState(() {
                                  selectedHour =
                                      (selectedHour - 1 + 24) % 24;
                                });
                              },
                            ),
                          ],
                        ),

                        Text(
                          ':',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),

                        Column(
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.keyboard_arrow_up,
                                color: iconColor,
                              ),
                              onPressed: () {
                                setDialogState(() {
                                  selectedMinute =
                                      (selectedMinute + 5) % 60;
                                });
                              },
                            ),
                            Text(
                              formattedMinute,
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.keyboard_arrow_down,
                                color: iconColor,
                              ),
                              onPressed: () {
                                setDialogState(() {
                                  selectedMinute =
                                      (selectedMinute - 5 + 60) % 60;
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    Row(
                      mainAxisAlignment:
                      MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            Navigator.pop(
                              dialogContext,
                              null,
                            );
                          },
                          child: Text(
                            '취소',
                            style: TextStyle(
                              color: cancelColor,
                            ),
                          ),
                        ),

                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _mainStayColor,
                          ),
                          onPressed: () {
                            Navigator.pop(
                              dialogContext,
                              '$formattedHour:$formattedMinute',
                            );
                          },
                          child: const Text(
                            '확인',
                            style: TextStyle(
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }


  void _showRepeatDayPicker() async {
    final baseDate =
        DateTime.tryParse(
          _editingItems.first['dateStr']?.toString() ?? '',
        ) ??
            DateTime.now();

    final normalizedBaseDate = DateTime(
      baseDate.year,
      baseDate.month,
      baseDate.day,
    );

    List<int> tempSelectedDays =
    List<int>.from(_selectedRepeatDays);

    DateTime tempEndDate =
        _repeatEndDate ??
            normalizedBaseDate;

    const days = [
      '월',
      '화',
      '수',
      '목',
      '금',
      '토',
      '일',
    ];

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
              context,
              setDialogState,
              ) {
            final isValid =
                tempSelectedDays.isNotEmpty &&
                    !tempEndDate.isBefore(
                      normalizedBaseDate,
                    );

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text(
                '반복 요일 선택',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  const Text(
                    '반복할 요일',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(
                      7,
                          (index) {
                        final dayIndex = index + 1;
                        final selected =
                        tempSelectedDays.contains(
                          dayIndex,
                        );

                        return FilterChip(
                          label: Text(days[index]),
                          selected: selected,
                          selectedColor:
                          _mainStayColor.withOpacity(0.3),
                          checkmarkColor:
                          _mainStayColor,
                          onSelected: (value) {
                            setDialogState(() {
                              if (value) {
                                if (!tempSelectedDays
                                    .contains(dayIndex)) {
                                  tempSelectedDays
                                      .add(dayIndex);
                                }
                              } else {
                                tempSelectedDays
                                    .remove(dayIndex);
                              }

                              tempSelectedDays.sort();
                            });
                          },
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 24),

                  const Text(
                    '반복 기간',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 10),

                  InkWell(
                    borderRadius:
                    BorderRadius.circular(14),
                    onTap: () async {
                      final picked =
                      await _showCustomDatePicker(
                        tempEndDate,
                      );

                      if (picked == null) return;

                      final normalized = DateTime(
                        picked.year,
                        picked.month,
                        picked.day,
                      );

                      if (normalized.isBefore(
                        normalizedBaseDate,
                      )) {
                        _showSnack(
                          '시작일 이후의 날짜를 선택해주세요.',
                        );
                        return;
                      }

                      setDialogState(() {
                        tempEndDate = normalized;
                      });
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius:
                        BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_today_outlined,
                            color: Colors.grey,
                            size: 20,
                          ),

                          const SizedBox(width: 12),

                          Expanded(
                            child: Text(
                              '${DateFormat(
                                'yyyy년 M월 d일 (E)',
                                'ko_KR',
                              ).format(tempEndDate)}까지',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),

                          const Icon(
                            Icons.chevron_right,
                            color: Colors.grey,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text(
                    '취소',
                    style: TextStyle(
                      color: Colors.grey,
                    ),
                  ),
                ),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isValid
                        ? _mainStayColor
                        : Colors.grey,
                  ),
                  onPressed: !isValid
                      ? null
                      : () {
                    setState(() {
                      _selectedRepeatDays =
                      List<int>.from(
                        tempSelectedDays,
                      );

                      _repeatEndDate =
                          tempEndDate;
                    });

                    Navigator.pop(
                      dialogContext,
                    );
                  },
                  child: const Text(
                    '확인',
                    style: TextStyle(
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }


  Future<void> _submitSchedules() async {
    final uid =
        FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      _showSnack('로그인이 필요합니다.');
      return;
    }

    try {
      final firestore =
          FirebaseFirestore.instance;

      final schedulesRef = firestore
          .collection('users')
          .doc(uid)
          .collection('schedules');

      final batch = firestore.batch();

      int getMinutes(
          String startTime,
          String endTime,
          ) {
        final startParts =
        startTime.split(':');
        final endParts =
        endTime.split(':');

        final startHour =
        startParts.isNotEmpty
            ? int.tryParse(startParts[0]) ?? 0
            : 0;

        final startMinute =
        startParts.length > 1
            ? int.tryParse(startParts[1]) ?? 0
            : 0;

        final endHour =
        endParts.isNotEmpty
            ? int.tryParse(endParts[0]) ?? 0
            : 0;

        final endMinute =
        endParts.length > 1
            ? int.tryParse(endParts[1]) ?? 0
            : 0;

        final start =
            startHour * 60 + startMinute;

        var end =
            endHour * 60 + endMinute;

        if (end <= start) {
          end += 1440;
        }

        return end - start;
      }

      DateTime makeDateTime(
          DateTime date,
          String time,
          ) {
        final parts = time.split(':');

        final hour =
        parts.isNotEmpty
            ? int.tryParse(parts[0]) ?? 0
            : 0;

        final minute =
        parts.length > 1
            ? int.tryParse(parts[1]) ?? 0
            : 0;

        return DateTime(
          date.year,
          date.month,
          date.day,
          hour.clamp(0, 23),
          minute.clamp(0, 59),
        );
      }

      for (final item in _editingItems) {
        final title =
        (item['title'] ?? '')
            .toString()
            .trim();

        if (title.isEmpty) {
          _showSnack('일정 제목을 입력해주세요.');
          return;
        }

        final subject =
        (item['subject'] ?? '')
            .toString()
            .trim();

        final placeName =
        (
            item['place_name'] ??
                item['location_name'] ??
                item['location'] ??
                ''
        )
            .toString()
            .trim();

        final placeAddress =
        (item['place_address'] ?? '')
            .toString()
            .trim();

        final latitude =
            item['place_lat'] ??
                item['latitude'];

        final longitude =
            item['place_lng'] ??
                item['longitude'];

        final placeDistance =
        item['place_distance'];

        final uiColor =
        _toColorInt(item['ui_color']);

        final force =
            item['is_forced_mode'] == true;

        final alarmEnabled =
            item['is_alarm_enabled'] != false;

        final isAllDay =
            item['is_all_day'] == true;

        final startTime =
        (item['starttime'] ?? '09:00')
            .toString();

        final endTime =
        (item['endtime'] ?? '10:00')
            .toString();

        final baseDate =
            DateTime.tryParse(
              (item['dateStr'] ?? '')
                  .toString(),
            ) ??
                DateTime.now();

        final normalizedBaseDate =
        DateTime(
          baseDate.year,
          baseDate.month,
          baseDate.day,
        );

        final targetMinutes = isAllDay
            ? 1440
            : getMinutes(
          startTime,
          endTime,
        );

        final isRepeating =
            _selectedRepeatDays.isNotEmpty &&
                _repeatEndDate != null;

        final List<DateTime> targetDates = [];

        if (isRepeating) {
          final endDate = DateTime(
            _repeatEndDate!.year,
            _repeatEndDate!.month,
            _repeatEndDate!.day,
          );

          var current =
              normalizedBaseDate;

          while (!current.isAfter(endDate)) {
            if (_selectedRepeatDays
                .contains(current.weekday)) {
              targetDates.add(current);
            }

            current = current.add(
              const Duration(days: 1),
            );
          }
        } else {
          targetDates.add(
            normalizedBaseDate,
          );
        }

        for (final targetDate
        in targetDates) {
          final startDateTime =
          makeDateTime(
            targetDate,
            startTime,
          );

          DateTime endDateTime;

          if (isAllDay) {
            endDateTime = DateTime(
              targetDate.year,
              targetDate.month,
              targetDate.day,
            ).add(
              const Duration(days: 1),
            );
          } else {
            endDateTime =
                makeDateTime(
                  targetDate,
                  endTime,
                );

            if (!endDateTime.isAfter(
              startDateTime,
            )) {
              endDateTime =
                  endDateTime.add(
                    const Duration(days: 1),
                  );
            }
          }

          final dateStr =
          DateFormat('yyyy-MM-dd')
              .format(targetDate);

          final docRef =
          schedulesRef.doc();

          batch.set(
            docRef,
            {
              'title': title,
              'subject': subject,

              'dateStr': dateStr,

              'startTime': startTime,
              'endTime': endTime,

              'starttime': startTime,
              'endtime': endTime,

              'start_datetime':
              Timestamp.fromDate(
                startDateTime,
              ),
              'end_datetime':
              Timestamp.fromDate(
                endDateTime,
              ),

              'durationMinutes':
              targetMinutes,
              'target_minutes':
              targetMinutes,

              'location_name':
              placeName,
              'location':
              placeName,
              'place_name':
              placeName,
              'place_address':
              placeAddress,
              'place_distance':
              placeDistance,

              'latitude': latitude,
              'longitude': longitude,
              'place_lat': latitude,
              'place_lng': longitude,

              'ui_color': uiColor,

              'force': force,
              'is_forced_mode': force,

              'is_alarm_enabled':
              alarmEnabled,
              'is_all_day': isAllDay,

              'isFinished': false,
              'status': 'scheduled',

              'repeat_enabled':
              isRepeating,
              'repeat_days':
              isRepeating
                  ? List<int>.from(
                _selectedRepeatDays,
              )
                  : <int>[],

              'repeat_end_date':
              isRepeating
                  ? Timestamp.fromDate(
                DateTime(
                  _repeatEndDate!.year,
                  _repeatEndDate!.month,
                  _repeatEndDate!.day,
                ),
              )
                  : null,

              'created_at':
              FieldValue.serverTimestamp(),
              'updated_at':
              FieldValue.serverTimestamp(),
            },
          );
        }
      }

      await batch.commit();

      if (!mounted) return;

      Navigator.pop(
        context,
        true,
      );
    } catch (e, stackTrace) {
      debugPrint(
        '❌ schedules 저장 오류: $e',
      );
      debugPrint('$stackTrace');

      if (mounted) {
        _showSnack(
          '일정 저장에 실패했습니다.',
        );
      }
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;

    final isDark =
        Theme.of(context).brightness ==
            Brightness.dark;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: TextStyle(
              color: isDark
                  ? Colors.black
                  : Colors.white,
            ),
          ),
          backgroundColor: isDark
              ? Colors.white
              : const Color(0xFF323232),
          behavior:
          SnackBarBehavior.floating,
        ),
      );
  }

  void _showColorPickerPopup(int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(24),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              const Text(
                '일정 색상 선택',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 16),

              GridView.builder(
                shrinkWrap: true,
                physics:
                const NeverScrollableScrollPhysics(),
                gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemCount:
                _availableColors.length,
                itemBuilder: (
                    context,
                    colorIdx,
                    ) {
                  final color =
                  _availableColors[colorIdx];

                  final isSelected =
                      _toColorInt(
                        _editingItems[index]
                        ['ui_color'],
                      ) ==
                          color.value;

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _editingItems[index]
                        ['ui_color'] =
                            color.value;
                      });

                      Navigator.pop(
                        sheetContext,
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(
                          color: Colors.black,
                          width: 3,
                        )
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 20,
                      )
                          : null,
                    ),
                  );
                },
              ),

              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color backgroundColor =
    isDark
        ? const Color(0xFF121212)
        : Colors.white;

    final Color handleColor =
    isDark
        ? const Color(0xFF555555)
        : Colors.grey.shade300;

    final Color textColor =
    isDark
        ? Colors.white
        : Colors.black87;

    return Container(
      constraints: BoxConstraints(
        maxHeight:
        MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(30),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),

            Container(
              width: 50,
              height: 5,
              decoration: BoxDecoration(
                color: handleColor,
                borderRadius:
                BorderRadius.circular(10),
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 20,
                ),
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      "새 일정 추가",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),

                    const SizedBox(height: 15),

                    ...List.generate(
                      _editingItems.length,
                          (i) => _buildItemCard(i),
                    ),

                    const SizedBox(height: 20),

                    _buildSubmitButton(),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemCard(int index) {
    final item = _editingItems[index];

    if (item['endDateStr'] == null) {
      item['endDateStr'] = item['dateStr'];
    }

    final targetDate =
        DateTime.tryParse(
          item['dateStr']?.toString() ?? '',
        ) ??
            DateTime.now();

    final endDate =
        DateTime.tryParse(
          item['endDateStr']?.toString() ?? '',
        ) ??
            targetDate;

    final isAlarmEnabled =
        item['is_alarm_enabled'] != false;

    final isForcedMode =
        item['is_forced_mode'] == true;

    final isAllDay =
        item['is_all_day'] == true;

    final locationName =
    (item['location_name'] ?? '')
        .toString()
        .trim();

    final isDark =
        Theme.of(context).brightness ==
            Brightness.dark;

    final cardBackground = isDark
        ? const Color(0xFF1E1E1E)
        : Colors.white;

    final textColor = isDark
        ? Colors.white
        : Colors.black87;

    final secondaryTextColor = isDark
        ? Colors.white70
        : Colors.black87;

    final greyColor = isDark
        ? Colors.white54
        : Colors.grey;

    final dividerColor = isDark
        ? const Color(0xFF3A3A3A)
        : Colors.grey.shade200;

    return Container(
      margin: const EdgeInsets.only(
        bottom: 16,
      ),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: BorderRadius.circular(20),
        boxShadow: isDark
            ? null
            : [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isDark
              ? const Color(0xFF333333)
              : Colors.grey.shade100,
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          // 제목 + 색상
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: TextEditingController(
                    text: item['title']?.toString() ?? '',
                  )..selection = TextSelection.fromPosition(
                    TextPosition(
                      offset:
                      (item['title']?.toString() ?? '')
                          .length,
                    ),
                  ),
                  onChanged: (value) {
                    item['title'] = value;

                    if (value.trim().isNotEmpty) {
                      final generatedColor =
                      _generateColorFromTitle(value);

                      if (item['ui_color'] !=
                          generatedColor.value) {
                        setState(() {
                          item['ui_color'] =
                              generatedColor.value;
                        });
                      }
                    } else {
                      setState(() {});
                    }
                  },
                  decoration: InputDecoration(
                    hintText: '제목',
                    border: InputBorder.none,
                    hintStyle: TextStyle(
                      color: isDark
                          ? Colors.white54
                          : Colors.grey,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ),

              const SizedBox(width: 12),

              _colorPicker(index),
            ],
          ),

          // 구분선
          Container(
            height: 1,
            color: dividerColor,
            margin: const EdgeInsets.symmetric(
              vertical: 8,
            ),
          ),

          const SizedBox(height: 6),

          // 날짜 / 시간
          Row(
            mainAxisAlignment:
            MainAxisAlignment.spaceBetween,
            children: [
              // 시작 날짜 / 시간
              GestureDetector(
                onTap: () async {
                  final picked =
                  await _showCustomDatePicker(
                    targetDate,
                  );

                  if (picked == null) return;

                  final pickedDate = DateTime(
                    picked.year,
                    picked.month,
                    picked.day,
                  );

                  setState(() {
                    item['dateStr'] =
                        DateFormat('yyyy-MM-dd')
                            .format(pickedDate);

                    final currentEndDate =
                    DateTime.tryParse(
                      item['endDateStr']
                          ?.toString() ??
                          '',
                    );

                    if (currentEndDate == null ||
                        pickedDate.isAfter(
                          currentEndDate,
                        )) {
                      item['endDateStr'] =
                      item['dateStr'];
                    }
                  });
                },
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat(
                        'M월 d일 (E)',
                        'ko_KR',
                      ).format(targetDate),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),

                    if (!isAllDay) ...[
                      const SizedBox(height: 15),

                      GestureDetector(
                        onTap: () async {
                          final pickedTime =
                          await _showCustomTimePicker(
                            item['starttime']
                                ?.toString() ??
                                '09:00',
                          );

                          if (pickedTime == null) {
                            return;
                          }

                          setState(() {
                            item['starttime'] =
                                pickedTime;
                          });
                        },
                        child: Text(
                          _formatTimeOfDay(
                            item['starttime']
                                ?.toString() ??
                                '09:00',
                          ),
                          style: TextStyle(
                            fontSize: 15,
                            color:
                            secondaryTextColor,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              Icon(
                Icons.arrow_forward,
                color: greyColor,
                size: 18,
              ),

              // 종료 날짜 / 시간
              GestureDetector(
                onTap: () async {
                  final picked =
                  await _showCustomDatePicker(
                    endDate,
                  );

                  if (picked == null) return;

                  setState(() {
                    item['endDateStr'] =
                        DateFormat('yyyy-MM-dd')
                            .format(picked);
                  });
                },
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.end,
                  children: [
                    if (!isAllDay) ...[
                      const SizedBox(height: 15),

                      GestureDetector(
                        onTap: () async {
                          final pickedTime =
                          await _showCustomTimePicker(
                            item['endtime']
                                ?.toString() ??
                                '10:00',
                          );

                          if (pickedTime == null) {
                            return;
                          }

                          setState(() {
                            item['endtime'] =
                                pickedTime;
                          });
                        },
                        child: Text(
                          _formatTimeOfDay(
                            item['endtime']
                                ?.toString() ??
                                '10:00',
                          ),
                          style: TextStyle(
                            fontSize: 15,
                            color:
                            secondaryTextColor,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          // 구분선
          Container(
            height: 1,
            color: dividerColor,
            margin: const EdgeInsets.symmetric(
              vertical: 16,
            ),
          ),

          // 장소
          InkWell(
            onTap: () => _openMapSelection(item),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 6,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    color: greyColor,
                    size: 22,
                  ),

                  const SizedBox(width: 14),

                  Expanded(
                    child: Text(
                      locationName.isEmpty
                          ? '장소'
                          : locationName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: locationName.isEmpty
                            ? greyColor
                            : textColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 구분선
          Container(
            height: 1,
            color: dividerColor,
            margin: const EdgeInsets.symmetric(
              vertical: 12,
            ),
          ),

          // 반복
          InkWell(
            onTap: _showRepeatDayPicker,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 6,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.repeat,
                    color: greyColor,
                    size: 22,
                  ),

                  const SizedBox(width: 14),

                  Expanded(
                    child: _buildRepeatSummary(),
                  ),

                  Icon(
                    Icons.chevron_right,
                    color: greyColor,
                  ),
                ],
              ),
            ),
          ),

          // 구분선
          Container(
            height: 1,
            color: dividerColor,
            margin: const EdgeInsets.symmetric(
              vertical: 12,
            ),
          ),

          // 강제모드
          InkWell(
            onTap: () {
              setState(() {
                item['is_forced_mode'] =
                !isForcedMode;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 6,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lock_outline,
                    color: isForcedMode
                        ? _mainStayColor
                        : greyColor,
                    size: 22,
                  ),

                  const SizedBox(width: 14),

                  Expanded(
                    child: Text(
                      isForcedMode
                          ? '강제모드 적용됨'
                          : '강제모드 미적용',
                      style: TextStyle(
                        fontSize: 16,
                        color: isForcedMode
                            ? textColor
                            : greyColor,
                        fontWeight:
                        FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 구분선
          Container(
            height: 1,
            color: dividerColor,
            margin: const EdgeInsets.symmetric(
              vertical: 12,
            ),
          ),

          // 알림
          InkWell(
            onTap: () {
              setState(() {
                item['is_alarm_enabled'] =
                !isAlarmEnabled;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 6,
              ),
              child: Row(
                children: [
                  Icon(
                    isAlarmEnabled
                        ? Icons.notifications_active
                        : Icons.notifications_off_outlined,
                    color: isAlarmEnabled
                        ? _mainStayColor
                        : greyColor,
                    size: 22,
                  ),

                  const SizedBox(width: 14),

                  Expanded(
                    child: Text(
                      isAlarmEnabled
                          ? '시작 30분 전 알림'
                          : '알림 해제됨',
                      style: TextStyle(
                        fontSize: 16,
                        color: isAlarmEnabled
                            ? textColor
                            : greyColor,
                        fontWeight:
                        FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildRepeatSummary() {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color normalTextColor =
    isDark
        ? Colors.white
        : Colors.black87;

    if (_selectedRepeatDays.isEmpty) {
      return Text(
        '반복',
        style: TextStyle(
          fontSize: 16,
          color: normalTextColor,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    const days = [
      '월',
      '화',
      '수',
      '목',
      '금',
      '토',
      '일',
    ];

    final dayText = _selectedRepeatDays
        .where((day) => day >= 1 && day <= 7)
        .map((day) => days[day - 1])
        .join(', ');

    final endText = _repeatEndDate == null
        ? ''
        : ' ~ ${DateFormat(
      'M월 d일',
      'ko_KR',
    ).format(_repeatEndDate!)}';

    return Text(
      '매주 $dayText$endText',
      style: const TextStyle(
        fontSize: 16,
        color: _mainStayColor,
        fontWeight: FontWeight.w500,
      ),
    );
  }


  String _formatTimeOfDay(String timeStr) {
    try {
      final parts = timeStr.split(':');
      int hour = int.parse(parts[0]);
      int minute = int.parse(parts[1]);
      String period = hour < 12 ? "오전" : "오후";
      if (hour == 0) {
        hour = 12;
      } else if (hour > 12) {
        hour -= 12;
      }
      return "$period $hour:${_p(minute)}";
    } catch (_) {
      return timeStr;
    }
  }

  Widget _colorPicker(int index) {
    final Color color = Color(
      _toColorInt(
        _editingItems[index]['ui_color'],
      ),
    );

    return GestureDetector(
      onTap: () => _showColorPickerPopup(index),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }


  int _toColorInt(dynamic value) {
    if (value == null) {
      return const Color(0xFF6FD0F1).value;
    }

    if (value is int) {
      return value;
    }

    if (value is Color) {
      return value.value;
    }

    return int.tryParse(value.toString()) ??
        const Color(0xFF6FD0F1).value;
  }


  String _p(int n) => n.toString().padLeft(2, '0');



  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _submitSchedules,
        style: ElevatedButton.styleFrom(
          backgroundColor: _mainStayColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: const Text(
          "일정 저장하기",
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }}






class ScheduleDetailSheet extends StatefulWidget {
  final Map<String, dynamic> schedule;
  final VoidCallback onUpdated;

  const ScheduleDetailSheet({
    super.key,
    required this.schedule,
    required this.onUpdated,
  });

  @override
  State<ScheduleDetailSheet> createState() => _ScheduleDetailSheetState();
}

class _ScheduleDetailSheetState extends State<ScheduleDetailSheet> {
  late int _currentColor;
  late bool _isForcedMode;
  bool _isLoading = false;

  // 전역으로 통일된 kAppPaletteColors 사용
  final List<Color> _availableColors = kAppPaletteColors;

  // 수정용 컨트롤러
  late TextEditingController _titleController;
  late TextEditingController _locationController;

  // 장소 상세 정보 저장을 위한 변수
  String? _selectedPlaceAddress;
  double? _selectedLatitude;
  double? _selectedLongitude;

  @override
  void initState() {
    super.initState();

    final dynamic savedColor = widget.schedule['ui_color'];

    if (savedColor is int) {
      _currentColor = savedColor;
    } else {
      _currentColor =
          int.tryParse(savedColor?.toString() ?? '') ??
              const Color(0xFF6FD0F1).value;
    }

    final dynamic forcedValue =
        widget.schedule['force'] ??
            widget.schedule['is_forced_mode'] ??
            widget.schedule['is_strict'] ??
            widget.schedule['isStrictMode'] ??
            false;

    _isForcedMode = forcedValue == true;

    _titleController = TextEditingController(
      text: widget.schedule['title']?.toString() ?? '',
    );

    _locationController = TextEditingController(
      text: widget.schedule['location_name']?.toString() ??
          widget.schedule['location']?.toString() ??
          widget.schedule['place_name']?.toString() ??
          '',
    );

    _selectedPlaceAddress =
        widget.schedule['place_address']?.toString();

    _selectedLatitude = double.tryParse(
      widget.schedule['place_lat']?.toString() ??
          widget.schedule['latitude']?.toString() ??
          '',
    );

    _selectedLongitude = double.tryParse(
      widget.schedule['place_lng']?.toString() ??
          widget.schedule['longitude']?.toString() ??
          '',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  // 장소 선택 페이지(MapSelectionPage) 연동 메서드
  Future<void> _openMapSelection() async {
    final Map<String, dynamic> item = widget.schedule;

    final DateTime targetDate =
        DateTime.tryParse(
          item['dateStr']?.toString() ?? '',
        ) ??
            DateTime.now();

    final String startTime =
        item['starttime']?.toString() ?? '09:00';

    final List<String> timeParts = startTime.split(':');

    final int hour =
        int.tryParse(
          timeParts.isNotEmpty ? timeParts[0] : '09',
        ) ??
            9;

    final int minute =
        int.tryParse(
          timeParts.length > 1 ? timeParts[1] : '00',
        ) ??
            0;

    // 현재 저장된 색상 가져오기
    int colorValue = const Color(0xFF6FD0F1).value;

    final dynamic savedColor = item['ui_color'];

    if (savedColor is int) {
      colorValue = savedColor;
    } else if (savedColor != null) {
      colorValue =
          int.tryParse(savedColor.toString()) ??
              const Color(0xFF6FD0F1).value;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapSelectionPage(
          startTime: TimeOfDay(
            hour: hour.clamp(0, 23),
            minute: minute.clamp(0, 59),
          ),
          duration: 60,
          selectedDate: targetDate,
          isFromCalendar: true,
          title: _titleController.text,
          colorValue: colorValue,
        ),
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    if (result is! Map) {
      debugPrint('❌ MapSelectionPage 결과가 Map이 아닙니다.');
      debugPrint('result = $result');
      return;
    }

    final dynamic rawLocation = result['location'];

    if (rawLocation is! Map) {
      debugPrint('❌ location 데이터가 없습니다.');
      debugPrint('result = $result');
      return;
    }

    final String placeName =
        rawLocation['name']?.toString() ?? '';

    final String placeAddress =
        rawLocation['address']?.toString() ?? '';

    final double? latitude =
    double.tryParse(
      rawLocation['latitude']?.toString() ?? '',
    );

    final double? longitude =
    double.tryParse(
      rawLocation['longitude']?.toString() ?? '',
    );

    debugPrint('================================');
    debugPrint('📍 장소 선택 완료');
    debugPrint('name = $placeName');
    debugPrint('address = $placeAddress');
    debugPrint('lat = $latitude');
    debugPrint('lng = $longitude');
    debugPrint('================================');

    setState(() {
      // 화면 표시
      _locationController.text = placeName;

      // 선택한 장소 상세정보
      _selectedPlaceAddress = placeAddress;
      _selectedLatitude = latitude;
      _selectedLongitude = longitude;

      // widget.schedule 데이터에도 반영
      item['place_name'] = placeName;
      item['place_address'] = placeAddress;
      item['place_lat'] = latitude;
      item['place_lng'] = longitude;

      // 기존 코드 호환
      item['location_name'] = placeName;
      item['location'] = placeName;
      item['latitude'] = latitude;
      item['longitude'] = longitude;
    });

    debugPrint('✅ 선택한 장소가 현재 일정 데이터에 반영됨');
  }

  void _showColorPickerPopup() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("일정 색상 변경", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemCount: _availableColors.length,
                itemBuilder: (context, colorIdx) {
                  final color = _availableColors[colorIdx];
                  final isSelected = _currentColor == color.value;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _currentColor = color.value;
                      });
                      Navigator.pop(context);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: isSelected ? Border.all(color: Colors.black, width: 3) : null,
                      ),
                      child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  // 변경된 모든 정보(제목, 장소, 강제모드, 색상 등)를 한 번에 저장하는 메서드
  Future<void> _updateScheduleChanges(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null || _isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final firestore = FirebaseFirestore.instance;

      final schedulesRef = firestore
          .collection('users')
          .doc(uid)
          .collection('schedules');

      DocumentReference<Map<String, dynamic>>? scheduleRef;

      final candidates = <String>[
        widget.schedule['docId']?.toString().trim() ?? '',
        widget.schedule['scheduleId']?.toString().trim() ?? '',
        widget.schedule['documentId']?.toString().trim() ?? '',
        widget.schedule['schedule_id']?.toString().trim() ?? '',
        widget.schedule['id']?.toString().trim() ?? '',
      ].where((id) => id.isNotEmpty).toSet().toList();

      for (final id in candidates) {
        final ref = schedulesRef.doc(id);
        final snapshot = await ref.get();

        if (snapshot.exists) {
          scheduleRef = ref;
          break;
        }
      }

      if (scheduleRef == null) {
        final calendarEventId =
            widget.schedule['calendar_event_id']?.toString().trim() ?? '';

        if (calendarEventId.isNotEmpty) {
          final query = await schedulesRef
              .where(
            'calendar_event_id',
            isEqualTo: calendarEventId,
          )
              .limit(1)
              .get();

          if (query.docs.isNotEmpty) {
            scheduleRef = query.docs.first.reference;
          }
        }
      }

      if (scheduleRef == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('기존 일정을 찾을 수 없습니다.'),
          ),
        );
        return;
      }

      final existingSnapshot = await scheduleRef.get();

      if (!existingSnapshot.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('기존 일정을 찾을 수 없습니다.'),
          ),
        );
        return;
      }

      final existingData =
          existingSnapshot.data() ?? <String, dynamic>{};

      final bool isRepeating =
          existingData['repeat_enabled'] == true;

      String? editScope;

      if (isRepeating) {
        editScope = await showDialog<String>(
          context: context,
          builder: (dialogContext) {
            final bool isDark =
                Theme.of(dialogContext).brightness == Brightness.dark;

            final Color titleColor =
            isDark ? Colors.white : Colors.black87;

            final Color contentColor =
            isDark ? Colors.white70 : Colors.black87;

            final Color cancelColor =
            isDark ? Colors.white70 : Colors.black87;

            return AlertDialog(
              backgroundColor:
              isDark ? const Color(0xFF1E1E1E) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                '반복 일정 수정',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: titleColor,
                ),
              ),
              content: Text(
                '수정할 범위를 선택해주세요.',
                style: TextStyle(
                  color: contentColor,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                      'this',
                    );
                  },
                  child: Text(
                    '이번 일정만',
                    style: TextStyle(
                      color: cancelColor,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                    const Color(0xFF6FD0F1),
                  ),
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                      'this_and_future',
                    );
                  },
                  child: const Text(
                    '이번 일정 포함 앞으로 모든 일정',
                    style: TextStyle(
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            );
          },
        );

        if (editScope == null) return;
      } else {
        editScope = 'this';
      }

      final String title =
      _titleController.text.trim();

      final String placeName =
      _locationController.text.trim();

      final String placeAddress =
      (_selectedPlaceAddress ??
          existingData['place_address'] ??
          '')
          .toString()
          .trim();

      final double? placeLat =
          _selectedLatitude ??
              double.tryParse(
                existingData['place_lat']?.toString() ?? '',
              );

      final double? placeLng =
          _selectedLongitude ??
              double.tryParse(
                existingData['place_lng']?.toString() ?? '',
              );

      final Map<String, dynamic> updateData = {
        'title': title,
        'force': _isForcedMode,
        'is_forced_mode': _isForcedMode,
        'ui_color': _currentColor,
        'place_name': placeName,
        'location_name': placeName,
        'location': placeName,
        'place_address': placeAddress,
        'place_lat': placeLat,
        'place_lng': placeLng,
        'latitude': placeLat,
        'longitude': placeLng,
        'updated_at': FieldValue.serverTimestamp(),
      };

      if (editScope == 'this') {
        await scheduleRef.set(
          updateData,
          SetOptions(merge: true),
        );
      } else {
        final allSchedules =
        await schedulesRef.get();

        final String currentDate =
            existingData['dateStr']?.toString() ??
                existingData['date_str']?.toString() ??
                '';

        final String currentTitle =
            existingData['title']?.toString() ?? '';

        final String currentStartTime =
            existingData['startTime']?.toString() ??
                existingData['starttime']?.toString() ??
                '';

        final String currentEndTime =
            existingData['endTime']?.toString() ??
                existingData['endtime']?.toString() ??
                '';

        final List<int> repeatDays =
            (existingData['repeat_days'] as List?)
                ?.map(
                  (e) =>
              int.tryParse(e.toString()) ?? 0,
            )
                .where(
                  (e) => e >= 1 && e <= 7,
            )
                .toList() ??
                [];

        final dynamic repeatEndDate =
        existingData['repeat_end_date'];

        final batch = firestore.batch();

        for (final doc in allSchedules.docs) {
          final data = doc.data();

          if (data['repeat_enabled'] != true) {
            continue;
          }

          final String scheduleDate =
              data['dateStr']?.toString() ??
                  data['date_str']?.toString() ??
                  '';

          if (scheduleDate.compareTo(currentDate) < 0) {
            continue;
          }

          final String scheduleTitle =
              data['title']?.toString() ?? '';

          final String scheduleStartTime =
              data['startTime']?.toString() ??
                  data['starttime']?.toString() ??
                  '';

          final String scheduleEndTime =
              data['endTime']?.toString() ??
                  data['endtime']?.toString() ??
                  '';

          final List<int> scheduleRepeatDays =
              (data['repeat_days'] as List?)
                  ?.map(
                    (e) =>
                int.tryParse(e.toString()) ?? 0,
              )
                  .where(
                    (e) => e >= 1 && e <= 7,
              )
                  .toList() ??
                  [];

          bool sameRepeatEndDate = true;

          if (repeatEndDate != null &&
              data['repeat_end_date'] != null) {
            final Timestamp? a =
            repeatEndDate is Timestamp
                ? repeatEndDate
                : null;

            final Timestamp? b =
            data['repeat_end_date'] is Timestamp
                ? data['repeat_end_date']
                : null;

            if (a != null && b != null) {
              sameRepeatEndDate =
                  a.toDate().year ==
                      b.toDate().year &&
                      a.toDate().month ==
                          b.toDate().month &&
                      a.toDate().day ==
                          b.toDate().day;
            }
          }

          final bool sameRepeatGroup =
              scheduleTitle == currentTitle &&
                  scheduleStartTime ==
                      currentStartTime &&
                  scheduleEndTime ==
                      currentEndTime &&
                  scheduleRepeatDays.length ==
                      repeatDays.length &&
                  scheduleRepeatDays.toSet().containsAll(
                    repeatDays,
                  ) &&
                  repeatDays.toSet().containsAll(
                    scheduleRepeatDays,
                  ) &&
                  sameRepeatEndDate;

          if (!sameRepeatGroup) {
            continue;
          }

          batch.set(
            doc.reference,
            updateData,
            SetOptions(merge: true),
          );
        }

        await batch.commit();
      }

      widget.schedule['docId'] = scheduleRef.id;
      widget.schedule['title'] = title;
      widget.schedule['force'] = _isForcedMode;
      widget.schedule['is_forced_mode'] = _isForcedMode;
      widget.schedule['ui_color'] = _currentColor;
      widget.schedule['place_name'] = placeName;
      widget.schedule['location_name'] = placeName;
      widget.schedule['location'] = placeName;
      widget.schedule['place_address'] = placeAddress;
      widget.schedule['place_lat'] = placeLat;
      widget.schedule['place_lng'] = placeLng;

      widget.onUpdated();

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e, stackTrace) {
      debugPrint('❌ 일정 업데이트 실패: $e');
      debugPrint('$stackTrace');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _deleteSchedule(BuildContext context) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) return;

    final String? docId =
        widget.schedule['docId']?.toString() ??
            widget.schedule['calendar_event_id']?.toString();

    if (docId == null || docId.isEmpty) return;

    try {
      final firestore = FirebaseFirestore.instance;

      final schedulesRef = firestore
          .collection('users')
          .doc(uid)
          .collection('schedules');

      final docRef = schedulesRef.doc(docId);

      final snapshot = await docRef.get();

      if (!snapshot.exists) return;

      final data =
          snapshot.data() ?? <String, dynamic>{};

      final bool isRepeating =
          data['repeat_enabled'] == true;

      String? deleteScope;

      if (isRepeating) {
        deleteScope = await showDialog<String>(
          context: context,
          builder: (dialogContext) {
            final bool isDark =
                Theme.of(dialogContext).brightness == Brightness.dark;

            final Color titleColor =
            isDark ? Colors.white : Colors.black87;

            final Color contentColor =
            isDark ? Colors.white70 : Colors.black87;

            final Color cancelColor =
            isDark ? Colors.redAccent : Colors.red;

            return AlertDialog(
              backgroundColor:
              isDark ? const Color(0xFF1E1E1E) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                '반복 일정 삭제',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: titleColor,
                ),
              ),
              content: Text(
                '반복 일정입니다.\n삭제할 범위를 선택해주세요.',
                style: TextStyle(
                  color: contentColor,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                      'this',
                    );
                  },
                  child: Text(
                    '이번 일정만',
                    style: TextStyle(
                      color: cancelColor,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                  ),
                  onPressed: () {
                    Navigator.pop(
                      dialogContext,
                      'this_and_future',
                    );
                  },
                  child: const Text(
                    '이번 일정 포함 앞으로 모든 일정',
                    style: TextStyle(
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            );
          },
        );

        if (deleteScope == null) return;
      } else {
        deleteScope = 'this';
      }

      if (deleteScope == 'this') {
        await docRef.delete();
      } else {
        final allSchedules =
        await schedulesRef.get();

        final String currentDate =
            data['dateStr']?.toString() ??
                data['date_str']?.toString() ??
                '';

        final String currentTitle =
            data['title']?.toString() ?? '';

        final String currentStartTime =
            data['startTime']?.toString() ??
                data['starttime']?.toString() ??
                '';

        final String currentEndTime =
            data['endTime']?.toString() ??
                data['endtime']?.toString() ??
                '';

        final List<int> repeatDays =
            (data['repeat_days'] as List?)
                ?.map(
                  (e) =>
              int.tryParse(e.toString()) ?? 0,
            )
                .where(
                  (e) => e >= 1 && e <= 7,
            )
                .toList() ??
                [];

        final dynamic repeatEndDate =
        data['repeat_end_date'];

        final batch = firestore.batch();

        for (final doc in allSchedules.docs) {
          final schedule = doc.data();

          if (schedule['repeat_enabled'] != true) {
            continue;
          }

          final String scheduleDate =
              schedule['dateStr']?.toString() ??
                  schedule['date_str']?.toString() ??
                  '';

          if (scheduleDate.compareTo(currentDate) < 0) {
            continue;
          }

          final String scheduleTitle =
              schedule['title']?.toString() ?? '';

          final String scheduleStartTime =
              schedule['startTime']?.toString() ??
                  schedule['starttime']?.toString() ??
                  '';

          final String scheduleEndTime =
              schedule['endTime']?.toString() ??
                  schedule['endtime']?.toString() ??
                  '';

          final List<int> scheduleRepeatDays =
              (schedule['repeat_days'] as List?)
                  ?.map(
                    (e) =>
                int.tryParse(e.toString()) ?? 0,
              )
                  .where(
                    (e) => e >= 1 && e <= 7,
              )
                  .toList() ??
                  [];

          bool sameRepeatEndDate = true;

          if (repeatEndDate != null &&
              schedule['repeat_end_date'] != null) {
            final Timestamp? a =
            repeatEndDate is Timestamp
                ? repeatEndDate
                : null;

            final Timestamp? b =
            schedule['repeat_end_date']
            is Timestamp
                ? schedule['repeat_end_date']
                : null;

            if (a != null && b != null) {
              sameRepeatEndDate =
                  a.toDate().year ==
                      b.toDate().year &&
                      a.toDate().month ==
                          b.toDate().month &&
                      a.toDate().day ==
                          b.toDate().day;
            }
          }

          final bool sameRepeatGroup =
              scheduleTitle == currentTitle &&
                  scheduleStartTime ==
                      currentStartTime &&
                  scheduleEndTime ==
                      currentEndTime &&
                  scheduleRepeatDays.length ==
                      repeatDays.length &&
                  scheduleRepeatDays.toSet().containsAll(
                    repeatDays,
                  ) &&
                  repeatDays.toSet().containsAll(
                    scheduleRepeatDays,
                  ) &&
                  sameRepeatEndDate;

          if (!sameRepeatGroup) {
            continue;
          }

          batch.delete(doc.reference);
        }

        await batch.commit();
      }

      final calendarEventId =
      widget.schedule['calendar_event_id']
          ?.toString();

      final calendarId =
      widget.schedule['calendar_id']?.toString();

      if (calendarEventId != null &&
          calendarEventId.isNotEmpty &&
          calendarId != null &&
          calendarId.isNotEmpty) {
        try {
          final plugin = DeviceCalendarPlugin();

          await plugin.deleteEvent(
            calendarId,
            calendarEventId,
          );
        } catch (e) {
          debugPrint(
            '기기 캘린더 삭제 오류: $e',
          );
        }
      }

      if (context.mounted) {
        Navigator.pop(context, true);
      }
    } catch (e, stackTrace) {
      debugPrint('❌ 일정 삭제 오류: $e');
      debugPrint('$stackTrace');
    }
  }


  Future<void> _savePlaceChanges({
    required String placeName,
    required String placeAddress,
    required dynamic latitude,
    required dynamic longitude,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final String? docId =
        widget.schedule['docId']?.toString() ??
            widget.schedule['calendar_event_id']?.toString();

    if (docId == null || docId.isEmpty) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('schedules')
        .doc(docId)
        .set({
      'place_name': placeName,
      'location_name': placeName,
      'location': placeName,
      'place_address': placeAddress,
      'place_lat': latitude,
      'place_lng': longitude,
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color sheetBackground =
    isDark ? const Color(0xFF1E1E1E) : Colors.white;

    final Color fieldBackground =
    isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade50;

    final Color borderColor =
    isDark ? const Color(0xFF3A3A3A) : Colors.grey.shade200;

    final Color titleColor =
    isDark ? Colors.white : Colors.black87;

    final Color hintColor =
    isDark ? Colors.white54 : Colors.grey;

    final Color iconColor =
    isDark ? Colors.white60 : Colors.grey;

    final Color handleColor =
    isDark ? const Color(0xFF555555) : Colors.grey.shade300;

    final Color colorBorder =
    isDark ? const Color(0xFF555555) : Colors.grey.shade300;

    // 기기 캘린더(삼성캘린더 등) 연동 일정인지 확인하는 플래그
    final bool isDeviceCalendar =
        widget.schedule['is_device_calendar'] == true ||
            widget.schedule['is_samsung'] == true ||
            (widget.schedule['calendar_event_id'] != null &&
                widget.schedule['calendar_event_id']
                    .toString()
                    .isNotEmpty);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      decoration: BoxDecoration(
        color: sheetBackground,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 상단 바텀시트 인디케이터
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: handleColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // 제목 입력 + 삭제 버튼
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: fieldBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: borderColor,
                        ),
                      ),
                      child: TextField(
                        controller: _titleController,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: titleColor,
                        ),
                        decoration: InputDecoration(
                          hintText: "일정 제목 입력",
                          hintStyle: TextStyle(
                            color: hintColor,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                  ),

                  // 삼성캘린더/디바이스 캘린더 일정이 아닐 때만 삭제 버튼
                  if (!isDeviceCalendar) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                      ),
                      onPressed: () => _deleteSchedule(context),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 20),

              // 일정 색상
              Row(
                children: [
                  Text(
                    "일정 색상",
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: titleColor,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _showColorPickerPopup,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Color(_currentColor),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colorBorder,
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // 장소 입력
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: fieldBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: borderColor,
                  ),
                ),
                child: TextField(
                  controller: _locationController,
                  readOnly: true,
                  onTap: _openMapSelection,
                  style: TextStyle(
                    fontSize: 15,
                    color: titleColor,
                  ),
                  decoration: InputDecoration(
                    icon: Icon(
                      Icons.location_on_outlined,
                      color: iconColor,
                      size: 20,
                    ),
                    hintText: "장소 추가",
                    hintStyle: TextStyle(
                      color: hintColor,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 강제 모드
              SwitchListTile(
                title: Text(
                  "강제모드 (일정 집중)",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: titleColor,
                  ),
                ),
                value: _isForcedMode,
                activeColor: const Color(0xFF6FD0F1),
                contentPadding: EdgeInsets.zero,
                onChanged: (val) {
                  setState(() {
                    _isForcedMode = val;
                  });
                },
              ),

              const SizedBox(height: 24),

              // 저장 버튼
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6FD0F1),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isLoading
                      ? null
                      : () => _updateScheduleChanges(context),
                  child: _isLoading
                      ? const CircularProgressIndicator(
                    color: Colors.white,
                  )
                      : const Text(
                    "저장하기",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }}