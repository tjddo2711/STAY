import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'login_page.dart';
import 'main.dart'; // pointColor와 RootScreen 등을 참조하기 위함

// 로컬 알림 플러그인 전역 인스턴스
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

class SettingsPage extends StatefulWidget {
  final ValueChanged<bool>? onDarkModeChanged; // 다크모드 외부 연동을 위한 콜백
  const SettingsPage({super.key, this.onDarkModeChanged});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 실제 기능을 위한 상태 변수들
  bool _isNotificationOn = true;
  bool _isDarkMode = false;

  final Color pointColor = const Color(0xFF6FD0F1); // 메인 하늘색
  final Color subBlue = const Color(0xFF3A86FF);    // 진한 블루

  @override
  void initState() {
    super.initState();

    // 현재 전역 테마 상태를 설정창에 반영
    _isDarkMode = themeModeNotifier.value == ThemeMode.dark;

    // 다른 화면에서 테마가 변경되어도 설정창 상태 동기화
    themeModeNotifier.addListener(_onThemeChanged);

    _initNotifications();
  }

  @override
  void dispose() {
    themeModeNotifier.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _changeDarkMode(bool value) {
    themeModeNotifier.value =
    value ? ThemeMode.dark : ThemeMode.light;

    if (!mounted) return;

    setState(() {
      _isDarkMode = value;
    });

    widget.onDarkModeChanged?.call(value);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor:
        value ? const Color(0xFF2A2A2A) : Colors.white,
        content: Text(
          value
              ? '다크 모드가 적용되었습니다.'
              : '라이트 모드가 적용되었습니다.',
          style: TextStyle(
            color: value ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  void _onThemeChanged() {
    if (!mounted) return;

    setState(() {
      _isDarkMode = themeModeNotifier.value == ThemeMode.dark;
    });
  }

  // 알림 초기화 설정
  Future<void> _initNotifications() async {
    tz.initializeTimeZones();

    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
    DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    return Scaffold(
      backgroundColor: _isDarkMode
          ? const Color(0xFF121212)
          : const Color(0xFFF8FBFD),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: _isDarkMode
            ? const Color(0xFF1E1E1E)
            : Colors.white,
        centerTitle: true,
        title: Text(
          "설정",
          style: TextStyle(
            color: _isDarkMode
                ? Colors.white
                : Colors.grey.shade800,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new,
            color: _isDarkMode
                ? Colors.white
                : Colors.grey.shade800,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 10,
        ),
        children: [
          const SizedBox(height: 10),

          user != null
              ? _buildProfileCard(user)
              : _buildProfileCardFallback("로그인 정보 없음"),

          const SizedBox(height: 30),

          _buildSectionTitle("계정 설정"),

          _buildSettingsGroup([
            _buildListTile(
              Icons.lock_outline,
              "비밀번호 변경",
              onTap: () {
                _handlePasswordChangeCheck(user);
              },
            ),
          ]),

          const SizedBox(height: 25),

          _buildSectionTitle("앱 이용 설정"),

          _buildSettingsGroup([
            _buildSwitchTile(
              Icons.notifications_none_rounded,
              "알림",
              _isNotificationOn,
                  (val) {
                setState(() {
                  _isNotificationOn = val;
                });

                _handleNotificationSetting(val);
              },
            ),

            // ⭐ 기존 익명 함수 제거
            // ⭐ 전역 다크모드 변경 함수 연결
            _buildSwitchTile(
              Icons.dark_mode_outlined,
              "다크 모드",
              _isDarkMode,
              _changeDarkMode,
            ),
          ]),

          const SizedBox(height: 25),

          _buildSectionTitle("기타"),

          _buildSettingsGroup([
            _buildListTile(
              Icons.bug_report_outlined,
              "오류 제보",
              onTap: _handleErrorReport,
            ),

            _buildListTile(
              Icons.info_outline,
              "앱 버전 정보",
              trailingText: "1.0.0",
            ),

            _buildListTile(
              Icons.logout_rounded,
              "로그아웃",
              textColor: Colors.redAccent,
              iconColor: Colors.redAccent,
              onTap: _handleSignOut,
            ),

            _buildListTile(
              Icons.person_remove_outlined,
              "회원 탈퇴",
              textColor: Colors.redAccent,
              iconColor: Colors.redAccent,
              onTap: _handleDeleteAccount,
            ),
          ]),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // --- 프로필 카드 ---
  Widget _buildProfileCard(User user) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('user_profile')
          .doc('current')
          .snapshots(),
      builder: (context, snapshot) {
        String displayName = user.email ?? "사용자";
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          if (data != null && data['이름'] != null && data['이름'].toString().isNotEmpty) {
            displayName = data['이름'];
          }
        }

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: pointColor.withOpacity(0.2),
                child: Icon(Icons.person, color: subBlue, size: 30),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("반가워요!", style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text(displayName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _isDarkMode ? Colors.white : Colors.black)),
                    const SizedBox(height: 2),
                    Text(user.email ?? "", style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildProfileCardFallback(String text) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: pointColor.withOpacity(0.2),
            child: Icon(Icons.person, color: subBlue, size: 30),
          ),
          const SizedBox(width: 15),
          Text(text, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: _isDarkMode ? Colors.white : Colors.black)),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 5, bottom: 10),
      child: Text(title,
          style: TextStyle(color: _isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.w600)
      ),
    );
  }

  Widget _buildSettingsGroup(List<Widget> tiles) {
    return Container(
      decoration: BoxDecoration(
        color: _isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(children: tiles),
    );
  }

  Widget _buildListTile(IconData icon, String title, {VoidCallback? onTap, Color? textColor, Color? iconColor, String? trailingText}) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? (_isDarkMode ? Colors.white70 : Colors.grey.shade700), size: 22),
      title: Text(title, style: TextStyle(fontSize: 15, color: textColor ?? (_isDarkMode ? Colors.white : Colors.black87), fontWeight: FontWeight.w500)),
      trailing: trailingText != null
          ? Text(trailingText, style: const TextStyle(color: Colors.grey))
          : const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  Widget _buildSwitchTile(
      IconData icon,
      String title,
      bool value,
      Function(bool) onChanged,
      ) {
    return ListTile(
      leading: Icon(
        icon,
        color: _isDarkMode
            ? Colors.white70
            : Colors.grey.shade700,
        size: 22,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: _isDarkMode
              ? Colors.white
              : Colors.black87,
        ),
      ),
      trailing: CupertinoSwitch(
        value: value,

        // ⭐ OFF 상태
        trackColor: Colors.grey.shade300,

        // ⭐ ON 상태
        activeColor: pointColor,

        thumbColor: Colors.white,

        onChanged: onChanged,
      ),
    );
  }

  // --- 기능 메서드들 ---

  // 이메일 로그인 사용자만 비밀번호 변경 가능하도록 체크
  Future<void> _handlePasswordChangeCheck(User? user) async {
    if (user == null) return;

    bool isEmailLogin = user.providerData.any((info) => info.providerId == 'password');

    if (!isEmailLogin) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: _isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.info_outline_rounded, color: pointColor, size: 22),
              const SizedBox(width: 8),
              Text("알림", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: _isDarkMode ? Colors.white : Colors.black)),
            ],
          ),
          content: Padding(
            padding: const EdgeInsets.only(top: 5.0),
            child: Text(
              "구글 계정은 해당 플랫폼에서 비밀번호를 관리하므로 앱 내에서 변경할 수 없습니다.",
              style: TextStyle(fontSize: 14, color: _isDarkMode ? Colors.white70 : Colors.black87, height: 1.4),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: pointColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text("확인", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
        ),
      );
      return;
    }

