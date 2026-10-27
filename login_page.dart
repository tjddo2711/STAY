import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';

import 'Welcome.dart';
import 'main.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final GoogleSignIn _googleSignIn = GoogleSignIn();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _pwController = TextEditingController();

  bool isLoginPage = true;

  final Color pointColor = const Color(0xFF6FD0F1);
  final Color signUpColor = const Color(0xFF3A86FF);

  @override
  void dispose() {
    _emailController.dispose();
    _pwController.dispose();
    super.dispose();
  }

  Future<void> _handleSignUp() async {
    try {
      final email = _emailController.text.trim();
      final password = _pwController.text.trim();

      if (email.isEmpty || password.isEmpty) {
        _showError("이메일과 비밀번호를 입력해주세요.");
        return;
      }

      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = credential.user;

      if (user == null) {
        _showError("회원가입 실패");
        return;
      }

      await user.sendEmailVerification();

      await _createInitialUserData(
        uid: user.uid,
        name: email.split('@')[0],
        email: email,
        provider: 'email',
      );

      _showSuccess("인증 이메일 발송 완료");

      setState(() {
        isLoginPage = true;
      });

    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        _showError("이미 사용중인 이메일입니다.");
      } else {
        _showError(e.message ?? "회원가입 실패");
      }
    }
  }

  // =========================
  // 이메일 로그인
  // =========================

  Future<void> _handleLogin() async {
    try {
      final email = _emailController.text.trim();
      final password = _pwController.text.trim();

      if (email.isEmpty || password.isEmpty) {
        _showError("이메일과 비밀번호를 입력해주세요.");
        return;
      }

      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = credential.user;

      if (user == null) {
        _showError("로그인 실패");
        return;
      }

      await user.reload();
      final currentUser = _auth.currentUser;

      if (currentUser == null) {
        _showError("사용자 정보를 불러올 수 없습니다.");
        return;
      }

      if (!currentUser.emailVerified) {
        await _auth.signOut();
        _showError("이메일 인증 후 로그인해주세요.");
        return;
      }

      await _createInitialUserData(
        uid: currentUser.uid,
        name: currentUser.email?.split('@')[0] ?? "사용자",
        email: currentUser.email ?? "",
        provider: "email",
      );

      await _checkAndNavigateAfterLogin(currentUser);

    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential') {
        _showError("이메일 또는 비밀번호가 잘못되었습니다.");
      } else {
        _showError(e.message ?? "로그인 실패");
      }
    } catch (e) {
      debugPrint("로그인 오류 : $e");
      _showError("로그인 중 오류가 발생했습니다.");
    }
  }
  // =========================
  // 구글 로그인
  // =========================

  Future<void> _signInWithGoogle() async {
    try {
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
      }

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;

      if (user == null) {
        _showError("구글 로그인 실패");
        return;
      }

      await _createInitialUserData(
        uid: user.uid,
        name: user.displayName ?? "사용자",
        email: user.email ?? "",
        provider: "google",
      );

      await _checkAndNavigateAfterLogin(user);

    } on FirebaseAuthException catch (e) {
      debugPrint("FirebaseAuth 오류 : ${e.code}");
      _showError(e.message ?? "구글 로그인 실패");
    } catch (e, s) {
      debugPrint("Google 로그인 오류 : $e");
      debugPrint(s.toString());
      _showError("구글 로그인 중 오류 발생");
    }
  }

  // =========================
  // Firestore 초기 데이터 생성
  // =========================

  Future<void> _checkAndNavigateAfterLogin(User user) async {
    try {
      final profileDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('user_profile')
          .doc('current')
          .get();

      final data = profileDoc.data();
      final bool onboardingCompleted =
          (data?['name']?.toString().trim().isNotEmpty ?? false) &&
              (data?['goal']?.toString().trim().isNotEmpty ?? false);

      if (!mounted) return;

      if (onboardingCompleted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const RootScreen()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const WelcomePage()),
        );
      }
    } catch (e) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RootScreen()),
      );
    }
  }


  Future<void> _createInitialUserData({
    required String uid,
    required String name,
    required String email,
    required String provider,
  }) async {
    final userDoc = _firestore.collection('users').doc(uid);
    final profileDoc = userDoc.collection('user_profile').doc('current');

    final profileSnapshot = await profileDoc.get();

    // 이미 프로필이 존재하고 데이터가 채워져 있다면 유지
    if (profileSnapshot.exists) {
      final data = profileSnapshot.data();
      if (data?['name'] != null && data?['goal'] != null) {
        return;
      }
    }

    final now = FieldValue.serverTimestamp();

    // DB 설계에 정의된 user_profile 필드만 생성 및 초기화
    await profileDoc.set({
      'name': name,
      'mbti': '',
      'home_address': '',
      'home_lat': 0.0,
      'home_lng': 0.0,
      'goal': '',
      'gender': '',
      'point': 0,
      'email': email,
      'provider': provider,
      'created_at': now,
      'updated_at': now,
    }, SetOptions(merge: true));
  }

  // =========================
  // 홈 이동
  // =========================

  void _goHome() {

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
        const RootScreen(),
      ),
    );
  }

  // =========================
  // 스낵바
  // =========================

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  // =========================
  // UI
  // =========================

  @override
  Widget build(BuildContext context) {
    final Color currentThemeColor = isLoginPage ? pointColor : signUpColor;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 60),
                Text(
                  "STAY",
                  style: TextStyle(
                    fontSize: 54,
                    fontWeight: FontWeight.w900,
                    color: currentThemeColor,
                    letterSpacing: 4,
                  ),
                ),
                Text(
                  isLoginPage ? "나만의 집중 공간, 머무름" : "새로운 여정의 시작",
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 70),
                _buildTextField(
                  "이메일",
                  _emailController,
                  Icons.email_outlined,
                  currentThemeColor,
                ),
                const SizedBox(height: 15),
                _buildTextField(
                  "비밀번호",
                  _pwController,
                  Icons.lock_outline,
                  currentThemeColor,
                  obscure: true,
                ),
                const SizedBox(height: 30),
                _mainButton(
                  isLoginPage ? "로그인" : "회원가입 완료",
                  currentThemeColor,
                  isLoginPage ? _handleLogin : _handleSignUp,
                ),
                const SizedBox(height: 15),
                TextButton(
                  onPressed: () {
                    setState(() {
                      isLoginPage = !isLoginPage;
                    });
                    _emailController.clear();
                    _pwController.clear();
                  },
                  child: Text(
                    isLoginPage ? "아직 회원이 아니신가요? 회원가입" : "이미 계정이 있으신가요? 로그인",
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                _divider(),
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _socialGoogleButton(
                      "assets/google_logo2.png",
                      _signInWithGoogle,
                    ),
                  ],
                ),
                const SizedBox(height: 60),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =========================
  // 텍스트필드
  // =========================

  Widget _buildTextField(
      String hint,
      TextEditingController controller,
      IconData icon,
      Color themeColor, {
        bool obscure = false,
      }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 15),
      decoration: BoxDecoration(
        color: themeColor.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: themeColor.withOpacity(0.3),
          width: 1.2,
        ),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        cursorColor: themeColor,
        decoration: InputDecoration(
          icon: Icon(
            icon,
            color: themeColor.withOpacity(0.7),
            size: 20,
          ),
          hintText: hint,
          hintStyle: TextStyle(
            color: Colors.grey.shade400,
            fontSize: 14,
          ),
          border: InputBorder.none,
        ),
      ),
    );
  }


  // =========================
  // 메인 버튼
  // =========================

  Widget _mainButton(
      String text,
      Color color,
      VoidCallback onTap,
      ) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
  // =========================
  // 구글 버튼
  // =========================

  Widget _socialGoogleButton(
      String imgPath,
      VoidCallback onTap,
      ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 270,
        height: 55,
        padding: const EdgeInsets.symmetric(
          horizontal: 1,
          vertical: 5,
        ),
        child: Image.asset(
          imgPath,
          fit: BoxFit.contain,
        ),
      ),
    );
  }

  // =========================
  // 구분선
  // =========================

  Widget _divider() {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            "간편 로그인",
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 12,
            ),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}