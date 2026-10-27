import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import 'camera_timer_page.dart';
import 'map.dart';

const Color pointColor = Color(0xFF6FD0F1);

Future<void> showAddScheduleBottomSheet(BuildContext context) async {
  if (!context.mounted) return;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    enableDrag: true,
    builder: (_) {
      return const _AddScheduleBottomSheet();
    },
  );
}

// ================================================================
// 일정 추가 화면
// ================================================================

class _AddScheduleBottomSheet extends StatefulWidget {
  const _AddScheduleBottomSheet();

  @override
  State<_AddScheduleBottomSheet> createState() =>
      _AddScheduleBottomSheetState();
}

class _AddScheduleBottomSheetState
    extends State<_AddScheduleBottomSheet> {
  // ==============================================================
  // Controllers
  // ==============================================================

  final TextEditingController _titleController =
  TextEditingController();

  late final FixedExtentScrollController _hourController;
  late final FixedExtentScrollController _minuteController;

  // ==============================================================
  // 기본값
  // ==============================================================

  int _selectedHour = 0;
  int _selectedMinute = 1;

  late DateTime _selectedStartDateTime;

  bool _isStartTimeManuallyChanged = false;

  // ==============================================================
  // 장소
  // ==============================================================

  double _selectedLat = 0.0;
  double _selectedLng = 0.0;

  String _selectedLocationName = '현재 위치';
  String _selectedLocationAddress = '';

  // ==============================================================
  // 기타
  // ==============================================================

  bool _isForceMode = false;
  bool _isSaving = false;
  bool _isLoadingLocation = false;

  // ==============================================================
  // 초기화
  // ==============================================================

  @override
  void initState() {
    super.initState();

    final now = DateTime.now();

    // 현재가 20:45:37이면 기본값 20:46:00
    _selectedStartDateTime = _getNextMinute(now);

    _hourController =
        FixedExtentScrollController(initialItem: 0);

    _minuteController =
        FixedExtentScrollController(initialItem: 1);

    _loadCurrentLocation();
  }

  // ==============================================================
  // 현재 시간보다 정확히 다음 1분
  // ==============================================================
  DateTime _getNextMinute(DateTime now) {
    return DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    ).add(
      const Duration(minutes: 1),
    );
  }

  // ==============================================================
  // 현재 선택 시간
  // ==============================================================
  TimeOfDay get _selectedTime {
    return TimeOfDay(
      hour: _selectedStartDateTime.hour,
      minute: _selectedStartDateTime.minute,
    );
  }

  // ==============================================================
  // SnackBar
  // ==============================================================
  void _showSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: pointColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ==============================================================
  // 현재 위치
  // ==============================================================
  Future<void> _loadCurrentLocation() async {
    if (!mounted) return;

    setState(() {
      _isLoadingLocation = true;
    });

    try {
      final bool serviceEnabled =
      await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        debugPrint('위치 서비스가 꺼져 있습니다.');
        return;
      }

      LocationPermission permission =
      await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('위치 권한이 없습니다.');
        return;
      }

      final Position position =
      await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      if (!mounted) return;

      if (_selectedLocationName == '현재 위치' ||
          _selectedLocationName == '현재위치') {
        setState(() {
          _selectedLat = position.latitude;
          _selectedLng = position.longitude;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('현재 위치 조회 실패: $e');
      debugPrint('$stackTrace');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
        });
      }
    }
  }
  // ==============================================================
  // 장소 선택
  // ==============================================================
  Future<void> _openLocationPicker() async {
    if (_isSaving) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) {
          return MapSelectionPage(
            startTime: _selectedTime,
            duration: (_selectedHour * 60) + _selectedMinute,
            selectedDate: _selectedStartDateTime,
            isFromCalendar: false,
            title: _titleController.text.trim().isEmpty
                ? '제목 없음'
                : _titleController.text.trim(),
            colorValue: pointColor.value,
          );
        },
      ),
    );

    if (!mounted || result == null || result is! Map) {
      return;
    }

    final dynamic locationData = result['location'];

    if (locationData is! Map) {
      _showSnack('선택한 장소 정보를 불러오지 못했습니다.');
      return;
    }

    final dynamic rawName = locationData['name'];
    final dynamic rawAddress = locationData['address'];
    final dynamic rawLatitude = locationData['latitude'];
    final dynamic rawLongitude = locationData['longitude'];

    final String locationName =
        rawName?.toString().trim() ?? '';

    final String address =
        rawAddress?.toString().trim() ?? '';

    final double? latitude = rawLatitude is num
        ? rawLatitude.toDouble()
        : double.tryParse(rawLatitude?.toString() ?? '');

    final double? longitude = rawLongitude is num
        ? rawLongitude.toDouble()
        : double.tryParse(rawLongitude?.toString() ?? '');

    if (latitude == null ||
        longitude == null ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        (latitude == 0.0 && longitude == 0.0)) {
      _showSnack('선택한 장소의 위치 정보를 불러오지 못했습니다.');
      return;
    }

    setState(() {
      _selectedLocationName =
      locationName.isNotEmpty ? locationName : '선택한 장소';

      _selectedLocationAddress = address;

      _selectedLat = latitude;
      _selectedLng = longitude;
    });

    debugPrint('장소 직접 지정 완료');
    debugPrint('place_name: $_selectedLocationName');
    debugPrint('place_address: $_selectedLocationAddress');
    debugPrint('place_lat: $_selectedLat');
    debugPrint('place_lng: $_selectedLng');
  }


  // ==============================================================
  // 시작시간 변경
  // ==============================================================
  void _onStartTimeChanged(DateTime value) {
    if (_isSaving) return;

    setState(() {
      _selectedStartDateTime = DateTime(
        value.year,
        value.month,
        value.day,
        value.hour,
        value.minute,
      );

      _isStartTimeManuallyChanged = true;
    });
  }

  // ==============================================================
  // 집중시간
  // ==============================================================
  int get _totalMinutes {
    return (_selectedHour * 60) +
        _selectedMinute;
  }

  // ==============================================================
  // 집 ↔ 장소 거리
  // ==============================================================
  Future<double> _calculatePlaceDistance(
      User user,
      ) async {
    if (_selectedLat == 0.0 ||
        _selectedLng == 0.0) {
      return 0.0;
    }

    try {
      final snapshot =
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('user_profile')
          .doc('current')
          .get();

      final data = snapshot.data();

      final dynamic rawHomeLat =
      data?['home_lat'];

      final dynamic rawHomeLng =
      data?['home_lng'];

      if (rawHomeLat is! num ||
          rawHomeLng is! num) {
        return 0.0;
      }

      final homeLat =
      rawHomeLat.toDouble();

      final homeLng =
      rawHomeLng.toDouble();

      return Geolocator.distanceBetween(
        homeLat,
        homeLng,
        _selectedLat,
        _selectedLng,
      );
    } catch (e) {
      debugPrint('거리 계산 실패: $e');
      return 0.0;
    }
  }

  // ==============================================================
  // 강제 모드 포인트 확인
  // ==============================================================
  Future<bool> _checkForceModePoint(
      User user,
      ) async {
    if (!_isForceMode) {
      return true;
    }

    try {
      final snapshot =
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('user_profile')
          .doc('current')
          .get();

      final data = snapshot.data();

      final dynamic rawPoints =
          data?['total_points'] ??
              data?['point'] ??
              0;

      final int currentPoints =
      rawPoints is num
          ? rawPoints.toInt()
          : 0;

      if (currentPoints < 500) {
        _showSnack(
          '강제 모드는 500P 이상 필요합니다. '
              '(보유: ${currentPoints}P)',
        );

        return false;
      }

      return true;
    } catch (e) {
      debugPrint(
        '포인트 조회 실패: $e',
      );

      _showSnack(
        '포인트 정보를 확인하지 못했습니다.',
      );

      return false;
    }
  }

  // ==============================================================
  // 시작시간 확정
  // ==============================================================
  DateTime? _makeStartDateTime() {
    final now = DateTime.now();

    if (!_isStartTimeManuallyChanged) {
      return _getNextMinute(now);
    }

    DateTime selected = DateTime(
      now.year,
      now.month,
      now.day,
      _selectedStartDateTime.hour,
      _selectedStartDateTime.minute,
    );

    if (!selected.isAfter(now)) {
      selected = selected.add(
        const Duration(days: 1),
      );
    }

    return selected;
  }

  // ==============================================================
  // 일정 저장
  // ==============================================================
  Future<void> _saveSchedule() async {
    if (_isSaving) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showSnack('로그인이 필요합니다.');
      return;
    }

    final int totalMinutes = _totalMinutes;

    if (totalMinutes <= 0) {
      _showSnack('1분 이상 설정하세요.');
      return;
    }

    final DateTime? startDateTime = _makeStartDateTime();

    if (startDateTime == null) {
      _showSnack('시작시간을 확인하세요.');
      return;
    }

    final DateTime endDateTime = startDateTime.add(
      Duration(minutes: totalMinutes),
    );

    final String title = _titleController.text.trim();

    final String titleText =
    title.isEmpty ? '제목 없음' : title;

    setState(() {
      _isSaving = true;
    });

    try {
      final bool forceModeValid =
      await _checkForceModePoint(user);

      if (!mounted) return;

      if (!forceModeValid) {
        setState(() {
          _isSaving = false;
        });
        return;
      }

      final bool isCurrentLocation =
          _selectedLocationName == '현재 위치' ||
              _selectedLocationName == '현재위치' ||
              _selectedLocationName.trim().isEmpty;

      if (isCurrentLocation) {
        final bool serviceEnabled =
        await Geolocator.isLocationServiceEnabled();

        if (!serviceEnabled) {
          if (!mounted) return;

          setState(() {
            _isSaving = false;
          });

          _showSnack(
            '위치 서비스가 꺼져 있습니다.\nGPS를 켜주세요.',
          );

          return;
        }

        LocationPermission permission =
        await Geolocator.checkPermission();

        if (permission == LocationPermission.denied) {
          permission =
          await Geolocator.requestPermission();
        }

        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          if (!mounted) return;

          setState(() {
            _isSaving = false;
          });

          _showSnack(
            '위치 권한이 필요합니다.\n위치 권한을 허용해주세요.',
          );

          return;
        }

        try {
          final Position position =
          await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 15),
          );

          if (!mounted) return;

          _selectedLat = position.latitude;
          _selectedLng = position.longitude;
          _selectedLocationName = '현재 위치';
          _selectedLocationAddress = '';
        } catch (e, stackTrace) {
          debugPrint('저장 시 현재 위치 조회 실패: $e');
          debugPrint('$stackTrace');

          if (!mounted) return;

          setState(() {
            _isSaving = false;
          });

          _showSnack(
            '현재 위치를 확인할 수 없습니다.\n'
                '위치 권한과 GPS를 확인해주세요.',
          );

          return;
        }
      }

      if (!_selectedLat.isFinite ||
          !_selectedLng.isFinite ||
          (_selectedLat == 0.0 &&
              _selectedLng == 0.0)) {
        if (!mounted) return;

        setState(() {
          _isSaving = false;
        });

        _showSnack(
          '공부 장소 위치 정보를 불러오지 못했습니다.',
        );

        return;
      }

      final double placeDistance =
      await _calculatePlaceDistance(user);

      if (!mounted) return;

      // ============================================================
      // 중요:
      // 일정 생성 시에는 절대로 is_started=true로 만들지 않는다.
      // 예정시간보다 먼저 눌러도 Firestore에서는 계속 scheduled 상태.
      // 실제 타이머를 시작하는 곳에서 start_datetime을 검사한다.
      // ============================================================

      final Map<String, dynamic> scheduleData = {
        'title': titleText,
        'subject': titleText,

        'place_name': _selectedLocationName,
        'place_address': _selectedLocationAddress,

        'place_lat': _selectedLat,
        'place_lng': _selectedLng,

        'place_distance': placeDistance,

        'target_minutes': totalMinutes,

        'start_datetime':
        Timestamp.fromDate(startDateTime),

        'end_datetime':
        Timestamp.fromDate(endDateTime),

        // 반드시 bool로 저장
        'force': _isForceMode,

        // 예정 상태 유지
        'status': 'scheduled',
        'is_started': false,
        'is_finished': false,

        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      };

      final DocumentReference scheduleRef =
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('schedules')
          .add(scheduleData);

      await scheduleRef.update({
        'doc_id': scheduleRef.id,
      });

      if (!mounted) return;

      Navigator.of(context).pop();
    } catch (e, stackTrace) {
      debugPrint('일정 저장 오류: $e');
      debugPrint('$stackTrace');

      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });

      _showSnack(
        '일정 저장에 실패했습니다.\n$e',
      );
    }
  }// ==============================================================
  // Dispose
  // ==============================================================
  @override
  void dispose() {
    _titleController.dispose();
    _hourController.dispose();
    _minuteController.dispose();

    super.dispose();
  }

  // ==============================================================
  // UI
  // ==============================================================
  @override
  Widget build(BuildContext context) {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color sheetBackground =
    isDark ? const Color(0xFF121212) : Colors.white;

    final Color fieldBackground =
    isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0F4F8);

    final Color primaryText =
    isDark ? Colors.white : const Color(0xFF111827);

    final Color secondaryText =
    isDark ? Colors.white70 : Colors.grey.shade600;

    final Color pickerText =
    isDark ? Colors.white : const Color(0xFF111827);

    return DraggableScrollableSheet(
      initialChildSize: 0.95,
      minChildSize: 0.8,
      maxChildSize: 0.98,
      expand: false,
      builder: (
          context,
          scrollController,
          ) {
        return Container(
          decoration: BoxDecoration(
            color: sheetBackground,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(40),
            ),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(
              25,
              20,
              25,
              MediaQuery.of(context).viewInsets.bottom + 25,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 30),

                Text(
                  '오늘의 계획 추가',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: primaryText,
                  ),
                ),

                const SizedBox(height: 20),

                TextField(
                  controller: _titleController,
                  enabled: !_isSaving,
                  style: TextStyle(
                    color: primaryText,
                  ),
                  cursorColor: pointColor,
                  decoration: InputDecoration(
                    hintText: '무엇을 공부할까요?',
                    hintStyle: TextStyle(
                      color: secondaryText,
                    ),
                    filled: true,
                    fillColor: fieldBackground,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),

                const SizedBox(height: 25),

                Text(
                  '장소',
                  style: TextStyle(
                    color: secondaryText,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 12),

                GestureDetector(
                  onTap: _isSaving
                      ? null
                      : _openLocationPicker,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: fieldBackground,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.location_on,
                          color: pointColor,
                        ),

                        const SizedBox(width: 10),

                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedLocationName,
                                style: TextStyle(
                                  color: primaryText,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),

                              if (_selectedLocationAddress
                                  .isNotEmpty)
                                const SizedBox(height: 3),

                              if (_selectedLocationAddress
                                  .isNotEmpty)
                                Text(
                                  _selectedLocationAddress,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: secondaryText,
                                  ),
                                ),

                              if (_isLoadingLocation)
                                Padding(
                                  padding:
                                  const EdgeInsets.only(top: 5),
                                  child: Text(
                                    '현재 위치 확인 중...',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: secondaryText,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        Icon(
                          Icons.chevron_right,
                          color: primaryText,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 25),

                Text(
                  '시작 시간',
                  style: TextStyle(
                    color: secondaryText,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  _isStartTimeManuallyChanged
                      ? '선택한 시간으로 저장됩니다.'
                      : '기본값은 현재 시간보다 1분 뒤입니다.',
                  style: TextStyle(
                    color: isDark
                        ? Colors.white54
                        : Colors.grey.shade500,
                    fontSize: 12,
                  ),
                ),

                const SizedBox(height: 12),

                Container(
                  height: 160,
                  decoration: BoxDecoration(
                    color: fieldBackground,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: CupertinoTheme(
                    data: CupertinoThemeData(
                      brightness: isDark
                          ? Brightness.dark
                          : Brightness.light,
                      textTheme: CupertinoTextThemeData(
                        dateTimePickerTextStyle: TextStyle(
                          color: pickerText,
                          fontSize: 21,
                        ),
                      ),
                    ),
                    child: CupertinoDatePicker(
                      mode: CupertinoDatePickerMode.time,
                      initialDateTime: _selectedStartDateTime,
                      use24hFormat: false,
                      onDateTimeChanged:
                      _onStartTimeChanged,
                    ),
                  ),
                ),

                const SizedBox(height: 25),

                Text(
                  '집중 시간',
                  style: TextStyle(
                    color: secondaryText,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 12),

                SizedBox(
                  height: 120,
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: fieldBackground,
                            borderRadius:
                            BorderRadius.circular(20),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: CupertinoTheme(
                            data: CupertinoThemeData(
                              brightness: isDark
                                  ? Brightness.dark
                                  : Brightness.light,
                              textTheme:
                              CupertinoTextThemeData(
                                pickerTextStyle: TextStyle(
                                  color: pickerText,
                                  fontSize: 20,
                                ),
                              ),
                            ),
                            child: CupertinoPicker(
                              itemExtent: 45,
                              scrollController:
                              _hourController,
                              onSelectedItemChanged:
                              _isSaving
                                  ? null
                                  : (index) {
                                setState(() {
                                  _selectedHour =
                                      index;
                                });
                              },
                              children: List.generate(
                                24,
                                    (index) {
                                  return Center(
                                    child: Text(
                                      '$index시간',
                                      style: TextStyle(
                                        color: pickerText,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 15),

                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: fieldBackground,
                            borderRadius:
                            BorderRadius.circular(20),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: CupertinoTheme(
                            data: CupertinoThemeData(
                              brightness: isDark
                                  ? Brightness.dark
                                  : Brightness.light,
                              textTheme:
                              CupertinoTextThemeData(
                                pickerTextStyle: TextStyle(
                                  color: pickerText,
                                  fontSize: 20,
                                ),
                              ),
                            ),
                            child: CupertinoPicker(
                              itemExtent: 45,
                              scrollController:
                              _minuteController,
                              onSelectedItemChanged:
                              _isSaving
                                  ? null
                                  : (index) {
                                setState(() {
                                  _selectedMinute =
                                      index;
                                });
                              },
                              children: List.generate(
                                60,
                                    (index) {
                                  return Center(
                                    child: Text(
                                      '$index분',
                                      style: TextStyle(
                                        color: pickerText,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                Center(
                  child: Text(
                    '총 $_totalMinutes분',
                    style: const TextStyle(
                      color: pointColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '강제 모드 (실패시 -500p)',
                        style: TextStyle(
                          color: primaryText,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    Switch(
                      value: _isForceMode,
                      activeColor: pointColor,
                      onChanged: _isSaving
                          ? null
                          : (value) {
                        setState(() {
                          _isForceMode = value;
                        });
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed:
                    _isSaving ? null : _saveSchedule,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: pointColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                        BorderRadius.circular(20),
                      ),
                      elevation: 0,
                    ),
                    child: _isSaving
                        ? const CircularProgressIndicator(
                      color: Colors.white,
                    )
                        : const Text(
                      '일정 추가하기',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 80),
              ],
            ),
          ),
        );
      },
    );
  }
}