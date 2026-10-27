import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class WriteDiaryPage extends StatefulWidget {
  final String? docId;
  final String? sessionId; // 💡 연결된 세션 ID를 받기 위한 파라미터 추가
  final String? existingContent;
  final String? existingEmotion;
  final DateTime? date;
  final bool canEdit;

  const WriteDiaryPage({
    super.key,
    this.docId,
    this.sessionId,
    this.existingContent,
    this.existingEmotion,
    this.date,
    this.canEdit = true,
  });

  @override
  State<WriteDiaryPage> createState() => _WriteDiaryPageState();
}

class _WriteDiaryPageState extends State<WriteDiaryPage> {
  late TextEditingController _controller;

  String _selectedStatus = "평온";

  final Color pointColor = const Color(0xFF6FD0F1);
  final Color darkBg = const Color(0xFF121416);

  final List<Map<String, dynamic>> _statusOptions = [
    {
      'label': '화남',
      'icon': Icons.fmd_bad_rounded,
      'color': Color(0xFFFF5252),
    },
    {
      'label': '뿌듯',
      'icon': Icons.stars_rounded,
      'color': Color(0xFFFFD740),
    },
    {
      'label': '행복',
      'icon': Icons.sentiment_very_satisfied_rounded,
      'color': Color(0xFF40C4FF),
    },
    {
      'label': '즐거움',
      'icon': Icons.celebration_rounded,
      'color': Color(0xFFFF4081),
    },
    {
      'label': '우울',
      'icon': Icons.wb_cloudy_rounded,
      'color': Color(0xFF90A4AE),
    },
    {
      'label': '평온',
      'icon': Icons.spa_rounded,
      'color': Color(0xFF6FD0F1),
    },
    {
      'label': '불안',
      'icon': Icons.waves_rounded,
      'color': Color(0xFFB388FF),
    },
    {
      'label': '슬픔',
      'icon': Icons.water_drop_rounded,
      'color': Color(0xFF448AFF),
    },
    {
      'label': '아픔',
      'icon': Icons.medical_services_rounded,
      'color': Color(0xFF69F0AE),
    },
    {
      'label': '짜증',
      'icon': Icons.bolt_rounded,
      'color': Color(0xFFFFAB40),
    },
    {
      'label': '피곤',
      'icon': Icons.nights_stay_rounded,
      'color': Color(0xFF7C4DFF),
    },
    {
      'label': '설렘',
      'icon': Icons.favorite_rounded,
      'color': Color(0xFFFF1744),
    },
  ];

  @override
  void initState() {
    super.initState();

    _controller = TextEditingController(
      text: widget.existingContent ?? '',
    );

    if (widget.existingEmotion != null &&
        _statusOptions.any(
              (e) => e['label'] == widget.existingEmotion,
        )) {
      _selectedStatus = widget.existingEmotion!;
    }

    if (widget.docId == null) {
      WidgetsBinding.instance.addPostFrameCallback(
            (_) => _showEmotionPicker(),
      );
    }
  }

  void _showEmotionPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: const Color(0xFF1E2124),
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(30),
          ),
          border: Border.all(
            color: Colors.white10,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(25, 15, 25, 25),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 25),
            const Text(
              "오늘의 마음 상태",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 20,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 25),
            Expanded(
              child: StatefulBuilder(
                builder: (context, setModalState) {
                  return GridView.builder(
                    gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.0,
                    ),
                    itemCount: _statusOptions.length,
                    itemBuilder: (context, index) {
                      final option = _statusOptions[index];
                      final bool isSelected = _selectedStatus == option['label'];

                      return GestureDetector(
                        onTap: () {
                          setModalState(() {
                            _selectedStatus = option['label'];
                          });

                          setState(() {
                            _selectedStatus = option['label'];
                          });

                          Future.delayed(
                            const Duration(milliseconds: 250),
                                () => Navigator.pop(context),
                          );
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? option['color'].withOpacity(0.15)
                                : Colors.white.withOpacity(0.03),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected
                                  ? option['color']
                                  : Colors.white10,
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                option['icon'],
                                color: isSelected
                                    ? option['color']
                                    : Colors.white30,
                                size: 30,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                option['label'],
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.white30,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ⭐ study_diaries 구조 설계에 정확히 맞춘 저장 로직
  Future<void> _saveDiary() async {
    if (_controller.text.trim().isEmpty) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final String today = DateFormat('yyyy-MM-dd').format(
        widget.date ?? DateTime.now(),
      );

      // 1. study_diaries 컬렉션 참조 생성 (docId가 있으면 기존 문서 업데이트, 없으면 자동 생성)
      final diaryRef = widget.docId != null
          ? FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('study_diaries')
          .doc(widget.docId)
          : FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('study_diaries')
          .doc();

      // 2. 요구사항 필드 구조에 맞춰 데이터 매핑 및 저장
      await diaryRef.set({
        'session_id': widget.sessionId ?? '',
        'date': today,
        'study_review': _controller.text.trim(),
        'emotion': _selectedStatus,
      }, SetOptions(merge: true));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("오늘 기록이 저장되었습니다."),
          backgroundColor: pointColor,
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      debugPrint("일기 저장 오류: $e");

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("저장 실패: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentStatusData = _statusOptions.firstWhere(
          (e) => e['label'] == _selectedStatus,
      orElse: () => _statusOptions[5],
    );

    return Scaffold(
      backgroundColor: darkBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(
          widget.docId == null ? "Today's Log" : "Edit Log",
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Colors.white70,
            fontSize: 17,
          ),
        ),
        actions: [
          TextButton(
            onPressed: widget.canEdit ? _saveDiary : null,
            child: Text(
              "완료",
              style: TextStyle(
                color: pointColor,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          Center(
            child: GestureDetector(
              onTap: widget.canEdit ? _showEmotionPicker : null,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: currentStatusData['color'].withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: currentStatusData['color'].withOpacity(0.3),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      currentStatusData['icon'],
                      color: currentStatusData['color'],
                      size: 40,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "지금 상태: ${currentStatusData['label']}",
                      style: const TextStyle(
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 40),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(30, 40, 30, 20),
              decoration: const BoxDecoration(
                color: Color(0xFF1E2124),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(40),
                ),
              ),
              child: TextField(
                controller: _controller,
                maxLines: null,
                enabled: widget.canEdit,
                style: const TextStyle(
                  fontSize: 18,
                  height: 1.8,
                  color: Colors.white,
                ),
                decoration: const InputDecoration(
                  hintText: "오늘 하루를 기록하세요",
                  hintStyle: TextStyle(
                    color: Colors.white24,
                  ),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}