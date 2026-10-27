import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'write_diary_page.dart';

class DiaryPage extends StatefulWidget {
  const DiaryPage({super.key});

  @override
  State<DiaryPage> createState() => _DiaryPageState();
}

class _DiaryPageState extends State<DiaryPage> {
  final Color pointColor = const Color(0xFF6FD0F1);
  final Color bgColor = const Color(0xFFF8F9FA);

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchText = "";

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// study_diaries/{diaryId} 문서 삭제 함수
  void _deleteDiary(String docId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('study_diaries')
          .doc(docId)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("일기가 삭제되었습니다"),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      debugPrint("삭제 실패: $e");
    }
  }

  void _showDeleteDialog(String docId) {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color dialogBackground =
    isDark ? const Color(0xFF1E1E1E) : Colors.white;

    final Color titleColor =
    isDark ? Colors.white : const Color(0xFF1E293B);

    final Color contentColor =
    isDark ? Colors.white70 : const Color(0xFF475569);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: dialogBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          "일기 삭제",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: titleColor,
          ),
        ),
        content: Text(
          "정말 이 기록을 삭제할까요?",
          style: TextStyle(
            color: contentColor,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "취소",
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.grey,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteDiary(docId);
            },
            child: const Text(
              "삭제",
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color backgroundColor =
    isDark ? const Color(0xFF121212) : bgColor;

    final Color appBarColor =
    isDark ? const Color(0xFF1E1E1E) : Colors.white;

    final Color primaryTextColor =
    isDark ? Colors.white : const Color(0xFF1E293B);

    final Color searchHintColor =
    isDark ? Colors.white54 : const Color(0xFF94A3B8);

    if (user == null) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: Center(
          child: Text(
            "로그인이 필요합니다",
            style: TextStyle(
              color: primaryTextColor,
            ),
          ),
        ),
      );
    }

    final studyDiariesRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('study_diaries');

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: appBarColor,
        foregroundColor: primaryTextColor,
        elevation: 0,
        centerTitle: true,
        title: _isSearching
            ? TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: "일기 내용 검색...",
            hintStyle: TextStyle(
              color: searchHintColor,
              fontSize: 14,
            ),
            border: InputBorder.none,
          ),
          style: TextStyle(
            fontSize: 15,
            color: primaryTextColor,
          ),
          onChanged: (value) {
            setState(() {
              _searchText = value;
            });
          },
        )
            : Text(
          "공부 일기",
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: primaryTextColor,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isSearching
                  ? Icons.close_rounded
                  : Icons.search_rounded,
              color: primaryTextColor,
            ),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;

                if (!_isSearching) {
                  _searchController.clear();
                  _searchText = "";
                }
              });
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: studyDiariesRef
            .orderBy('date', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(
              child: CircularProgressIndicator(
                valueColor:
                AlwaysStoppedAnimation<Color>(pointColor),
              ),
            );
          }

          final docs = snapshot.data!.docs;

          final diaryDocs = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final review =
            (data['study_review'] ?? "").toString();

            return review.trim().isNotEmpty;
          }).toList();

          final filtered = diaryDocs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final review =
            (data['study_review'] ?? "")
                .toString()
                .toLowerCase();

            return review.contains(
              _searchText.toLowerCase(),
            );
          }).toList();

          return ListView.builder(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 16,
            ),
            itemCount: filtered.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  children: [
                    _buildWriteCard(),
                    if (filtered.isEmpty)
                      _buildEmptyState(),
                  ],
                );
              }

              final doc = filtered[index - 1];
              final data =
              doc.data() as Map<String, dynamic>;

              return _buildDiaryCard(
                doc.id,
                data,
              );
            },
          );
        },
      ),
    );
  }

  /// 상단 일기 작성 유도 카드 디자인 (솔리드 컬러 기반 깔끔한 스타일)
  Widget _buildWriteCard() {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color cardColor =
    isDark ? const Color(0xFF1E1E1E) : Colors.white;

    final Color titleColor =
    isDark ? Colors.white : const Color(0xFF1E293B);

    final Color subTextColor =
    isDark ? Colors.white60 : const Color(0xFF94A3B8);

    final Color borderColor =
    isDark
        ? pointColor.withOpacity(0.55)
        : pointColor.withOpacity(0.4);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              isDark ? 0.2 : 0.02,
            ),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: borderColor,
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const WriteDiaryPage(),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: pointColor.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.edit_rounded,
                    color: pointColor,
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
                        "오늘의 공부 일기 작성",
                        style: TextStyle(
                          color: titleColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        "일기는 AI피드백에 반영됩니다.",
                        style: TextStyle(
                          color: subTextColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: pointColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  /// 일기가 없을 때 보여줄 빈 화면 위젯
  Widget _buildEmptyState() {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color textColor =
    isDark ? Colors.white70 : const Color(0xFF64748B);

    final Color iconColor =
    isDark ? Colors.white38 : Colors.grey.withOpacity(0.4);

    return Container(
      margin: const EdgeInsets.only(top: 40),
      padding: const EdgeInsets.all(20),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(
            Icons.menu_book_rounded,
            size: 48,
            color: iconColor,
          ),
          const SizedBox(height: 12),
          Text(
            "작성된 일기가 없습니다",
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
  /// 개별 일기 카드 디자인
  Widget _buildDiaryCard(
      String docId,
      Map<String, dynamic> data,
      ) {
    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    final Color cardColor =
    isDark ? const Color(0xFF1E1E1E) : Colors.white;

    final Color dateColor =
    isDark ? Colors.white54 : const Color(0xFF94A3B8);

    final Color reviewColor =
    isDark ? Colors.white : const Color(0xFF334155);

    final Color borderColor =
    isDark
        ? const Color(0xFF333333)
        : const Color(0xFFF1F5F9);

    final studyReview =
    (data['study_review'] ?? "").toString();

    final emotion =
    (data['emotion'] ?? "평온").toString();

    final dateField = data['date'];

    DateTime parsedDate;

    if (dateField is Timestamp) {
      parsedDate = dateField.toDate();
    } else if (dateField is String) {
      try {
        parsedDate = DateTime.parse(dateField);
      } catch (_) {
        parsedDate = DateTime.now();
      }
    } else {
      try {
        parsedDate =
            DateFormat('yyyy-MM-dd').parse(docId);
      } catch (_) {
        parsedDate = DateTime.now();
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              isDark ? 0.2 : 0.02,
            ),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: borderColor,
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onLongPress: () =>
              _showDeleteDialog(docId),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => WriteDiaryPage(
                  docId: docId,
                  existingContent: studyReview,
                  existingEmotion: emotion,
                  date: parsedDate,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding:
                          const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color:
                            pointColor.withOpacity(0.2),
                            borderRadius:
                            BorderRadius.circular(8),
                          ),
                          child: Text(
                            emotion,
                            style: TextStyle(
                              fontSize: 11,
                              color: pointColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          DateFormat(
                            'yyyy.MM.dd (E)',
                            'ko_KR',
                          ).format(parsedDate),
                          style: TextStyle(
                            fontSize: 12,
                            color: dateColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: isDark
                          ? Colors.white38
                          : const Color(0xFFCBD5E1),
                      size: 18,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  studyReview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: reviewColor,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }}