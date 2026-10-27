
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ReportHistoryPage extends StatefulWidget {
const ReportHistoryPage({super.key});

@override
State<ReportHistoryPage> createState() => _ReportHistoryPageState();
}

class _ReportHistoryPageState extends State<ReportHistoryPage> {
final Color pointColor = const Color(0xFF6FD0F1);

String _userName = "사용자";
bool _isLoadingName = true;

@override
void initState() {
super.initState();
_loadUserName();
}

// ─────────────────────────────────────────────
// 사용자 이름 불러오기
// ─────────────────────────────────────────────

Future<void> _loadUserName() async {
final uid = FirebaseAuth.instance.currentUser?.uid;

if (uid == null) {
if (mounted) {
setState(() {
_isLoadingName = false;
});
}
return;
}

try {
final doc = await FirebaseFirestore.instance
    .collection('users')
    .doc(uid)
    .collection('user_profile')
    .doc('current')
    .get();

if (doc.exists && doc.data() != null) {
final data = doc.data()!;

if (mounted) {
setState(() {
_userName =
data['name']?.toString().trim().isNotEmpty == true
? data['name'].toString()
    : "사용자";

_isLoadingName = false;
});
}
} else {
if (mounted) {
setState(() {
_isLoadingName = false;
});
}
}
} catch (e) {
debugPrint("사용자 이름 로드 실패: $e");

if (mounted) {
setState(() {
_isLoadingName = false;
});
}
}
}

// ─────────────────────────────────────────────
// 날짜 변환
// ─────────────────────────────────────────────

String _formatDate(dynamic rawDate) {
if (rawDate is Timestamp) {
return DateFormat(
'yyyy.MM.dd HH:mm',
).format(rawDate.toDate());
}

if (rawDate is DateTime) {
return DateFormat(
'yyyy.MM.dd HH:mm',
).format(rawDate);
}

if (rawDate is String) {
final parsed = DateTime.tryParse(rawDate);

if (parsed != null) {
return DateFormat(
'yyyy.MM.dd HH:mm',
).format(parsed);
}

if (rawDate.trim().isNotEmpty) {
return rawDate;
}
}

return '최근 분석 리포트';
}

// ─────────────────────────────────────────────
// AI 피드백 삭제
// ─────────────────────────────────────────────

Future<void> _deleteAiFeedback(
String documentId,
) async {
final uid = FirebaseAuth.instance.currentUser?.uid;

if (uid == null) {
_showSnackBar('로그인이 필요합니다.');
return;
}

try {
final feedbackRef = FirebaseFirestore.instance
    .collection('users')
    .doc(uid)
    .collection('ai_feedback_diaries')
    .doc(documentId);

await feedbackRef.delete();

if (!mounted) return;

_showSnackBar('AI 피드백이 삭제되었습니다.');
} catch (e, stackTrace) {
debugPrint('AI 피드백 삭제 실패: $e');
debugPrint('$stackTrace');

if (!mounted) return;

_showSnackBar(
'AI 피드백 삭제에 실패했습니다.',
);
}
}

// ─────────────────────────────────────────────
// 삭제 확인
// ─────────────────────────────────────────────

Future<void> _showDeleteConfirmDialog(
String documentId,
) async {
if (!mounted) return;

final bool? shouldDelete =
await showDialog<bool>(
context: context,
builder: (dialogContext) {
return AlertDialog(
backgroundColor: Colors.white,
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(20),
),
title: const Text(
'AI 피드백 삭제',
style: TextStyle(
color: Color(0xFF1E293B),
fontSize: 18,
fontWeight: FontWeight.w800,
),
),
content: const Text(
'이 AI 피드백을 삭제하시겠습니까?\n'
'삭제하면 저장된 리포트도 함께 삭제됩니다.',
style: TextStyle(
color: Color(0xFF64748B),
fontSize: 14,
height: 1.5,
),
),
actions: [
TextButton(
onPressed: () {
Navigator.pop(
dialogContext,
false,
);
},
child: const Text(
'취소',
style: TextStyle(
color: Color(0xFF64748B),
fontWeight: FontWeight.w600,
),
),
),
TextButton(
onPressed: () {
Navigator.pop(
dialogContext,
true,
);
},
child: const Text(
'삭제',
style: TextStyle(
color: Color(0xFFFF5C69),
fontWeight: FontWeight.w700,
),
),
),
],
);
},
);

if (shouldDelete == true) {
await _deleteAiFeedback(documentId);
}
}

