import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import 'add_schedule_bottom_sheet.dart';
import 'main.dart' hide pointColor;
import 'map.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final _nameController = TextEditingController();
  final _goalController = TextEditingController();
  final _mbtiController = TextEditingController();

  String _displayName = "";
  String _homeAddress = "";
  double _homeLat = 0.0;
  double _homeLng = 0.0;

  final Color pointColor = const Color(0xFF6FD0F1);

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() {
      setState(() {
        _displayName = _nameController.text.trim();
      });
    });
  }

  Future<void> sendDataToN8N() async {
    final String n8nUrl = "https://tjddo2711.app.n8n.cloud/webhook-test/6e5b181b-f64e-4782-b5a0-9da76107b8f5";
    try {
      await http.post(
        Uri.parse(n8nUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "name": _nameController.text.isEmpty ? "이름" : _nameController.text,
          "total_study_time": "0h",
          "goal": _goalController.text.isEmpty ? "토익 900점" : _goalController.text,
          "mbti": _mbtiController.text.isEmpty ? "MBTI" : _mbtiController.text.toUpperCase(),
        }),
      );
    } catch (e) {
      debugPrint("⚠ n8n 전송 오류: $e");
    }
  }

  Future<void> _openHomeLocationPicker() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapSelectionPage(
          startTime: TimeOfDay.now(),
          duration: 60,
          selectedDate: DateTime.now(),
          isFromCalendar: false,
          title: '집 위치 설정',
          colorValue: pointColor.value,
        ),
      ),
    );

    if (result == null) return;

    debugPrint("=== [DEBUG] 맵 선택 결과: $result ===");

    String selectedName = '';
    double lat = 0.0;
    double lng = 0.0;

    if (result is Map) {
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
          targetMap['title'] ?? '';

      lat = (targetMap['latitude'] as num?)?.toDouble() ??
          (targetMap['lat'] as num?)?.toDouble() ?? 0.0;

      lng = (targetMap['longitude'] as num?)?.toDouble() ??
          (targetMap['lng'] as num?)?.toDouble() ?? 0.0;

      if (lat == 0.0 && result['latitude'] != null) {
        lat = (result['latitude'] as num).toDouble();
      }
      if (lng == 0.0 && result['longitude'] != null) {
        lng = (result['longitude'] as num).toDouble();
      }
    } else if (result is String) {
      selectedName = result;
    }

    if (selectedName.isEmpty) {
      selectedName = "선택된 위치";
    }

    setState(() {
      _homeAddress = selectedName;
      _homeLat = lat;
      _homeLng = lng;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _goalController.dispose();
    _mbtiController.dispose();
    super.dispose();
  }

  Future<void> _saveAndGoHome() async {
    if (_nameController.text.isEmpty || _goalController.text.isEmpty || _mbtiController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이름, 현재 목표, MBTI는 모두 입력해주세요!')),
      );
      return;
    }

    if (_homeAddress.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('집 주소를 지도에서 설정해주세요!')),
      );
      return;
    }

    final User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final String uid = currentUser.uid;
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    String provider = 'email';
    for (var info in currentUser.providerData) {
      if (info.providerId.contains('google')) {
        provider = 'google';
        break;
      }
    }

    try {
      await userRef.collection('user_profile').doc('current').set({
        'name': _nameController.text.trim(),
        'mbti': _mbtiController.text.trim().toUpperCase(),
        'home_address': _homeAddress,
        'home_lat': _homeLat,
        'home_lng': _homeLng,
        'goal': _goalController.text.trim(),
        'gender': '',
        'point': 0,
        'email': currentUser.email ?? '',
        'provider': provider,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await sendDataToN8N();

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const RootScreen(),
        ),
      );

    } catch (e) {
      debugPrint("데이터 저장 중 오류 발생: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('데이터 저장에 실패했습니다. 다시 시도해주세요.')),
      );
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: pointColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.waving_hand_rounded, color: pointColor, size: 28),
              ),
              const SizedBox(height: 20),
              Text(
                "반갑습니다!\n${_displayName.isEmpty ? '회원' : _displayName}님을 위한 STAY를 시작할게요.",
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 32),

              _buildInputLabel("이름"),
              _buildTextField(_nameController, "성함을 입력해주세요.", Icons.person_outline),

              _buildInputLabel("현재 목표"),
              _buildTextField(_goalController, "예: 토익 900점 달성", Icons.flag_outlined),

              _buildInputLabel("MBTI"),
              _buildTextField(_mbtiController, "예: INTJ", Icons.psychology_outlined),

              _buildInputLabel("집 주소"),
              GestureDetector(
                onTap: _openHomeLocationPicker,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _homeAddress.isEmpty ? Colors.grey.shade300 : pointColor.withOpacity(0.6),
                      width: _homeAddress.isEmpty ? 1 : 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.location_on_rounded, color: pointColor),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _homeAddress.isEmpty ? "지도를 눌러 집 위치를 선택해주세요" : _homeAddress,
                          style: TextStyle(
                            color: _homeAddress.isEmpty ? Colors.grey.shade400 : Colors.black87,
                            fontSize: 15,
                            fontWeight: _homeAddress.isEmpty ? FontWeight.normal : FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _saveAndGoHome,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: pointColor,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    "STAY 시작하기",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    "입력하신 데이터는 학습 분석 목적으로만 안전하게 활용됩니다.",
                    style: TextStyle(fontSize: 11.5, color: Colors.grey),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputLabel(String label) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(
      label,
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 14.5,
        color: Colors.black87,
      ),
    ),
  );

  Widget _buildTextField(TextEditingController controller, String hint, IconData prefixIcon) =>
      TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14.5),
          prefixIcon: Icon(prefixIcon, color: Colors.grey.shade500, size: 22),
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: pointColor, width: 1.5),
          ),
        ),
      );
}