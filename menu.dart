import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'inform.dart';
import 'settings_page.dart';

const Color pointColor = Color(0xFF6FD0F1);
const Color subBlue = Color(0xFF3A86FF);

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;

    final bool isDark =
        Theme.of(context).brightness == Brightness.dark;

    return Drawer(
      backgroundColor:
      isDark ? const Color(0xFF121212) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: StreamBuilder<DocumentSnapshot>(
        stream: user != null
            ? FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('profile')
            .doc('current')
            .snapshots()
            : null,
        builder: (context, snapshot) {
          String displayName = "사용자";

          if (snapshot.hasData && snapshot.data!.exists) {
            final data =
            snapshot.data!.data() as Map<String, dynamic>?;
            displayName = data?['name']?.toString() ?? "사용자";
          }

          return Column(
            children: [
              _buildCustomHeader(
                displayName,
                user?.email ?? "정보 없음",
              ),

              const SizedBox(height: 10),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  children: [
                    _drawerItem(
                      Icons.person_outline,
                      "내 정보 수정",
                          () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const InformPage(),
                          ),
                        );
                      },
                    ),

                    Divider(
                      height: 30,
                      thickness: 1,
                      indent: 10,
                      endIndent: 10,
                      color: isDark
                          ? Colors.white24
                          : Colors.black12,
                    ),

                    _drawerItem(
                      Icons.settings_outlined,
                      "앱 설정",
                          () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SettingsPage(),
                          ),
                        );
                      },
                    ),

                    _drawerItem(
                      Icons.help_outline_rounded,
                      "도움말",
                          () {},
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.only(bottom: 30),
                child: Text(
                  "STAY v1.0.0",
                  style: TextStyle(
                    color: isDark
                        ? Colors.white38
                        : Colors.grey.shade400,
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // 컴팩트 헤더 위젯
  Widget _buildCustomHeader(String name, String email) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(
        top: 75,
        left: 25,
        right: 25,
        bottom: 40,
      ),
      decoration: const BoxDecoration(
        color: pointColor,
        borderRadius: BorderRadius.only(
          bottomRight: Radius.circular(40),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: const CircleAvatar(
                  radius: 25,
                  backgroundColor: Color(0xFFE1F5FE),
                  child: Icon(
                    Icons.person,
                    color: subBlue,
                    size: 30,
                  ),
                ),
              ),

              const SizedBox(width: 15),

              Expanded(
                child: Builder(
                  builder: (context) {
                    return Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,
                      children: [
                        Text(
                          "$name님",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          email,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 15),

          const Text(
            "오늘도 성장을 위해 머무르세요.",
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
  // 드로어 개별 아이템 위젯
  Widget _drawerItem(
      IconData icon,
      String title,
      VoidCallback onTap,
      ) {
    return Builder(
      builder: (context) {
        final bool isDark =
            Theme.of(context).brightness == Brightness.dark;

        return ListTile(
          leading: Icon(
            icon,
            color: isDark
                ? Colors.white70
                : Colors.grey.shade700,
            size: 22,
          ),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? Colors.white
                  : Colors.black87,
            ),
          ),
          onTap: onTap,
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        );
      },
    );
  }}