// ─────────────────────────────────────────────
// 스낵바
// ─────────────────────────────────────────────

void _showSnackBar(String message) {
if (!mounted) return;

ScaffoldMessenger.of(context)
..hideCurrentSnackBar()
..showSnackBar(
SnackBar(
content: Text(message),
behavior: SnackBarBehavior.floating,
duration: const Duration(seconds: 2),
),
);
}

// ─────────────────────────────────────────────
// BUILD
// ─────────────────────────────────────────────

@override
Widget build(BuildContext context) {
return Scaffold(
backgroundColor: const Color(0xFFF8F9FA),

appBar: AppBar(
title: Text(
"$_userName 님께 온 편지",
style: const TextStyle(
color: Colors.black,
fontWeight: FontWeight.w900,
fontSize: 18,
),
),
centerTitle: true,
backgroundColor: Colors.white,
elevation: 0,
leading: IconButton(
icon: const Icon(
Icons.arrow_back_ios_new,
color: Colors.black,
size: 20,
),
onPressed: () => Navigator.pop(context),
),
),

body: Builder(
builder: (context) {
final uid =
FirebaseAuth.instance.currentUser?.uid;

if (uid == null) {
return const Center(
child: Text("로그인이 필요합니다."),
);
}

return StreamBuilder<
QuerySnapshot<Map<String, dynamic>>>(
stream: FirebaseFirestore.instance
    .collection('users')
    .doc(uid)
    .collection('ai_feedback_diaries')
    .orderBy(
'created_at',
descending: true,
)
    .snapshots(),

builder: (context, snapshot) {
if (snapshot.hasError) {
debugPrint(
'AI 피드백 목록 오류: ${snapshot.error}',
);

return const Center(
child: Text(
"AI 피드백 목록을 불러오지 못했습니다.",
),
);
}

if (snapshot.connectionState ==
ConnectionState.waiting ||
_isLoadingName) {
return const Center(
child: CircularProgressIndicator(
valueColor:
AlwaysStoppedAnimation<Color>(
Color(0xFF6FD0F1),
),
),
);
}

if (!snapshot.hasData ||
snapshot.data!.docs.isEmpty) {
return _buildEmptyState();
}

final docs = snapshot.data!.docs;

return ListView.separated(
physics:
const BouncingScrollPhysics(),

padding: const EdgeInsets.symmetric(
horizontal: 20,
vertical: 20,
),

itemCount: docs.length,

separatorBuilder: (_, __) =>
const SizedBox(height: 15),

itemBuilder: (context, index) {
final doc = docs[index];

final data = doc.data();

// Firestore 문서 ID
final String documentId = doc.id;

// AI 피드백 내용
final String content =
data['request_date']
    ?.toString()
    .trim()
    .isNotEmpty ==
true
? data['request_date']
    .toString()
    : '분석 내용이 비어 있습니다.';

// AI 분석 날짜
final String dateStr =
_formatDate(
data['created_at'],
);

return GestureDetector(
onTap: () {
_showLetterDetail(
context,
dateStr,
content,
);
},

child: Container(
padding:
const EdgeInsets.all(20),

decoration: BoxDecoration(
color: Colors.white,
borderRadius:
BorderRadius.circular(22),

boxShadow: [
BoxShadow(
color: Colors.black
    .withOpacity(0.03),
blurRadius: 10,
offset:
const Offset(0, 4),
),
],
),

child: Column(
crossAxisAlignment:
CrossAxisAlignment.start,

children: [
// 날짜 + 삭제 버튼
Row(
children: [
Expanded(
child: Text(
dateStr,
maxLines: 1,
overflow:
TextOverflow
    .ellipsis,
style:
const TextStyle(
color:
Color(
0xFF94A3B8,
),
fontSize: 12,
fontWeight:
FontWeight.w600,
),
),
),

const SizedBox(
width: 8,
),

Container(
padding:
const EdgeInsets
    .symmetric(
horizontal: 10,
vertical: 4,
),
decoration:
BoxDecoration(
color: pointColor
    .withOpacity(
0.15,
),
borderRadius:
BorderRadius
    .circular(
8,
),
),
child: Text(
'STAY AI 리포트',
style: TextStyle(
color:
pointColor,
fontWeight:
FontWeight.bold,
fontSize: 11,
),
),
),

const SizedBox(
width: 4,
),

// 삭제 버튼
IconButton(
onPressed: () {
_showDeleteConfirmDialog(
documentId,
);
},
icon: const Icon(
Icons
    .delete_outline_rounded,
color:
Color(0xFFFF5C69),
size: 21,
),
tooltip: '삭제',
padding:
EdgeInsets.zero,
constraints:
const BoxConstraints(
minWidth: 36,
minHeight: 36,
),
),
],
),

const SizedBox(
height: 12,
),

// AI 피드백 내용
Text(
content,
maxLines: 3,
overflow:
TextOverflow.ellipsis,
style:
const TextStyle(
fontSize: 14,
color:
Color(0xFF334155),
height: 1.5,
),
),

const SizedBox(
height: 14,
),

// 자세히 보기
Row(
mainAxisAlignment:
MainAxisAlignment.end,
children: [
Text(
'자세히 보기',
style:
TextStyle(
color:
pointColor,
fontSize: 12,
fontWeight:
FontWeight.w700,
),
),

const SizedBox(
width: 4,
),

Icon(
Icons
    .arrow_forward_ios_rounded,
color:
pointColor,
size: 12,
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
},
),
);
}

// ─────────────────────────────────────────────
// AI 피드백 상세 보기
// ─────────────────────────────────────────────

void _showLetterDetail(
BuildContext context,
String date,
String content,
) {
showModalBottomSheet(
context: context,
isScrollControlled: true,
backgroundColor: Colors.transparent,

builder: (context) {
return Container(
height:
MediaQuery.of(context).size.height *
0.8,

decoration:
const BoxDecoration(
color: Colors.white,
borderRadius:
BorderRadius.vertical(
top: Radius.circular(35),
),
),

padding:
const EdgeInsets.fromLTRB(
30,
20,
30,
20,
),

child: Column(
crossAxisAlignment:
CrossAxisAlignment.start,

children: [
Center(
child: Container(
width: 45,
height: 5,
decoration:
BoxDecoration(
color: Colors.grey[200],
borderRadius:
BorderRadius.circular(
10,
),
),
),
),

const SizedBox(height: 25),

Row(
mainAxisAlignment:
MainAxisAlignment
    .spaceBetween,

children: [
Text(
date,
style: TextStyle(
color: pointColor,
fontWeight:
FontWeight.bold,
fontSize: 14,
),
),

const Icon(
Icons.auto_awesome,
color: Colors.amber,
size: 20,
),
],
),

const SizedBox(height: 10),

const Text(
"STAY 분석 리포트",
style: TextStyle(
fontSize: 22,
fontWeight:
FontWeight.w900,
color:
Color(0xFF1E293B),
),
),

const Divider(
height: 30,
thickness: 1.2,
),

Expanded(
child:
SingleChildScrollView(
physics:
const BouncingScrollPhysics(),

child: Text(
content,
style:
const TextStyle(
fontSize: 16,
height: 1.8,
color:
Color(0xFF334155),
letterSpacing: -0.3,
),
),
),
),

const SizedBox(height: 20),

SizedBox(
width: double.infinity,
height: 54,

child: ElevatedButton(
onPressed: () =>
Navigator.pop(context),

style:
ElevatedButton.styleFrom(
backgroundColor:
pointColor,
shape:
RoundedRectangleBorder(
borderRadius:
BorderRadius
    .circular(
16,
),
),
elevation: 0,
),

child: const Text(
"닫기",
style: TextStyle(
color: Colors.white,
fontWeight:
FontWeight.bold,
fontSize: 16,
),
),
),
),

SizedBox(
height:
MediaQuery.of(context)
    .padding
    .bottom,
),
],
),
);
},
);
}

// ─────────────────────────────────────────────
// 데이터가 없을 때
// ─────────────────────────────────────────────

Widget _buildEmptyState() {
return Center(
child: Column(
mainAxisAlignment:
MainAxisAlignment.center,

children: [
Icon(
Icons.mail_lock_rounded,
size: 80,
color: Colors.grey[300],
),

const SizedBox(height: 25),

Text(
"아직 $_userName 님을 위한\n"
"분석 편지가 도착하지 않았어요.",

textAlign: TextAlign.center,

style: const TextStyle(
color: Color(0xFF334155),
fontSize: 16,
fontWeight:
FontWeight.w600,
height: 1.5,
),
),

const SizedBox(height: 10),

const Text(
"오늘의 공부 기록을 남기고\n"
"AI에게 따뜻한 피드백을 받아보세요!",

textAlign: TextAlign.center,

style: TextStyle(
color: Color(0xFF94A3B8),
fontSize: 14,
),
),
],
),
);
}
}