    _showChangePasswordDialog(user);
  }

  // 비밀번호 변경 재설정 메일 발송
  Future<void> _showChangePasswordDialog(User user) async {
    bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text("비밀번호 변경", style: TextStyle(fontWeight: FontWeight.bold, color: _isDarkMode ? Colors.white : Colors.black)),
        content: Text("현재 계정(${user.email})으로 비밀번호 재설정 이메일을 발송합니다. 변경하시겠습니까?", style: TextStyle(color: _isDarkMode ? Colors.white70 : Colors.black87)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("취소", style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text("발송하기", style: TextStyle(color: subBlue, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _auth.sendPasswordResetEmail(email: user.email!);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('비밀번호 재설정 이메일이 발송되었습니다. 메일함을 확인해주세요.')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('메일 발송 실패: $e')),
        );
      }
    }
  }

  // 푸시 알림 설정 (30분 전 스케줄 알림 등록 로직 연동)
  Future<void> _handleNotificationSetting(bool isOn) async {
    if (isOn) {
      // 1. 알림 권한 요청 (Android 13+ 및 iOS)
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
      flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      await androidImplementation?.requestNotificationsPermission();
      await androidImplementation?.requestExactAlarmsPermission();

      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);

      // 2. 현재 로그인된 유저의 Firestore 스케줄들을 불러와 30분 전 알림 예약
      final user = _auth.currentUser;
      if (user != null) {
        try {
          final querySnapshot = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('schedules')
              .get();

          for (var doc in querySnapshot.docs) {
            final data = doc.data();
            final status = data['status']?.toString() ?? '';

            // 완료, 취소, 삭제된 일정은 제외
            if (status == 'completed' || status == 'cancelled' || status == 'deleted') {
              continue;
            }

            final dynamic startValue = data['start_time'] ?? data['start_datetime'] ?? data['startTime'];
            final String dateStr = data['date_str']?.toString() ?? data['dateStr']?.toString() ?? '';

            DateTime? startTime = _parseScheduleTime(startValue, dateStr: dateStr);
            if (startTime == null) continue;

            // ★ 시작 시간 30분 전 계산
            final DateTime notificationTime = startTime.subtract(const Duration(minutes: 30));

            // 이미 지난 시간이라면 예약하지 않음
            if (notificationTime.isBefore(DateTime.now())) continue;

            final tz.TZDateTime scheduledDate = tz.TZDateTime.from(notificationTime, tz.local);
            final int notificationId = doc.id.hashCode.abs() % 2147483647;
            final String title = data['title']?.toString() ?? '예정된 일정';

            const AndroidNotificationDetails androidPlatformChannelSpecifics =
            AndroidNotificationDetails(
              'schedule_channel',
              '일정 알림',
              channelDescription: '스케줄 시작 30분 전 알림을 제공합니다.',
              importance: Importance.max,
              priority: Priority.high,
            );

            const NotificationDetails platformChannelSpecifics =
            NotificationDetails(android: androidPlatformChannelSpecifics);

            await flutterLocalNotificationsPlugin.zonedSchedule(
              notificationId,
              '⏰ 30분 후 일정 시작',
              '\'$title\' 일정이 30분 뒤에 시작됩니다!',
              scheduledDate,
              platformChannelSpecifics,
              androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
              uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
            );
          }
        } catch (e) {
          debugPrint("알림 예약 중 오류 발생: $e");
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('메인 일정 기준 30분 전 알림이 설정되었습니다.')),
      );
    } else {
      // 알림이 꺼지면 모든 예약된 알림 취소
      await flutterLocalNotificationsPlugin.cancelAll();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('푸시 알림이 꺼졌고 예약된 알림이 취소되었습니다.')),
      );
    }
  }

  // 스케줄 시간 파싱 헬퍼 메서드
  DateTime? _parseScheduleTime(dynamic value, {required String dateStr}) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toLocal();

      if (value.length <= 5 && value.contains(':') && dateStr.isNotEmpty) {
        try {
          final parts = value.split(':');
          final hour = int.parse(parts[0]);
          final minute = int.parse(parts[1]);
          return DateTime(
            int.parse(dateStr.substring(0, 4)),
            int.parse(dateStr.substring(5, 7)),
            int.parse(dateStr.substring(8, 10)),
            hour,
            minute,
          );
        } catch (_) {}
      }
    }
    return null;
  }

  Future<void> _handleErrorReport() async {
    final reportController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text("오류 제보 및 피드백", style: TextStyle(fontWeight: FontWeight.bold, color: _isDarkMode ? Colors.white : Colors.black)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("욕설 및 비방글은 사용이 제한됩니다.",
                style: TextStyle(fontSize: 13, color: _isDarkMode ? Colors.white70 : Colors.grey.shade600)),
            const SizedBox(height: 15),
            TextField(
              controller: reportController,
              maxLines: 4,
              style: TextStyle(color: _isDarkMode ? Colors.white : Colors.black),
              decoration: InputDecoration(
                hintText: "오류 내용을 상세히 적어주세요.",
                hintStyle: TextStyle(color: _isDarkMode ? Colors.grey.shade500 : Colors.grey.shade400),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: pointColor, width: 2)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("취소", style: TextStyle(color: Colors.grey))
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: pointColor, foregroundColor: Colors.white),
            onPressed: () async {
              final content = reportController.text.trim();
              if (content.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("내용을 입력해주세요.")));
                return;
              }

              try {
                // vlxk12@naver.com으로 수신될 수 있도록 Firestore에 제보 데이터 저장 (관리자 백엔드에서 vlxk12@naver.com 연동용)
                final user = _auth.currentUser;
                await FirebaseFirestore.instance.collection('error_reports').add({
                  'target_email': 'vlxk12@naver.com',
                  'user_email': user?.email ?? '비회원',
                  'uid': user?.uid ?? 'unknown',
                  'content': content,
                  'timestamp': FieldValue.serverTimestamp(),
                });

                if (!mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('오류 제보가 vlxk12@naver.com 관리자에게 전송되었습니다!')),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('전송 실패: $e')),
                );
              }
            },
            child: const Text("보내기"),
          ),
        ],
      ),
    );
  }

  // 로그아웃 기능
  Future<void> _handleSignOut() async {
    bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text("로그아웃", style: TextStyle(fontWeight: FontWeight.bold, color: _isDarkMode ? Colors.white : Colors.black)),
        content: Text("정말 로그아웃 하시겠습니까?", style: TextStyle(color: _isDarkMode ? Colors.white70 : Colors.black87)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("취소", style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text("로그아웃", style: TextStyle(color: subBlue))),
        ],
      ),
    );

    if (confirm == true) {
      await _auth.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const LoginPage()),
              (route) => false
      );
    }
  }

  // 회원 탈퇴 기능
  Future<void> _handleDeleteAccount() async {
    bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("회원 탈퇴", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
        content: Text("탈퇴 시 모든 공부 데이터와 프로필이 영구 삭제됩니다. 정말 탈퇴하시겠습니까?", style: TextStyle(color: _isDarkMode ? Colors.white70 : Colors.black87)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("취소")),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("탈퇴하기", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final user = _auth.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance.collection('users').doc(user.uid).delete();
      await user.delete();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('회원 탈퇴가 완료되었습니다.')));

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginPage()),
            (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      debugPrint("탈퇴 오류: ${e.code}");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('탈퇴 실패: ${e.message}. 재로그인 후 다시 시도해주세요.')),
      );
    } catch (e) {
      debugPrint("기타 오류: $e");
    }
  }
}