import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';

const Color pointColor = Color(0xFF6FD0F1);
const Color primaryDarkColor = Color(0xFF38BDF8);
const Color bgColor = Color(0xFFF5F8FB);
const Color darkText = Color(0xFF17212B);
const Color subText = Color(0xFF7D8A96);

class PointPage extends StatefulWidget {
  const PointPage({super.key});

  @override
  State<PointPage> createState() => _PointPageState();
}

class _PointPageState extends State<PointPage> {
  // ============================================================
  // AD
  // ============================================================

  RewardedAd? _rewardedAd;

  bool _isLoadingAd = true;
  bool _isRewardProcessing = false;

  final int rewardPoint = 100;
  final int dailyLimit = 10;

  // ============================================================
  // FREE CHARGE ITEMS
  // ============================================================

  final List<Map<String, dynamic>> _offerItems = [
    {
      'title': '미션형',
      'icon': Icons.task_alt_rounded,
      'color': Color(0xFFFFB020),
      'badge': '인기',
      'description': '간단한 미션을 완료하고 포인트를 받아보세요.',
    },
    {
      'title': '앱 설치형',
      'icon': Icons.download_rounded,
      'color': Color(0xFF20B486),
      'badge': '추천',
      'description': '새로운 앱을 설치하고 실행하면 포인트를 적립할 수 있어요.',
    },
    {
      'title': '쇼핑',
      'icon': Icons.shopping_bag_rounded,
      'color': Color(0xFF8B5CF6),
      'badge': '추천',
      'description': '제휴 쇼핑을 이용하고 포인트를 적립해보세요.',
    },
  ];

  // ============================================================
  // INIT / DISPOSE
  // ============================================================

  @override
  void initState() {
    super.initState();
    _loadRewardedAd();
  }

  @override
  void dispose() {
    _rewardedAd?.dispose();
    super.dispose();
  }

  // ============================================================
  // LOAD REWARDED AD
  // ============================================================

