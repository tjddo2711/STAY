import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'map.dart'; // MapSelectionPage를 사용하기 위한 임포트

const Color pointColor = Color(0xFF6FD0F1);
const Color subBlue = Color(0xFF3A86FF);

class InformPage extends StatefulWidget {
  const InformPage({super.key});

  @override
  State<InformPage> createState() => _InformPageState();
}

class _InformPageState extends State<InformPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _goalController = TextEditingController();
  final TextEditingController _mbtiController = TextEditingController();
  final TextEditingController _situationController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  // 🔥 실시간 글자 수 표기를 위한 ValueNotifier 추가
  final ValueNotifier<int> _situationLengthNotifier = ValueNotifier<int>(0);

  bool _isLoading = true;

  // 🔥 집 주소 및 좌표 저장을 위한 변수 추가
  String _homeAddress = "";
  double _homeLat = 0.0;
  double _homeLng = 0.0;

  @override
  void initState() {
    super.initState();
    _loadExistingData();
    // 텍스트가 바뀔 때마다 길이를 갱신합니다.
    _situationController.addListener(_updateSituationLength);
  }

  void _updateSituationLength() {
    _situationLengthNotifier.value = _situationController.text.length;
  }

  @override
  void dispose() {
    _situationController.removeListener(_updateSituationLength);
    _nameController.dispose();
    _goalController.dispose();
    _mbtiController.dispose();
    _situationController.dispose();
    _situationLengthNotifier.dispose(); // 🔥 Notifier 메모리 해제
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('user_profile')
            .doc('current')
            .get();

        if (doc.exists && doc.data() != null) {
          final profile = doc.data()!;
          setState(() {
            _nameController.text = profile['name'] ?? "";
            _goalController.text = profile['goal'] ?? "";
            _mbtiController.text = profile['mbti'] ?? "";
            _phoneController.text = profile['phone_number'] ?? "";
            _situationController.text = profile['current_situation'] ?? "";

            _homeAddress = profile['home_address'] ?? profile['address'] ?? "";
            _homeLat = (profile['home_lat'] as num?)?.toDouble() ?? 0.0;
            _homeLng = (profile['home_lng'] as num?)?.toDouble() ?? 0.0;

            _situationLengthNotifier.value =
                _situationController.text.length;
          });
        }
      }
    } catch (e) {
      print("데이터 로드 실패: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 🔥 맵 페이지를 열어 주소와 좌표를 선택하는 함수
  Future<void> _openLocationPicker() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapSelectionPage(
          startTime: TimeOfDay.now(),
          duration: 60,
          selectedDate: DateTime.now(),
          isFromCalendar: false,
          title: '내 주소 설정',
          colorValue: pointColor.value,
        ),
      ),
    );

    if (result == null) return;

    debugPrint("=== [DEBUG] InformPage 맵 선택 결과: $result ===");

    String selectedName = _homeAddress;
    double lat = _homeLat;
    double lng = _homeLng;

    if (result is Map) {
      // 'location' 중첩 맵 구조 대응
      final dynamic innerLocation = result['location'];
      Map<String, dynamic>? targetMap;

      if (innerLocation is Map) {
        targetMap = Map<String, dynamic>.from(innerLocation);
      } else {
        targetMap = Map<String, dynamic>.from(result);
      }

      selectedName = targetMap['name'] ??
          targetMap['location_name'] ??
          targetMap['placeName'] ??
          targetMap['place_name'] ??
          targetMap['address'] ??
          targetMap['title'] ??
          _homeAddress;

      lat = (targetMap['latitude'] as num?)?.toDouble() ??
          (targetMap['lat'] as num?)?.toDouble() ?? _homeLat;

      lng = (targetMap['longitude'] as num?)?.toDouble() ??
          (targetMap['lng'] as num?)?.toDouble() ?? _homeLng;

      // 최상위 좌표 방어 코드
      if (lat == _homeLat && result['latitude'] != null) {
        lat = (result['latitude'] as num).toDouble();
      }
      if (lng == _homeLng && result['longitude'] != null) {
        lng = (result['longitude'] as num).toDouble();
      }
    } else if (result is String) {
      selectedName = result;
    }

    setState(() {
      _homeAddress = selectedName;
      _homeLat = lat;
      _homeLng = lng;
    });
  }

  Future<void> _saveAndSendInfo() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("이름을 입력해주세요!")),
      );
      return;
    }

    final String phoneNumber = _phoneController.text.trim();

    if (phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("기프티콘을 받을 전화번호를 입력해주세요!")),
      );
      return;
    }

    final String phoneDigits = phoneNumber.replaceAll('-', '');

    if (!RegExp(r'^01[0-9]{8,9}$').hasMatch(phoneDigits)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("올바른 전화번호를 입력해주세요!")),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        throw Exception("로그인 만료");
      }

      final profileRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('user_profile')
          .doc('current');

      await profileRef.set(
        {
          'name': _nameController.text.trim(),
          'mbti': _mbtiController.text.trim().toUpperCase(),
          'goal': _goalController.text.trim(),

          // 전화번호 저장
          'phone_number': phoneDigits,

          'current_situation': _situationController.text.trim(),
          'home_address': _homeAddress,
          'home_lat': _homeLat,
          'home_lng': _homeLng,
          'updated_at': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("정보가 성공적으로 업데이트되었습니다."),
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("저장 실패: $e")),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color backgroundColor =
    isDark ? const Color(0xFF121212) : const Color(0xFFF8FBFF);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: const Center(
          child: CircularProgressIndicator(color: pointColor),
        ),
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      resizeToAvoidBottomInset: true,
      appBar: _buildAppBar(),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(25, 0, 25, 20),
          child: _buildSubmitButton(),
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            25,
            20,
            25,
            MediaQuery.of(context).viewInsets.bottom + 40,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProfileHeader(),
              const SizedBox(height: 30),
              _buildSectionTitle("상세 정보"),
              _buildInputFields(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color textColor =
    isDark ? Colors.white : Colors.black87;

    return AppBar(
      title: Text(
        "내 정보 수정",
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_ios_new,
          color: textColor,
          size: 20,
        ),
        onPressed: () => Navigator.pop(context),
      ),
    );
  }


  Widget _buildProfileHeader() {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color primaryText =
    isDark ? Colors.white : Colors.black87;

    final Color secondaryText =
    isDark ? Colors.white70 : Colors.grey.shade500;

    final Color avatarContainerColor =
    isDark ? const Color(0xFF1E1E1E) : Colors.white;

    final Color avatarBackground =
    isDark ? const Color(0xFF263238) : const Color(0xFFE1F5FE);

    return Center(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: avatarContainerColor,
              shape: BoxShape.circle,
            ),
            child: CircleAvatar(
              radius: 40,
              backgroundColor: avatarBackground,
              child: const Icon(
                Icons.person,
                color: subBlue,
                size: 45,
              ),
            ),
          ),
          const SizedBox(height: 15),
          Text(
            "성애님의 프로필",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: primaryText,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            "분석에 필요한 정보를 최신으로 유지해주세요.",
            style: TextStyle(
              fontSize: 13,
              color: secondaryText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputFields() {
    return Column(
      children: [
        _buildCustomField(
          Icons.person_outline,
          "이름",
          _nameController,
          1,
        ),

        // 전화번호 입력창
        _buildPhoneField(),

        _buildCustomField(
          Icons.psychology_outlined,
          "MBTI",
          _mbtiController,
          1,
        ),

        _buildCustomField(
          Icons.flag_outlined,
          "나의 목표",
          _goalController,
          1,
        ),

        _buildLocationField(),
        _buildSituationField(),
      ],
    );
  }

  Widget _buildPhoneField() {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: TextField(
        controller: _phoneController,

        // 전화번호 입력 전용
        keyboardType: TextInputType.phone,

        // 숫자와 하이픈 입력
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            RegExp(r'[0-9-]'),
          ),
        ],

        maxLines: 1,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : Colors.black87,
        ),
        decoration: InputDecoration(
          prefixIcon: const Icon(
            Icons.phone_outlined,
            color: pointColor,
            size: 22,
          ),
          labelText: "전화번호",
          hintText: "010-1234-5678",
          hintStyle: TextStyle(
            color: isDark ? Colors.white38 : Colors.grey.shade400,
            fontSize: 14,
          ),
          labelStyle: TextStyle(
            color: isDark ? Colors.white54 : Colors.grey.shade400,
            fontSize: 13,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 18,
            horizontal: 20,
          ),
        ),
      ),
    );
  }

  // 일반 입력 필드 생성 메서드
  Widget _buildCustomField(
      IconData icon, String label, TextEditingController controller, int maxLines) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: pointColor, size: 22),
          labelText: label,
          labelStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13, fontWeight: FontWeight.w400),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
        ),
      ),
    );
  }

  // 🔥 지도 연동 주소 선택 필드 위젯
  Widget _buildLocationField() {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color fieldBackground =
    isDark ? const Color(0xFF1E1E1E) : Colors.white;

    final Color primaryText =
    isDark ? Colors.white : Colors.black87;

    final Color secondaryText =
    isDark ? Colors.white54 : Colors.grey.shade400;

    final Color shadowColor = isDark
        ? Colors.black.withOpacity(0.25)
        : Colors.black.withOpacity(0.04);

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: fieldBackground,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: _openLocationPicker,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 18,
              horizontal: 20,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  color: pointColor,
                  size: 22,
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "내 주소 (집)",
                        style: TextStyle(
                          color: secondaryText,
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _homeAddress.isEmpty
                            ? "주소를 설정해주세요"
                            : _homeAddress,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _homeAddress.isEmpty
                              ? secondaryText
                              : primaryText,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: isDark ? Colors.white54 : Colors.grey,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  // 🔥 실시간 글자 수(예: 302/1,000자) 표시를 지원하는 '현재 나의 상황' 필드 위젯
  Widget _buildSituationField() {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color fieldBackground =
    isDark ? const Color(0xFF1E1E1E) : Colors.white;

    final Color textColor =
    isDark ? Colors.white : Colors.black87;

    final Color labelColor =
    isDark ? Colors.white54 : const Color(0xFFBDBDBD);

    final Color counterColor =
    isDark ? Colors.white54 : Colors.grey.shade400;

    final Color shadowColor = isDark
        ? Colors.black.withOpacity(0.25)
        : Colors.black.withOpacity(0.04);

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
      decoration: BoxDecoration(
        color: fieldBackground,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          TextField(
            controller: _situationController,
            maxLines: 6,
            maxLength: 1000,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
            decoration: InputDecoration(
              prefixIcon: const Padding(
                padding: EdgeInsets.only(bottom: 70.0),
                child: Icon(
                  Icons.notes_outlined,
                  color: pointColor,
                  size: 22,
                ),
              ),
              labelText: "현재 나의 상황",
              labelStyle: TextStyle(
                color: labelColor,
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 10,
                horizontal: 20,
              ),
              counterText: "",
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: ValueListenableBuilder<int>(
              valueListenable: _situationLengthNotifier,
              builder: (context, length, child) {
                return Text(
                  "$length/1,000자",
                  style: TextStyle(
                    fontSize: 12,
                    color: length > 1000
                        ? Colors.red
                        : counterColor,
                    fontWeight: FontWeight.w500,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildSubmitButton() {
    return Container(
      width: double.infinity,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(colors: [pointColor, subBlue], begin: Alignment.centerLeft, end: Alignment.centerRight),
        boxShadow: [BoxShadow(color: pointColor.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: ElevatedButton(
        onPressed: _saveAndSendInfo,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        child: _isLoading
            ? const CircularProgressIndicator(color: Colors.white)
            : const Text("수정 완료", style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(
        bottom: 12,
        left: 5,
      ),
      child: Text(
        title,
        style: TextStyle(
          color: isDark ? Colors.white : Colors.grey.shade700,
          fontWeight: FontWeight.bold,
          fontSize: 15,
        ),
      ),
    );
  }}