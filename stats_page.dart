import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'n8n.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  // ─────────────────────────────────────────────
  // THEME
  // ─────────────────────────────────────────────

  final Color primary = const Color(0xFF5B5FEF);
  final Color primaryLight = const Color(0xFFEDEEFF);
  final Color background = const Color(0xFFF7F8FC);
  final Color card = Colors.white;
  final Color text = const Color(0xFF171A2B);
  final Color subText = const Color(0xFF8A8FA3);
  final Color green = const Color(0xFF20B486);
  final Color orange = const Color(0xFFFFA62B);
  final Color red = const Color(0xFFFF5C69);
  final Color purple = const Color(0xFF8B5CF6);

  // ─────────────────────────────────────────────
  // STATE
  // ─────────────────────────────────────────────

  bool _isAnalyzing = false;
  bool _isLoadingSessions = true;

  String? _aiFeedbackResult;

  String _currentUserName = '이름';
  String _currentUserGoal = '목표';

  int _selectedTab = 0;

  DateTime _dayDate = DateTime.now();
  DateTime _weekDate = DateTime.now();
  DateTime _monthDate = DateTime.now();

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _cachedSessions = [];

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _loadAllSessions();

  }

  // ─────────────────────────────────────────────
  // FIRESTORE
  // ─────────────────────────────────────────────

  Future<void> _loadUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('user_profile')
          .doc('current')
          .get();

      final data = doc.data();

      if (!mounted || data == null) return;

      setState(() {
        _currentUserName =
        data['name']?.toString().trim().isNotEmpty == true
            ? data['name'].toString()
            : '이름';

        _currentUserGoal =
        data['goal']?.toString().trim().isNotEmpty == true
            ? data['goal'].toString()
            : '목표';
      });
    } catch (e) {
      debugPrint('프로필 로드 실패: $e');
    }
  }

  Future<void> _loadAllSessions() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (mounted) {
        setState(() {
          _cachedSessions = [];
          _isLoadingSessions = false;
        });
      }
      return;
    }

    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('study_sessions');

    try {
      // start_time으로 orderBy하지 않고 모든 세션을 가져온다.
      // 일부 문서에 start_time이 없거나 형식이 달라도 누락되지 않게 한다.
      final snapshot = await ref.get();

      final docs = snapshot.docs.toList();

      // 최신 날짜순으로 앱에서 직접 정렬
      docs.sort((a, b) {
        final dateA = _parseSessionDate(a.data());
        final dateB = _parseSessionDate(b.data());

        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;

        return dateB.compareTo(dateA);
      });

      debugPrint('study_sessions 총 ${docs.length}개 로드');

      for (final doc in docs) {
        final data = doc.data();

        debugPrint(
          '세션 ${doc.id} | '
              'date=${data['date']} | '
              'study_minutes=${data['study_minutes']} | '
              'is_success=${data['is_success']} | '
              'is_failed=${data['is_failed']}',
        );
      }

      if (!mounted) return;

      setState(() {
        _cachedSessions = docs;
        _isLoadingSessions = false;
      });
    } catch (e, stackTrace) {
      debugPrint('study_sessions 로드 실패: $e');
      debugPrint('$stackTrace');

      if (!mounted) return;

      setState(() {
        _cachedSessions = [];
        _isLoadingSessions = false;
      });
    }
  }

  Future<bool> _consumeAiPoint() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      debugPrint('로그인된 사용자가 없습니다.');
      return false;
    }

    final pointRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('user_profile')
        .doc('current');

    try {
      return await FirebaseFirestore.instance
          .runTransaction<bool>((transaction) async {
        final snapshot = await transaction.get(pointRef);

        if (!snapshot.exists) {
          debugPrint('user_profile/current 문서가 존재하지 않습니다.');
          return false;
        }

        final data = snapshot.data();

        if (data == null) {
          debugPrint('프로필 데이터가 없습니다.');
          return false;
        }

        // 파이어베이스 구조의 'point' 필드 우선 타겟팅 (없으면 'points' 체크)[cite: 9]
        dynamic rawPoint = data['point'];
        if (rawPoint == null && data.containsKey('points')) {
          rawPoint = data['points'];
        }

        int currentPoint = 0;
        if (rawPoint is num) {
          currentPoint = rawPoint.toInt();
        } else if (rawPoint is String) {
          currentPoint = int.tryParse(rawPoint.trim()) ?? 0;
        }

        debugPrint('현재 보유 포인트: $currentPoint P');

        // AI 분석 필요 포인트 (1000P)
        const int requiredPoint = 1000;

        // 포인트 부족 여부 검증 로직 추가
        if (currentPoint < requiredPoint) {
          debugPrint('포인트 부족: 현재 $currentPoint P / 필요 $requiredPoint P');
          return false;
        }

        final int remainingPoint = currentPoint - requiredPoint;

        // 트랜잭션으로 DB의 point 및 points 필드 1000 차감 반영[cite: 9]
        transaction.update(pointRef, {
          'point': remainingPoint,
          'points': remainingPoint,
          'updated_at': FieldValue.serverTimestamp(),
        });

        debugPrint('포인트 차감 성공: $currentPoint P → $remainingPoint P');
        return true;
      });
    } catch (e, stackTrace) {
      debugPrint('AI 포인트 차감 중 오류 발생: $e');
      debugPrint('$stackTrace');
      return false;
    }
  }

  Future<void> _showNeedAdDialog() async {
    if (!mounted) return;

    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color dialogBackground =
    isDark ? const Color(0xFF1E1E1E) : card;

    final Color primaryText =
    isDark ? Colors.white : text;

    final Color secondaryText =
    isDark ? Colors.white70 : subText;

    final Color iconBackground =
    isDark ? const Color(0xFF292929) : primaryLight;

    await showDialog(
      context: context,
      builder: (_) {
        return Dialog(
          backgroundColor: dialogBackground,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 28, 26, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: iconBackground,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    color: primary,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  '포인트가 부족해요',
                  style: TextStyle(
                    color: primaryText,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  'AI 학습 분석을 이용하려면\n1000P가 필요합니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: secondaryText,
                    height: 1.5,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    child: const Text(
                      '확인',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  // ─────────────────────────────────────────────
  // DATE
  // ─────────────────────────────────────────────

  Map<String, dynamic> _getDateRangeInfo() {
    DateTime start;
    DateTime end;
    String label;

    if (_selectedTab == 0) {
      start = DateTime(
        _dayDate.year,
        _dayDate.month,
        _dayDate.day,
      );

      end = start.add(const Duration(days: 1));

      label = DateFormat(
        'yyyy.MM.dd',
      ).format(start);
    } else if (_selectedTab == 1) {
      start = DateTime(
        _weekDate.year,
        _weekDate.month,
        _weekDate.day,
      ).subtract(
        Duration(days: _weekDate.weekday - 1),
      );

      end = start.add(const Duration(days: 7));

      label =
      '${DateFormat('MM.dd').format(start)} - '
          '${DateFormat('MM.dd').format(end.subtract(const Duration(days: 1)))}';
    } else {
      start = DateTime(
        _monthDate.year,
        _monthDate.month,
        1,
      );

      end = DateTime(
        _monthDate.year,
        _monthDate.month + 1,
        1,
      );

      label = DateFormat(
        'yyyy년 M월',
      ).format(start);
    }

    return {
      'start': start,
      'end': end,
      'label': label,
    };
  }

  void _moveDate(int step) {
    setState(() {
      switch (_selectedTab) {
        case 0:
          _dayDate = DateTime(
            _dayDate.year,
            _dayDate.month,
            _dayDate.day + step,
          );
          break;

        case 1:
          _weekDate = DateTime(
            _weekDate.year,
            _weekDate.month,
            _weekDate.day + (7 * step),
          );
          break;

        case 2:
          _monthDate = DateTime(
            _monthDate.year,
            _monthDate.month + step,
            1,
          );
          break;
      }
    });
  }
  // ─────────────────────────────────────────────
  // SESSION DATE
  // ─────────────────────────────────────────────

  DateTime? _parseSessionDate(
      Map<String, dynamic> data,
      ) {
    // 1순위: 실제 공부 날짜
    final rawDate = data['date'];

    if (rawDate is Timestamp) {
      final date = rawDate.toDate();

      return DateTime(
        date.year,
        date.month,
        date.day,
      );
    }

    if (rawDate is DateTime) {
      return DateTime(
        rawDate.year,
        rawDate.month,
        rawDate.day,
      );
    }

    if (rawDate is String) {
      final value = rawDate.trim();

      if (value.isNotEmpty) {
        // yyyy-MM-dd
        final match = RegExp(
          r'^(\d{4})-(\d{1,2})-(\d{1,2})',
        ).firstMatch(value);

        if (match != null) {
          final year = int.tryParse(match.group(1)!);
          final month = int.tryParse(match.group(2)!);
          final day = int.tryParse(match.group(3)!);

          if (year != null &&
              month != null &&
              day != null) {
            return DateTime(
              year,
              month,
              day,
            );
          }
        }

        // ISO 날짜 등 다른 문자열 형식
        final parsed = DateTime.tryParse(value);

        if (parsed != null) {
          return DateTime(
            parsed.year,
            parsed.month,
            parsed.day,
          );
        }
      }
    }

    // 2순위: start_time
    final rawStartTime = data['start_time'];

    if (rawStartTime is Timestamp) {
      final date = rawStartTime.toDate();

      return DateTime(
        date.year,
        date.month,
        date.day,
      );
    }

    if (rawStartTime is DateTime) {
      return DateTime(
        rawStartTime.year,
        rawStartTime.month,
        rawStartTime.day,
      );
    }

    if (rawStartTime is String) {
      final value = rawStartTime.trim();

      if (value.isNotEmpty) {
        final parsed = DateTime.tryParse(value);

        if (parsed != null) {
          return DateTime(
            parsed.year,
            parsed.month,
            parsed.day,
          );
        }
      }
    }

    // 3순위: created_at
    final rawCreatedAt = data['created_at'];

    if (rawCreatedAt is Timestamp) {
      final date = rawCreatedAt.toDate();

      return DateTime(
        date.year,
        date.month,
        date.day,
      );
    }

    if (rawCreatedAt is DateTime) {
      return DateTime(
        rawCreatedAt.year,
        rawCreatedAt.month,
        rawCreatedAt.day,
      );
    }

    if (rawCreatedAt is String) {
      final parsed = DateTime.tryParse(
        rawCreatedAt.trim(),
      );

      if (parsed != null) {
        return DateTime(
          parsed.year,
          parsed.month,
          parsed.day,
        );
      }
    }

    return null;
  }

  int _toInt(dynamic value) {
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
      value?.toString() ?? '',
    ) ??
        0;
  }

  // ─────────────────────────────────────────────
  // STATISTICS
  // ─────────────────────────────────────────────

  Future<Map<String, dynamic>> _loadStats() async {
    final rangeInfo = _getDateRangeInfo();

    final DateTime rangeStart = rangeInfo['start'] as DateTime;
    final DateTime rangeEnd = rangeInfo['end'] as DateTime;

    final filteredSessions = _cachedSessions.where((doc) {
      final data = doc.data();
      final sessionDate = _parseSessionDate(data);

      if (sessionDate == null) return false;

      return !sessionDate.isBefore(rangeStart) &&
          sessionDate.isBefore(rangeEnd);
    }).toList();

    int totalMinutes = 0;
    int successCount = 0;
    int failCount = 0;
    int totalDepartureCount = 0;

    double accumulatedFocusScore = 0;

    final Map<int, int> hourlyDistribution = {};

    for (final doc in filteredSessions) {
      final data = doc.data();

      final int studyMinutes = _toInt(data['study_minutes']);
      final int departureCount = _toInt(data['departure_count']);
      final bool isSuccess = data['is_success'] == true;
      final bool isFailed = data['is_failed'] == true;

      totalMinutes += studyMinutes;
      totalDepartureCount += departureCount;

      if (isSuccess) {
        successCount++;
      }

      if (isFailed) {
        failCount++;
      }

      // 자리 이탈 횟수 및 성공/실패 여부를 통한 세션별 집중도 점수 산출
      double focusScore = 100.0;
      focusScore -= departureCount * 10.0; // 자리 이탈 1회당 -10점

      if (isFailed) {
        focusScore -= 30.0; // 중단/포기 시 -30점 추가
      }

      if (isSuccess) {
        focusScore += 10.0; // 성공 세션은 +10점 가산
      }

      accumulatedFocusScore += focusScore.clamp(0.0, 100.0);

      // 시간대별 학습량 집계
      final startTime = _parseSessionStartTime(data);
      if (startTime != null && studyMinutes > 0) {
        hourlyDistribution[startTime.hour] =
            (hourlyDistribution[startTime.hour] ?? 0) + studyMinutes;
      }
    }

    final int analyzedCount = filteredSessions.length;

    final int avgFocusRate = analyzedCount == 0
        ? 0
        : (accumulatedFocusScore / analyzedCount)
        .round()
        .clamp(0, 100);

    // 실패율과 이탈 수 기반 위험도 산출
    int riskScore = 0;
    if (analyzedCount > 0) {
      final double failRatio = (failCount / analyzedCount) * 50;
      final int departurePenalty = (totalDepartureCount * 5).clamp(0, 30);
      final int inconsistencyPenalty = analyzedCount < 2 ? 20 : 0;

      riskScore = (failRatio + departurePenalty + inconsistencyPenalty)
          .round()
          .clamp(0, 100);
    }

    // 최다 집중 시간대(골든타임) 도출
    int bestHour = 9;
    int maxHourMinutes = 0;

    hourlyDistribution.forEach((hour, minutes) {
      if (minutes > maxHourMinutes) {
        maxHourMinutes = minutes;
        bestHour = hour;
      }
    });

    String bestFocusTime;
    if (analyzedCount == 0 || maxHourMinutes == 0) {
      bestFocusTime = '데이터 없음';
    } else if (bestHour >= 6 && bestHour < 12) {
      bestFocusTime = '오전 ${bestHour}시';
    } else if (bestHour >= 12 && bestHour < 18) {
      bestFocusTime = '오후 ${bestHour}시';
    } else if (bestHour >= 18 && bestHour < 22) {
      bestFocusTime = '저녁 ${bestHour}시';
    } else {
      bestFocusTime = '새벽 ${bestHour}시';
    }

    final int successRate = analyzedCount == 0
        ? 0
        : ((successCount / analyzedCount) * 100).round().clamp(0, 100);

    final double averageDepartureCount =
    analyzedCount == 0 ? 0 : totalDepartureCount / analyzedCount;

    return {
      'chartData': _processChartData(filteredSessions),
      'totalStudyMinutes': totalMinutes,
      'totalStudyHours': totalMinutes / 60,
      'successCount': successCount,
      'failCount': failCount,
      'successRate': successRate,
      'avgFocusRate': avgFocusRate,
      'analyzedSessions': analyzedCount,
      'totalRiskScore': riskScore,
      'totalDepartureCount': totalDepartureCount,
      'averageDepartureCount': averageDepartureCount,
      'bestHour': '${bestHour.toString().padLeft(2, '0')}:00',
      'bestFocusTime': bestFocusTime,
    };
  }

  DateTime? _parseSessionStartTime(
      Map<String, dynamic> data,
      ) {
    final rawStartTime = data['start_time'];

    final DateTime? sessionDate =
    _parseSessionDate(data);

    // ─────────────────────────────────────
    // 1. Firestore Timestamp
    // ─────────────────────────────────────
    if (rawStartTime is Timestamp) {
      final dateTime = rawStartTime.toDate().toLocal();

      return dateTime;
    }

    // ─────────────────────────────────────
    // 2. DateTime
    // ─────────────────────────────────────
    if (rawStartTime is DateTime) {
      return rawStartTime.toLocal();
    }

    // ─────────────────────────────────────
    // 3. String
    // ─────────────────────────────────────
    if (rawStartTime is String) {
      String value = rawStartTime.trim();

      if (value.isEmpty) {
        return sessionDate;
      }

      // 앞뒤 따옴표 제거
      value = value.replaceAll('"', '').trim();

      // ─────────────────────────────────
      // 3-1. 완전한 날짜 + 시간
      //
      // 2026-09-22 19:00:00
      // 2026-09-22T19:00:00
      // ─────────────────────────────────
      final fullDateTime = DateTime.tryParse(value);

      if (fullDateTime != null) {
        return fullDateTime.toLocal();
      }

      // ─────────────────────────────────
      // 3-2. "19:00"
      // 3-3. "19:00:00"
      // 3-4. "07:00"
      // ─────────────────────────────────
      final timeMatch = RegExp(
        r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$',
      ).firstMatch(value);

      if (timeMatch != null) {
        final int? hour =
        int.tryParse(timeMatch.group(1)!);

        final int? minute =
        int.tryParse(timeMatch.group(2)!);

        final int second =
            int.tryParse(
              timeMatch.group(3) ?? '0',
            ) ??
                0;

        if (hour != null &&
            minute != null &&
            hour >= 0 &&
            hour <= 23 &&
            minute >= 0 &&
            minute <= 59 &&
            second >= 0 &&
            second <= 59) {
          final baseDate =
              sessionDate ?? DateTime.now();

          return DateTime(
            baseDate.year,
            baseDate.month,
            baseDate.day,
            hour,
            minute,
            second,
          );
        }
      }

      // ─────────────────────────────────
      // 3-5. 오전/오후 형식
      //
      // 오전 7:00
      // 오후 7:00
      // 오전 07:30:00
      // ─────────────────────────────────
      final koreanTimeMatch = RegExp(
        r'^(오전|오후)\s*(\d{1,2}):(\d{2})(?::(\d{2}))?$',
      ).firstMatch(value);

      if (koreanTimeMatch != null) {
        final String period =
        koreanTimeMatch.group(1)!;

        int? hour =
        int.tryParse(koreanTimeMatch.group(2)!);

        final int? minute =
        int.tryParse(koreanTimeMatch.group(3)!);

        final int second =
            int.tryParse(
              koreanTimeMatch.group(4) ?? '0',
            ) ??
                0;

        if (hour != null &&
            minute != null &&
            hour >= 1 &&
            hour <= 12 &&
            minute >= 0 &&
            minute <= 59 &&
            second >= 0 &&
            second <= 59) {
          if (period == '오후' && hour != 12) {
            hour += 12;
          }

          if (period == '오전' && hour == 12) {
            hour = 0;
          }

          final baseDate =
              sessionDate ?? DateTime.now();

          return DateTime(
            baseDate.year,
            baseDate.month,
            baseDate.day,
            hour,
            minute,
            second,
          );
        }
      }

      // ─────────────────────────────────
      // 3-6. AM / PM 형식
      //
      // 7:00 PM
      // 07:00 PM
      // 7:00:00 PM
      // ─────────────────────────────────
      final amPmMatch = RegExp(
        r'^(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(AM|PM)$',
        caseSensitive: false,
      ).firstMatch(value);

      if (amPmMatch != null) {
        int? hour =
        int.tryParse(amPmMatch.group(1)!);

        final int? minute =
        int.tryParse(amPmMatch.group(2)!);

        final int second =
            int.tryParse(
              amPmMatch.group(3) ?? '0',
            ) ??
                0;

        final String period =
        amPmMatch.group(4)!.toUpperCase();

        if (hour != null &&
            minute != null &&
            hour >= 1 &&
            hour <= 12 &&
            minute >= 0 &&
            minute <= 59 &&
            second >= 0 &&
            second <= 59) {
          if (period == 'PM' && hour != 12) {
            hour += 12;
          }

          if (period == 'AM' && hour == 12) {
            hour = 0;
          }

          final baseDate =
              sessionDate ?? DateTime.now();

          return DateTime(
            baseDate.year,
            baseDate.month,
            baseDate.day,
            hour,
            minute,
            second,
          );
        }
      }
    }

    // ─────────────────────────────────────
    // 4. start_time을 못 읽은 경우
    // end_time 또는 study_minutes를 활용하여 역산
    // ─────────────────────────────────────
    final rawEndTime = data['end_time'];
    final studyMinutes = _toInt(data['study_minutes']);

    DateTime? endDateTime;

    if (rawEndTime is Timestamp) {
      endDateTime = rawEndTime.toDate().toLocal();
    } else if (rawEndTime is DateTime) {
      endDateTime = rawEndTime.toLocal();
    } else if (rawEndTime is String) {
      endDateTime = DateTime.tryParse(rawEndTime.trim())?.toLocal();
    }

    if (endDateTime != null) {
      return endDateTime.subtract(Duration(minutes: studyMinutes));
    }

    return sessionDate;
  }

  Map<int, double> _processChartData(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
    final Map<int, double> chartData = {};

    for (final doc in docs) {
      final data = doc.data();
      final int minutes = _toInt(data['study_minutes']);

      if (minutes <= 0) continue;

      if (_selectedTab == 0) {
        // 일간: 시간대별 (0~23시)
        final startTime = _parseSessionStartTime(data);
        if (startTime == null) continue;

        final int hour = startTime.hour;
        chartData[hour] = (chartData[hour] ?? 0) + minutes.toDouble();
      } else {
        final date = _parseSessionDate(data);
        if (date == null) continue;

        if (_selectedTab == 1) {
          // 주간: 요일별 (1=월 ~ 7=일)
          final int weekday = date.weekday;
          chartData[weekday] = (chartData[weekday] ?? 0) + minutes.toDouble();
        } else {
          // 월간: 일별 (1~31일)
          final int day = date.day;
          chartData[day] = (chartData[day] ?? 0) + minutes.toDouble();
        }
      }
    }

    return chartData;
  }  // ─────────────────────────────────────────────
  // AI
  // ─────────────────────────────────────────────
  String? _latestAiFeedbackDocId;
  Future<void> _requestAiFeedback() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null || _isAnalyzing) return;

    if (mounted) {
      setState(() {
        _isAnalyzing = true;
        _aiFeedbackResult = null;
        _latestAiFeedbackDocId = null;
      });
    }

    try {
      final stats = await _loadStats();

      final firestore = FirebaseFirestore.instance;

      // 1. 일기 수집
      final diariesSnapshot = await firestore
          .collection('users')
          .doc(user.uid)
          .collection('study_diaries')
          .orderBy('date', descending: true)
          .limit(30)
          .get();

      final diaries = <String>[];
      final emotions = <String>[];

      for (final doc in diariesSnapshot.docs) {
        final data = doc.data();

        final review =
            data['study_review']?.toString().trim() ?? '';

        final emotion =
            data['emotion']?.toString().trim() ?? '';

        if (review.isNotEmpty) {
          diaries.add(review);
        }

        if (emotion.isNotEmpty) {
          emotions.add(emotion);
        }
      }

      // 2. 포기 원인 수집
      final failReasons = <String>[];

      for (final doc in _cachedSessions) {
        final data = doc.data();

        if (data['is_failed'] == true) {
          final reason =
              data['give_up_reason']?.toString().trim() ?? '';

          if (reason.isNotEmpty) {
            failReasons.add(reason);
          }
        }
      }

      // 3. 프로필 정보
      final profileSnapshot = await firestore
          .collection('users')
          .doc(user.uid)
          .collection('user_profile')
          .doc('current')
          .get();

      final profileData =
          profileSnapshot.data() ?? {};

      // 4. 기존 AI 피드백 후기 수집
      final previousFeedbackSnapshot = await firestore
          .collection('users')
          .doc(user.uid)
          .collection('ai_feedback_diaries')
          .get();

      for (final doc in previousFeedbackSnapshot.docs) {
        final data = doc.data();

        final reviews = data['ai_feedback_reviews'];

        if (reviews is! List) continue;

        for (final item in reviews) {
          if (item is! Map) continue;

          final review =
              item['review']?.toString().trim() ?? '';

          final isAccurate =
              item['is_accurate'] == true;

          if (review.isNotEmpty) {
            diaries.add(
              '[이전 AI 피드백 사용자 후기] '
                  '${isAccurate ? 'AI 피드백이 실제 공부 상황과 일치함' : 'AI 피드백이 실제 공부 상황과 다름'}\n'
                  '사용자 후기: $review',
            );
          }
        }
      }

      // 5. AI 분석
      final result = await runN8nAnalysis(
        userName: _currentUserName,
        userGoal: _currentUserGoal,
        threshold: _toInt(stats['totalRiskScore']),
        bestHour: int.tryParse(
          stats['bestHour']
              .toString()
              .split(':')
              .first,
        ) ?? 0,
        totalHours:
        stats['totalStudyHours'] ?? 0,
        diaries: diaries,
        emotions: emotions,
        failReasons: failReasons,
        homeAddress:
        profileData['home_address']?.toString() ?? '',
        birthDate: '',
        birthTime: '',
        bestFocusTime:
        stats['bestFocusTime']?.toString() ?? '',
        analyzedSessions:
        _toInt(stats['analyzedSessions']),
      );

      final String feedbackContent =
      result?.trim().isNotEmpty == true
          ? result!.trim()
          : 'AI 분석 결과가 없습니다.';

      // 6. AI 피드백 문서 생성
      //
      // 문서 ID를 직접 생성하고 변수에 저장한다.
      // 이후 후기 저장할 때 이 ID를 그대로 사용한다.
      final feedbackRef = firestore
          .collection('users')
          .doc(user.uid)
          .collection('ai_feedback_diaries')
          .doc();

      final feedbackDocId = feedbackRef.id;

      await feedbackRef.set({
        'request_date': feedbackContent,
        'ai_feedback_reviews': [],
        'created_at': FieldValue.serverTimestamp(),
      });

      // 후기 저장용으로 정확한 문서 ID 기억
      if (mounted) {
        setState(() {
          _latestAiFeedbackDocId = feedbackDocId;
        });
      }

      debugPrint(
        'AI 피드백 저장 완료'
            ' / documentId=$feedbackDocId',
      );

      // 7. 포인트 차감
      final hasPoint = await _consumeAiPoint();

      if (!hasPoint) {
        if (!mounted) return;

        setState(() {
          _aiFeedbackResult =
          'AI 분석은 완료되었지만 포인트가 부족하여\n'
              '결과 이용이 처리되지 않았습니다.';
        });

        _showSnack(
          'AI 분석에 필요한 1000P가 부족합니다.',
        );

        return;
      }

      if (!mounted) return;

      setState(() {
        _aiFeedbackResult = feedbackContent;
      });

      _showSnack(
        '1000P가 차감되고 AI 학습 분석이 완료되었습니다.',
      );
    } catch (e, stackTrace) {
      debugPrint('AI 분석 오류: $e');
      debugPrint('$stackTrace');

      if (!mounted) return;

      setState(() {
        _aiFeedbackResult =
        'AI 서버 연결에 실패했습니다.\n'
            '잠시 후 다시 시도해주세요.';
      });

      _showSnack(
        'AI 분석 중 오류가 발생했습니다.',
      );
    } finally {
      if (!mounted) return;

      setState(() {
        _isAnalyzing = false;
      });
    }
  }  String? _currentAiFeedbackDocId;


  Future<void> _saveAiFeedbackReview({
    required bool isAccurate,
    required String review,
  }) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      debugPrint('후기 저장 실패: 로그인된 사용자가 없습니다.');
      return;
    }

    final trimmedReview = review.trim();

    if (trimmedReview.isEmpty) {
      _showSnack('후기를 입력해주세요.');
      return;
    }

    // AI 분석을 통해 생성된 정확한 문서 ID
    final feedbackDocId = _latestAiFeedbackDocId;

    if (feedbackDocId == null ||
        feedbackDocId.trim().isEmpty) {
      debugPrint(
        '후기 저장 실패: 최근 AI 피드백 문서 ID가 없습니다.',
      );

      _showSnack(
        'AI 피드백 정보를 찾을 수 없습니다.\n'
            'AI 분석을 다시 실행해주세요.',
      );

      return;
    }

    try {
      final firestore =
          FirebaseFirestore.instance;

      // 정확히 이번에 생성된 AI 피드백 문서
      final feedbackRef = firestore
          .collection('users')
          .doc(user.uid)
          .collection('ai_feedback_diaries')
          .doc(feedbackDocId);

      // 문서 존재 여부 확인
      final feedbackSnapshot =
      await feedbackRef.get();

      if (!feedbackSnapshot.exists) {
        debugPrint(
          '후기 저장 실패: AI 피드백 문서가 존재하지 않습니다.'
              ' / $feedbackDocId',
        );

        _showSnack(
          'AI 피드백 문서를 찾을 수 없습니다.',
        );

        return;
      }

      // 사용자가 입력한 후기
      final reviewData = <String, dynamic>{
        'review': trimmedReview,
        'is_accurate': isAccurate,
        'created_at': Timestamp.now(),
      };

      // 기존 후기 배열을 읽는다.
      final data =
          feedbackSnapshot.data() ?? {};

      final List<dynamic> existingReviews =
      data['ai_feedback_reviews'] is List
          ? List<dynamic>.from(
        data['ai_feedback_reviews'],
      )
          : [];

      // 새로운 사용자 후기 추가
      existingReviews.add(reviewData);

      // 해당 AI 피드백 문서에 저장
      await feedbackRef.update({
        'ai_feedback_reviews': existingReviews,
      });

      debugPrint(
        'AI 피드백 후기 저장 성공'
            ' / documentId=$feedbackDocId'
            ' / review=$trimmedReview'
            ' / isAccurate=$isAccurate',
      );

      if (!mounted) return;

      _showSnack(
        'AI 피드백 후기가 저장되었습니다.',
      );
    } catch (e, stackTrace) {
      debugPrint(
        'AI 피드백 후기 저장 실패: $e',
      );
      debugPrint('$stackTrace');

      if (!mounted) return;

      _showSnack(
        '후기 저장에 실패했습니다.',
      );
    }
  }



  void _showSnack(String message) {
    if (!mounted) return;

    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color snackBackground =
    isDark ? const Color(0xFFE5E7EB) : text;

    final Color snackText =
    isDark ? const Color(0xFF111827) : Colors.white;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: snackText,
          ),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: snackBackground,
        margin: const EdgeInsets.fromLTRB(
          18,
          0,
          18,
          18,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
      ),
    );
  }
  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color screenBackground =
    isDark ? const Color(0xFF121212) : background;

    final rangeInfo = _getDateRangeInfo();

    return Scaffold(
      backgroundColor: screenBackground,
      body: SafeArea(
        child: _isLoadingSessions
            ? Center(
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: primary,
          ),
        )
            : RefreshIndicator(
          color: primary,
          onRefresh: () async {
            await Future.wait([
              _loadUserProfile(),
              _loadAllSessions(),
            ]);
          },
          child: FutureBuilder<Map<String, dynamic>>(
            future: _loadStats(),
            builder: (
                context,
                snapshot,
                ) {
              if (snapshot.connectionState ==
                  ConnectionState.waiting) {
                return Center(
                  child: CircularProgressIndicator(
                    color: primary,
                  ),
                );
              }

              if (snapshot.hasError) {
                return Center(
                  child: Text(
                    '통계 데이터를 불러오지 못했습니다.',
                    style: TextStyle(
                      color:
                      isDark ? Colors.white70 : subText,
                    ),
                  ),
                );
              }

              final data =
                  snapshot.data ?? <String, dynamic>{};

              return SingleChildScrollView(
                physics:
                const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(
                  20,
                  10,
                  20,
                  36,
                ),
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),

                    const SizedBox(height: 20),

                    _buildPeriodSelector(),

                    const SizedBox(height: 14),

                    _buildDateNavigator(
                      rangeInfo['label'].toString(),
                    ),

                    const SizedBox(height: 20),

                    _buildChartCard(
                      (data['chartData']
                      as Map<int, double>?) ??
                          <int, double>{},
                    ),

                    const SizedBox(height: 22),

                    _buildStatSummary(
                      data['totalStudyMinutes'] ?? 0,
                      _toInt(data['successCount']),
                      _toInt(data['failCount']),
                      _toInt(data['avgFocusRate']),
                    ),

                    const SizedBox(height: 20),

                    _buildInsightCard(data),

                    const SizedBox(height: 20),

                    _buildAiCard(data),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }  // ─────────────────────────────────────────────
  // HEADER
  // ─────────────────────────────────────────────


  Widget _buildChartCard(Map<int, double> chartData) {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color primaryText =
    isDark ? Colors.white : text;

    final Color secondaryText =
    isDark ? Colors.white70 : subText;

    final double maxValue = chartData.values.isEmpty
        ? 1.0
        : max(
      chartData.values.reduce(max),
      1.0,
    );

    final List<int> keys;

    if (_selectedTab == 0) {
      // 일간 → 0~23시
      keys = List.generate(24, (i) => i);
    } else if (_selectedTab == 1) {
      // 주간 → 월~일
      keys = [1, 2, 3, 4, 5, 6, 7];
    } else {
      // 월간 → 1~12월
      keys = List.generate(12, (i) => i + 1);
    }

    Widget buildBarItem(int key) {
      final double value = chartData[key] ?? 0.0;

      final double ratio =
      (value / maxValue).clamp(0.0, 1.0);

      final double barWidth = _selectedTab == 0
          ? 10.0
          : _selectedTab == 1
          ? 16.0
          : 12.0;

      return SizedBox(
        width: _selectedTab == 0 ? 34 : null,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            SizedBox(
              height: 16,
              child: value > 0
                  ? Text(
                '${value.round()}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: primaryText,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              )
                  : null,
            ),

            const SizedBox(height: 6),

            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              width: barWidth,
              height: value <= 0
                  ? 4
                  : max(4.0, ratio * 95),
              decoration: BoxDecoration(
                color: value <= 0
                    ? primary.withOpacity(
                  isDark ? 0.20 : 0.12,
                )
                    : primary,
                borderRadius: BorderRadius.circular(6),
              ),
            ),

            const SizedBox(height: 8),

            Text(
              _chartLabel(key),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: secondaryText,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _selectedTab == 0
                      ? '시간대별 학습량'
                      : _selectedTab == 1
                      ? '요일별 학습량'
                      : '월별 학습량',
                  style: TextStyle(
                    color: primaryText,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '공부시간(분)',
                    style: TextStyle(
                      color: secondaryText,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 20),

          SizedBox(
            height: 160,
            child: _selectedTab == 0
                ? SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics:
              const BouncingScrollPhysics(),
              child: Row(
                crossAxisAlignment:
                CrossAxisAlignment.end,
                children: keys.map((key) {
                  return Padding(
                    padding:
                    const EdgeInsets.symmetric(
                      horizontal: 6,
                    ),
                    child: buildBarItem(key),
                  );
                }).toList(),
              ),
            )
                : Row(
              mainAxisAlignment:
              MainAxisAlignment.spaceAround,
              crossAxisAlignment:
              CrossAxisAlignment.end,
              children: keys
                  .map(
                    (key) => buildBarItem(key),
              )
                  .toList(),
            ),
          ),

          const SizedBox(height: 4),

          if (chartData.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: Text(
                  '해당 기간의 학습 데이터가 없습니다.',
                  style: TextStyle(
                    color: secondaryText,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }



  Widget _buildHeader() {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color primaryText =
    isDark ? Colors.white : text;

    final Color secondaryText =
    isDark ? Colors.white70 : subText;

    final Color iconBackground =
    isDark ? const Color(0xFF1E1E1E) : card;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 7),
              Text(
                '학습 통계',
                style: TextStyle(
                  color: primaryText,
                  fontSize: 29,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.2,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${_currentUserName}님의 공부 흐름을 확인해보세요.',
                style: TextStyle(
                  color: secondaryText,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: iconBackground,
            borderRadius: BorderRadius.circular(17),
            boxShadow: isDark
                ? []
                : [
              BoxShadow(
                color: Colors.black.withOpacity(.04),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Icon(
            Icons.bar_chart_rounded,
            color: primary,
            size: 24,
          ),
        ),
      ],
    );
  }
  // ─────────────────────────────────────────────
  // OVERVIEW
  // ─────────────────────────────────────────────


  Widget _overviewSmallStat(
      IconData icon,
      String value,
      String label,
      ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(.12),
          borderRadius: BorderRadius.circular(17),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: Colors.white,
              size: 17,
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  // PERIOD SELECTOR
  // ─────────────────────────────────────────────

  Widget _buildPeriodSelector() {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color borderColor =
    isDark ? const Color(0xFF383838) : const Color(0xFFEDEEF4);

    return Container(
      height: 52,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : card,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: borderColor,
        ),
      ),
      child: Row(
        children: [
          _periodItem(0, '일간'),
          _periodItem(1, '주간'),
          _periodItem(2, '월간'),
        ],
      ),
    );
  }


  Widget _periodItem(
      int index,
      String title,
      ) {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final bool selected = _selectedTab == index;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (_selectedTab == index) return;

            setState(() {
              _selectedTab = index;
            });
          },
          borderRadius: BorderRadius.circular(13),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: selected
                  ? primary
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Center(
              child: Text(
                title,
                style: TextStyle(
                  color: selected
                      ? Colors.white
                      : isDark
                      ? Colors.white70
                      : subText,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
  // ─────────────────────────────────────────────
  // DATE NAVIGATOR
  // ─────────────────────────────────────────────

  Widget _buildDateNavigator(String label) {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        _navButton(
          Icons.chevron_left_rounded,
              () => _moveDate(-1),
        ),
        Expanded(
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDark ? Colors.white : text,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ),
        _navButton(
          Icons.chevron_right_rounded,
              () => _moveDate(1),
        ),
      ],
    );
  }


  Widget _navButton(
      IconData icon,
      VoidCallback onTap,
      ) {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isDark ? const Color(0xFF1E1E1E) : card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? const Color(0xFF383838)
                  : const Color(0xFFE5E7EB),
            ),
          ),
          child: Icon(
            icon,
            color: isDark ? Colors.white : text,
            size: 20,
          ),
        ),
      ),
    );
  }// ─────────────────────────────────────────────
  // CHART
  // ─────────────────────────────────────────────

  String _chartLabel(int key) {
    if (_selectedTab == 0) {
      return '$key시';
    }

    if (_selectedTab == 1) {
      return _weekdayLabel(key);
    }

    return '$key월';
  }

  // ─────────────────────────────────────────────
  // SUMMARY
  // ─────────────────────────────────────────────

  Widget _buildStatSummary(
      num totalMinutes,
      int success,
      int fail,
      int avgFocusRate,
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('학습 성과', ''),
        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: _metricCard(
                title: '총 공부시간',
                value: _formatMinutes(totalMinutes),
                icon: Icons.timer_outlined,
                color: primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _metricCard(
                title: '성공 세션',
                value: '$success회',
                icon: Icons.check_circle_outline_rounded,
                color: green,
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: _metricCard(
                title: '평균 집중률',
                value: '$avgFocusRate%',
                icon: Icons.adjust_rounded,
                color: purple,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _metricCard(
                title: '실패 세션',
                value: '$fail회',
                icon: Icons.error_outline_rounded,
                color: red,
              ),
            ),
          ],
        ),
      ],
    );
  }


  Widget _metricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color primaryText =
    isDark ? Colors.white : text;

    final Color secondaryText =
    isDark ? Colors.white70 : subText;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
            MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: secondaryText,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Icon(
                icon,
                color: color,
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              color: primaryText,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // INSIGHT
  // ─────────────────────────────────────────────

  Widget _buildInsightCard(Map<String, dynamic> data) {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final int risk =
        data['totalRiskScore'] ?? 0;

    final String bestFocus =
        data['bestFocusTime']?.toString() ?? '-';

    final Color riskColor = risk >= 70
        ? red
        : risk >= 40
        ? orange
        : green;

    final String riskText = risk >= 70
        ? '고위험'
        : risk >= 40
        ? '주의'
        : '안정';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '학습 인사이트',
            style: TextStyle(
              color: isDark ? Colors.white : text,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _insightBox(
                  icon: Icons.psychology_outlined,
                  title: '집중 상태',
                  value: risk == 50 &&
                      data['analyzedSessions'] == 0
                      ? '데이터 없음'
                      : riskText,
                  color: riskColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _insightBox(
                  icon: Icons.bolt_outlined,
                  title: '골든타임',
                  value: bestFocus,
                  color: primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _insightBox({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(
          isDark ? 0.12 : 0.06,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: color,
            size: 20,
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              color: isDark ? Colors.white70 : subText,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // AI CARD
  // ─────────────────────────────────────────────

  Widget _buildAiCard(Map<String, dynamic> data) {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final int analyzed =
    _toInt(data['analyzedSessions']);

    final Color primaryText =
    isDark ? Colors.white : text;

    final Color secondaryText =
    isDark ? Colors.white70 : subText;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI 학습 패턴 분석',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: primaryText,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '$analyzed개 세션 데이터 기반',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: secondaryText,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Text(
            '맞춤형 학습 리포트를 확인해보세요',
            style: TextStyle(
              color: primaryText,
              fontSize: 17,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.3,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            '학습 시간, 집중도, 일기 기록을 종합 분석하여 피드백을 제공합니다.',
            style: TextStyle(
              color: secondaryText,
              fontSize: 12,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 18),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed:
              _isAnalyzing ? null : _requestAiFeedback,
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                primary.withOpacity(0.3),
                disabledForegroundColor: Colors.white70,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isAnalyzing
                  ? const Row(
                mainAxisAlignment:
                MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'AI가 분석 중입니다...',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              )
                  : const Row(
                mainAxisAlignment:
                MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 16,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'AI 학습 분석 받기 (1000P)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (_aiFeedbackResult != null &&
              _aiFeedbackResult!.trim().isNotEmpty) ...[
            const SizedBox(height: 16),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: primary.withOpacity(
                  isDark ? 0.10 : 0.05,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: primary.withOpacity(0.1),
                ),
              ),
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.description_outlined,
                        color: primary,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'AI 분석 결과',
                        style: TextStyle(
                          color: primaryText,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  Text(
                    _aiFeedbackResult!,
                    softWrap: true,
                    style: TextStyle(
                      color: primaryText,
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),

                  const SizedBox(height: 20),

                  Divider(
                    color: isDark
                        ? Colors.white12
                        : Colors.black12,
                    height: 1,
                  ),

                  const SizedBox(height: 16),

                  Text(
                    '이번 AI 피드백이 실제 공부 상황과 맞았나요?',
                    style: TextStyle(
                      color: primaryText,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 6),

                  Text(
                    '남겨주신 후기는 다음 AI 분석에 반영됩니다.',
                    style: TextStyle(
                      color: secondaryText,
                      fontSize: 11,
                    ),
                  ),

                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final result =
                        await showDialog<Map<String, dynamic>>(
                          context: context,
                          barrierDismissible: false,
                          builder: (dialogContext) {
                            bool? selectedAccurate;
                            final reviewController =
                            TextEditingController();

                            return StatefulBuilder(
                              builder:
                                  (
                                  stateContext,
                                  setDialogState,
                                  ) {
                                final bool dialogIsDark =
                                    Theme.of(stateContext)
                                        .brightness ==
                                        Brightness.dark;

                                return AlertDialog(
                                  backgroundColor: dialogIsDark
                                      ? const Color(0xFF1E1E1E)
                                      : Colors.white,

                                  title: Text(
                                    'AI 피드백 후기',
                                    style: TextStyle(
                                      color: dialogIsDark
                                          ? Colors.white
                                          : text,
                                      fontWeight:
                                      FontWeight.bold,
                                    ),
                                  ),

                                  content:
                                  SingleChildScrollView(
                                    child: Column(
                                      mainAxisSize:
                                      MainAxisSize.min,
                                      crossAxisAlignment:
                                      CrossAxisAlignment
                                          .start,
                                      children: [
                                        Text(
                                          '이번 피드백이 실제 공부 상황과 맞았나요?',
                                          style: TextStyle(
                                            color: dialogIsDark
                                                ? Colors.white70
                                                : subText,
                                            fontSize: 13,
                                          ),
                                        ),

                                        const SizedBox(
                                          height: 14,
                                        ),

                                        Row(
                                          children: [
                                            Expanded(
                                              child: ChoiceChip(
                                                label:
                                                const Text(
                                                  '맞았어요',
                                                ),
                                                selected:
                                                selectedAccurate ==
                                                    true,
                                                onSelected:
                                                    (selected) {
                                                  if (!selected) {
                                                    return;
                                                  }

                                                  setDialogState(() {
                                                    selectedAccurate =
                                                    true;
                                                  });
                                                },
                                              ),
                                            ),

                                            const SizedBox(
                                              width: 8,
                                            ),

                                            Expanded(
                                              child: ChoiceChip(
                                                label:
                                                const Text(
                                                  '아쉬웠어요',
                                                ),
                                                selected:
                                                selectedAccurate ==
                                                    false,
                                                onSelected:
                                                    (selected) {
                                                  if (!selected) {
                                                    return;
                                                  }

                                                  setDialogState(() {
                                                    selectedAccurate =
                                                    false;
                                                  });
                                                },
                                              ),
                                            ),
                                          ],
                                        ),

                                        const SizedBox(
                                          height: 14,
                                        ),

                                        TextField(
                                          controller:
                                          reviewController,
                                          maxLines: 4,
                                          textInputAction:
                                          TextInputAction
                                              .newline,
                                          style: TextStyle(
                                            color: dialogIsDark
                                                ? Colors.white
                                                : text,
                                          ),
                                          decoration:
                                          InputDecoration(
                                            hintText:
                                            '어떤 점이 맞았는지, 어떤 점이 달랐는지 적어주세요.',
                                            hintStyle:
                                            TextStyle(
                                              color: dialogIsDark
                                                  ? Colors.white38
                                                  : subText,
                                            ),
                                            filled: true,
                                            fillColor:
                                            dialogIsDark
                                                ? const Color(
                                              0xFF292929,
                                            )
                                                : const Color(
                                              0xFFF7F8FC,
                                            ),
                                            border:
                                            OutlineInputBorder(
                                              borderRadius:
                                              BorderRadius
                                                  .circular(
                                                12,
                                              ),
                                              borderSide:
                                              BorderSide.none,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  actions: [
                                    TextButton(
                                      onPressed: () {
                                        // 취소는 null 반환
                                        Navigator.of(
                                          dialogContext,
                                        ).pop();
                                      },
                                      child:
                                      const Text('취소'),
                                    ),

                                    ElevatedButton(
                                      onPressed:
                                      selectedAccurate ==
                                          null
                                          ? null
                                          : () {
                                        Navigator.of(
                                          dialogContext,
                                        ).pop({
                                          'is_accurate':
                                          selectedAccurate,
                                          'review':
                                          reviewController
                                              .text
                                              .trim(),
                                        });
                                      },
                                      style:
                                      ElevatedButton
                                          .styleFrom(
                                        backgroundColor:
                                        primary,
                                        foregroundColor:
                                        Colors.white,
                                      ),
                                      child:
                                      const Text('저장'),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        );

                        // 다이얼로그가 완전히 닫힌 다음에만 결과 처리
                        if (!mounted || result == null) {
                          return;
                        }

                        final bool? isAccurate =
                        result['is_accurate'] as bool?;

                        final String review =
                            result['review']?.toString() ?? '';

                        if (isAccurate == null) {
                          return;
                        }

                        if (review.trim().isEmpty) {
                          _showSnack('후기를 입력해주세요.');
                          return;
                        }

                        await _saveAiFeedbackReview(
                          isAccurate: isAccurate,
                          review: review,
                        );
                      },

                      icon: Icon(
                        Icons.rate_review_outlined,
                        size: 17,
                        color: primary,
                      ),

                      label: Text(
                        'AI 피드백 후기 남기기',
                        style: TextStyle(
                          color: primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color:
                          primary.withOpacity(0.25),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                          BorderRadius.circular(12),
                        ),
                        padding:
                        const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }// ─────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────

  Widget _sectionTitle(
      String title,
      String subtitle,
      ) {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    return Text(
      title,
      style: TextStyle(
        color: isDark ? Colors.white : text,
        fontSize: 16,
        fontWeight: FontWeight.bold,
        letterSpacing: -0.3,
      ),
    );
  }


  BoxDecoration _cardDecoration() {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    return BoxDecoration(
      color: isDark
          ? const Color(0xFF1E1E1E)
          : card,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: isDark
            ? const Color(0xFF303030)
            : const Color(0xFFF0F1F5),
      ),
      boxShadow: isDark
          ? []
          : [
        BoxShadow(
          color: Colors.black.withOpacity(0.03),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }
  String _formatMinutes(num totalMinutes) {
    final minutes = totalMinutes.round();

    if (_selectedTab == 2) {
      final hours = minutes ~/ 60;
      final remaining = minutes % 60;

      if (hours == 0 && remaining == 0) {
        return '0시간';
      }
      if (remaining == 0) {
        return '$hours시간';
      }
      if (hours == 0) {
        return '$remaining분';
      }
      return '$hours시간 $remaining분';
    }

    if (minutes < 60) {
      return '$minutes분';
    }

    final hours = minutes ~/ 60;
    final remaining = minutes % 60;

    if (remaining == 0) {
      return '$hours시간';
    }

    return '$hours시간 $remaining분';
  }


  String _weekdayLabel(int weekday) {
    switch (weekday) {
      case 1:
        return '월';
      case 2:
        return '화';
      case 3:
        return '수';
      case 4:
        return '목';
      case 5:
        return '금';
      case 6:
        return '토';
      case 7:
        return '일';
      default:
        return '';
    }
  }
}