  void _loadRewardedAd() {
    if (!mounted) return;

    setState(() {
      _isLoadingAd = true;
    });

    RewardedAd.load(
      adUnitId: 'ca-app-pub-3940256099942544/5224354917',
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;

          ad.fullScreenContentCallback =
              FullScreenContentCallback(
                onAdDismissedFullScreenContent: (ad) {
                  ad.dispose();

                  _rewardedAd = null;

                  if (mounted) {
                    _loadRewardedAd();
                  }
                },
                onAdFailedToShowFullScreenContent:
                    (ad, error) {
                  ad.dispose();

                  _rewardedAd = null;

                  if (mounted) {
                    _loadRewardedAd();
                  }
                },
              );

          if (mounted) {
            setState(() {
              _isLoadingAd = false;
            });
          }
        },
        onAdFailedToLoad: (error) {
          _rewardedAd = null;

          debugPrint(
            'RewardedAd 로드 실패: $error',
          );

          if (mounted) {
            setState(() {
              _isLoadingAd = false;
            });
          }
        },
      ),
    );
  }

  // ============================================================
  // TODAY AD COUNT
  // ============================================================

  Future<int> _getTodayAdCount() async {
    final user =
        FirebaseAuth.instance.currentUser;

    if (user == null) return 0;

    try {
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);

      final doc = await userRef.get();

      final data = doc.data() ?? {};

      final profile =
      data['user_profile'] is Map
          ? Map<String, dynamic>.from(
        data['user_profile'],
      )
          : <String, dynamic>{};

      final String today =
      DateFormat('yyyy-MM-dd')
          .format(DateTime.now());

      final String resetDate =
          profile['reward_ad_reset_date']
              ?.toString() ??
              '';

      int count = 0;

      final rawCount =
      profile['daily_reward_ad_count'];

      if (rawCount is num) {
        count = rawCount.toInt();
      } else if (rawCount is String) {
        count = int.tryParse(rawCount) ?? 0;
      }

      // 날짜가 바뀌면 자동 초기화
      if (resetDate != today) {
        await userRef.set(
          {
            'user_profile': {
              'daily_reward_ad_count': 0,
              'reward_ad_reset_date': today,
            },
          },
          SetOptions(merge: true),
        );

        return 0;
      }

      return count.clamp(0, dailyLimit);
    } catch (e) {
      debugPrint(
        '광고 횟수 확인 실패: $e',
      );

      return 0;
    }
  }

  // ============================================================
  // SHOW REWARDED AD
  // ============================================================

  Future<void> _showRewardAd() async {
    final user =
        FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showSnack('로그인이 필요합니다.');
      return;
    }

    if (_isRewardProcessing) {
      return;
    }

    final todayCount =
    await _getTodayAdCount();

    if (todayCount >= dailyLimit) {
      _showSnack(
        '오늘 광고 충전 횟수를 모두 사용했습니다.',
      );
      return;
    }

    final ad = _rewardedAd;

    if (ad == null) {
      _showSnack(
        '광고를 준비하고 있습니다. 잠시 후 다시 시도해주세요.',
      );

      _loadRewardedAd();

      return;
    }

    setState(() {
      _isRewardProcessing = true;
    });

    _rewardedAd = null;

    bool rewardEarned = false;

    ad.show(
      onUserEarnedReward:
          (ad, reward) async {
        if (rewardEarned) return;

        rewardEarned = true;

        try {
          await _grantReward(
            user.uid,
          );

          if (mounted) {
            _showSnack(
              '+$rewardPoint P가 지급되었습니다.',
            );
          }
        } catch (e) {
          debugPrint(
            '포인트 지급 실패: $e',
          );

          if (mounted) {
            _showSnack(
              '포인트 지급에 실패했습니다.',
            );
          }
        }
      },
    );

    if (mounted) {
      setState(() {
        _isRewardProcessing = false;
      });
    }
  }

  // ============================================================
  // GRANT REWARD
  // ============================================================

  Future<void> _grantReward(
      String uid,
      ) async {
    final firestore =
        FirebaseFirestore.instance;

    final profileRef = firestore
        .collection('users')
        .doc(uid)
        .collection('user_profile')
        .doc('current');

    final userRef = firestore
        .collection('users')
        .doc(uid);

    final today =
    DateFormat('yyyy-MM-dd')
        .format(DateTime.now());

    await firestore.runTransaction(
          (transaction) async {
        final profileSnapshot =
        await transaction.get(
          profileRef,
        );

        int currentPoint = 0;

        if (profileSnapshot.exists) {
          final data =
          profileSnapshot.data();

          if (data != null) {
            final rawPoint =
            data['point'];

            if (rawPoint is num) {
              currentPoint =
                  rawPoint.toInt();
            } else if (rawPoint is String) {
              currentPoint =
                  int.tryParse(
                    rawPoint.trim(),
                  ) ??
                      0;
            }
          }
        }

        final userSnapshot =
        await transaction.get(
          userRef,
        );

        final userData =
            userSnapshot.data() ?? {};

        final profileData =
        userData['user_profile']
        is Map
            ? Map<String, dynamic>.from(
          userData['user_profile'],
        )
            : <String, dynamic>{};

        String resetDate =
            profileData[
            'reward_ad_reset_date']
                ?.toString() ??
                '';

        int currentCount = 0;

        final rawCount =
        profileData[
        'daily_reward_ad_count'];

        if (rawCount is num) {
          currentCount =
              rawCount.toInt();
        } else if (rawCount is String) {
          currentCount =
              int.tryParse(rawCount) ?? 0;
        }

        if (resetDate != today) {
          currentCount = 0;
          resetDate = today;
        }

        if (currentCount >= dailyLimit) {
          throw Exception(
            'DAILY_LIMIT_REACHED',
          );
        }

        final updatedPoint =
            currentPoint + rewardPoint;

        transaction.set(
          profileRef,
          {
            'point': updatedPoint,
            'updated_at':
            FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        transaction.set(
          userRef,
          {
            'user_profile': {
              'daily_reward_ad_count':
              currentCount + 1,
              'reward_ad_reset_date':
              resetDate,
            },
          },
          SetOptions(merge: true),
        );
      },
    );
  }

  // ============================================================
  // COMPLETE STUDY SESSION
  // ============================================================

  Future<void> completeStudySession({
    required String sessionId,
    required String scheduleId,
    required int studyMinutes,
    required bool isSuccess,
  }) async {
    final user =
        FirebaseAuth.instance.currentUser;

    if (user == null) return;

    final uid = user.uid;

    final firestore =
        FirebaseFirestore.instance;

    final sessionRef = firestore
        .collection('users')
        .doc(uid)
        .collection('study_sessions')
        .doc(sessionId);

    final profileRef = firestore
        .collection('users')
        .doc(uid)
        .collection('user_profile')
        .doc('current');

    final int earnedPoints =
    isSuccess
        ? studyMinutes * 10
        : 0;

    await firestore.runTransaction(
          (transaction) async {
        final profileSnapshot =
        await transaction.get(
          profileRef,
        );

        int currentPoints = 0;

        if (profileSnapshot.exists) {
          final data =
          profileSnapshot.data();

          final rawPoint =
          data?['point'];

          if (rawPoint is num) {
            currentPoints =
                rawPoint.toInt();
          } else if (rawPoint is String) {
            currentPoints =
                int.tryParse(
                  rawPoint.trim(),
                ) ??
                    0;
          }
        }

        final updatedPoints =
            currentPoints + earnedPoints;

        transaction.update(
          sessionRef,
          {
            'study_minutes':
            studyMinutes,
            'is_success':
            isSuccess,
            'is_failed':
            !isSuccess,
            'arrival_verified':
            true,
            'end_time':
            FieldValue.serverTimestamp(),
          },
        );

        transaction.set(
          profileRef,
          {
            'point':
            updatedPoints,
            'updated_at':
            FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      },
    );
  }

  // ============================================================
  // POINT CARD
  // ============================================================

  Widget _buildPointCard() {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const SizedBox();
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('user_profile')
          .doc('current')
          .snapshots(),
      builder: (context, snapshot) {
        final isDark = Theme.of(context).brightness == Brightness.dark;

        final cardTextColor = isDark ? Colors.white : darkText;

        int point = 0;

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data();
          final rawPoint = data?['point'];

          if (rawPoint is num) {
            point = rawPoint.toInt();
          } else if (rawPoint is String) {
            point = int.tryParse(rawPoint.trim()) ?? 0;
          }
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(24, 23, 20, 22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xFF38BDF8),
                Color(0xFF65D5F2),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: primaryDarkColor.withOpacity(.25),
                blurRadius: 25,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 39,
                    height: 39,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.18),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 11),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MY POINT',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.3,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '현재 보유 포인트',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'POINT',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .8,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 25),
              Text(
                NumberFormat('#,###').format(point),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 39,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.5,
                ),
              ),
              const SizedBox(height: 1),
              const Text(
                'P',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                height: 1,
                color: Colors.white.withOpacity(.16),
              ),
              const SizedBox(height: 14),
            ],
          ),
        );
      },
    );
  }
  // ============================================================
  // REWARD SECTION
  // ============================================================

  Widget _buildRewardSection() {
    return FutureBuilder<int>(
      future: _getTodayAdCount(),
      builder: (context, snapshot) {
        final isDark = Theme.of(context).brightness == Brightness.dark;

        final cardColor = isDark
            ? const Color(0xFF1E293B)
            : Colors.white;

        final textColor = isDark ? Colors.white : darkText;

        final subTextColor = isDark
            ? const Color(0xFFB0BEC5)
            : subText;

        final borderColor = isDark
            ? const Color(0xFF334155)
            : const Color(0xFFE8EEF3);

        final infoBackground = isDark
            ? const Color(0xFF263548)
            : const Color(0xFFF6FAFC);

        final int count = snapshot.data ?? 0;

        final int remaining =
        (dailyLimit - count).clamp(0, dailyLimit);

        final double progress =
        (count / dailyLimit).clamp(0.0, 1.0);

        final bool exhausted = remaining <= 0;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(27),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? .15 : .035),
                blurRadius: 22,
                offset: const Offset(0, 9),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 43,
                    height: 43,
                    decoration: BoxDecoration(
                      color: primaryDarkColor.withOpacity(.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.play_circle_fill_rounded,
                      color: primaryDarkColor,
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '무료 포인트 충전',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '광고를 보고 100P를 받아보세요.',
                          style: TextStyle(
                            color: subTextColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 23),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: infoBackground,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _rewardInfo(
                        '1회 보상',
                        '+100P',
                        Icons.stars_rounded,
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 32,
                      color: borderColor,
                    ),
                    Expanded(
                      child: _rewardInfo(
                        '오늘 남은 횟수',
                        '$remaining회',
                        Icons.refresh_rounded,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 19),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '오늘 충전량',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '$count / $dailyLimit',
                    style: const TextStyle(
                      color: primaryDarkColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: isDark
                      ? const Color(0xFF475569)
                      : const Color(0xFFEAF0F4),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    pointColor,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: exhausted ||
                      _isLoadingAd ||
                      _isRewardProcessing
                      ? null
                      : _showRewardAd,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryDarkColor,
                    disabledBackgroundColor: isDark
                        ? const Color(0xFF475569)
                        : const Color(0xFFE9EEF2),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(17),
                    ),
                  ),
                  child: _isRewardProcessing || _isLoadingAd
                      ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: exhausted
                              ? subTextColor
                              : Colors.white,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Text(
                        _isRewardProcessing
                            ? '포인트 지급 중...'
                            : '광고 준비 중...',
                        style: TextStyle(
                          color: exhausted
                              ? subTextColor
                              : Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  )
                      : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.play_arrow_rounded,
                        color: exhausted
                            ? subTextColor
                            : Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        exhausted
                            ? '오늘 충전 횟수를 모두 사용했어요'
                            : '광고 보고 +100P 받기',
                        style: TextStyle(
                          color: exhausted
                              ? subTextColor
                              : Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 13),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    color: subTextColor,
                    size: 13,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '날짜가 바뀌면 충전 횟수가 초기화됩니다.',
                    style: TextStyle(
                      color: subTextColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _rewardInfo(
      String title,
      String value,
      IconData icon,
      ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final textColor = isDark ? Colors.white : darkText;

    final subTextColor = isDark
        ? const Color(0xFFB0BEC5)
        : subText;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          icon,
          color: primaryDarkColor,
          size: 17,
        ),
        const SizedBox(width: 7),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: subTextColor,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ],
    );
  }  // ============================================================
  // FREE CHARGE SECTION
  // ============================================================

  // ============================================================
  // SNACK
  // ============================================================

  void _showSnack(String message) {
    if (!mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: isDark
                ? const Color(0xFF17212B)
                : Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? const Color(0xFFE2E8F0)
            : darkText,
        margin: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
      ),
    );
  }
  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final backgroundColor = isDark
        ? const Color(0xFF0F172A)
        : bgColor;

    final textColor = isDark ? Colors.white : darkText;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar(
              backgroundColor: backgroundColor,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              pinned: false,
              automaticallyImplyLeading: true,
              expandedHeight: 92,
              flexibleSpace: FlexibleSpaceBar(
                background: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    20,
                    25,
                    20,
                    10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '포인트',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.2,
                        ),
                      ),
                      const SizedBox(height: 3),
                    ],
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                20,
                0,
                20,
                40,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  [
                    _buildPointCard(),
                    const SizedBox(height: 18),
                    _buildRewardSection(),

                    // 하단 '더 많은 포인트 받기' 광고 영역 제거
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}