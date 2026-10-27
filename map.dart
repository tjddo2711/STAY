import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'dart:convert';
import 'package:http/http.dart' as http;

class MapSelectionPage extends StatefulWidget {
  final TimeOfDay startTime;
  final int duration;
  final DateTime selectedDate;
  final bool isFromCalendar;
  final String? title;
  final int? colorValue;

  const MapSelectionPage({
    super.key,
    required this.startTime,
    required this.duration,
    required this.selectedDate,
    required this.isFromCalendar,
    this.title,
    this.colorValue,
  });

  @override
  State<MapSelectionPage> createState() => _MapSelectionPageState();
}

class _MapSelectionPageState extends State<MapSelectionPage> {


  NaverMapController? _mapController;
  NLatLng? selectedLocation;
  static const String _ncpClientId = 'gcoze7lkvx';
  static const String _ncpClientSecret = 'xEaW2Nf7ykn3vsZUGBld1kuokBbmCKLcD7DvFkcU';

  String selectedName = "지도를 탭하여 장소를 선택하세요";
  String selectedAddress = "";
  bool isFavorite = false;
  String? currentFavoriteDocId;

  NLatLng _initialCenter = const NLatLng(36.6285, 127.4563);
  bool _isLoadingLocation = true;

  final Color pointColor = const Color(0xFF6FD0F1);
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initLocation();
    geo.setLocaleIdentifier("ko_KR");
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
        Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
        if (mounted) {
          setState(() {
            _initialCenter = NLatLng(pos.latitude, pos.longitude);
            _isLoadingLocation = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoadingLocation = false;
          });
        }
      }
    } catch (e) {
      debugPrint("초기 위치 조회 실패: $e");
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
        });
      }
    }
  }

  void _onMapReady(NaverMapController controller) {
    _mapController = controller;
    _moveToCurrent();
  }

  Future<void> _moveToCurrent() async {
    try {
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
      final myLatLng = NLatLng(pos.latitude, pos.longitude);
      final cameraUpdate = NCameraUpdate.withParams(target: myLatLng, zoom: 16)
        ..setAnimation(duration: const Duration(milliseconds: 600));
      await _mapController?.updateCamera(cameraUpdate);
    } catch (e) {
      debugPrint("현재 위치 이동 오류: $e");
    }
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  Future<void> _checkFavoriteStatus(NLatLng latlng) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('favorite_locations')
        .where('latitude', isEqualTo: latlng.latitude)
        .where('longitude', isEqualTo: latlng.longitude)
        .get();

    setState(() {
      if (snapshot.docs.isNotEmpty) {
        isFavorite = true;
        currentFavoriteDocId = snapshot.docs.first.id;
      } else {
        isFavorite = false;
        currentFavoriteDocId = null;
      }
    });
  }

  Future<void> _showFavoriteList() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              "즐겨찾는 장소",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .collection('favorite_locations')
                    .orderBy('created_at', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(pointColor),
                      ),
                    );
                  }

                  final docs = snapshot.data!.docs;

                  if (docs.isEmpty) {
                    return Center(
                      child: Text(
                        "저장된 즐겨찾기가 없습니다.",
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;

                      return ListTile(
                        leading: const Icon(
                          Icons.star,
                          color: Colors.orange,
                        ),
                        title: Text(
                          data['location_name']?.toString() ?? "이름 없음",
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        subtitle: Text(
                          data['address']?.toString() ?? "",
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                        onTap: () {
                          Navigator.pop(context);

                          _onLocationSelected(
                            NLatLng(
                              (data['latitude'] as num).toDouble(),
                              (data['longitude'] as num).toDouble(),
                            ),
                            data['location_name']?.toString() ?? "이름 없음",
                            address: data['address']?.toString() ?? "",
                          );
                        },
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

  Future<void> _searchPlace(String query) async {
    final keyword = query.trim();

    if (keyword.isEmpty) {
      _showSnackBar("장소를 입력해주세요.");
      return;
    }

    FocusScope.of(context).unfocus();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      final locations = await geo.locationFromAddress(keyword);

      if (!mounted) return;

      Navigator.of(context, rootNavigator: true).pop();

      if (locations.isEmpty) {
        _showSnackBar("'$keyword' 검색 결과가 없습니다.");
        return;
      }

      final List<Map<String, dynamic>> results = [];

      for (final location in locations.take(10)) {
        String address = "";

        try {
          final placemarks = await geo.placemarkFromCoordinates(
            location.latitude,
            location.longitude,
          );

          if (placemarks.isNotEmpty) {
            final place = placemarks.first;

            final parts = <String>[
              if (place.administrativeArea?.isNotEmpty == true)
                place.administrativeArea!,
              if (place.locality?.isNotEmpty == true)
                place.locality!,
              if (place.subLocality?.isNotEmpty == true)
                place.subLocality!,
              if (place.thoroughfare?.isNotEmpty == true)
                place.thoroughfare!,
              if (place.subThoroughfare?.isNotEmpty == true)
                place.subThoroughfare!,
            ];

            address = parts.join(" ");
          }
        } catch (e) {
          debugPrint("좌표 주소 변환 실패: $e");
        }

        results.add({
          "name": keyword,
          "address": address,
          "latitude": location.latitude,
          "longitude": location.longitude,
        });
      }

      if (results.isEmpty) {
        _showSnackBar("'$keyword' 검색 결과가 없습니다.");
        return;
      }

      await _showDeviceGeocodeResults(
        results,
        keyword,
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
      }

      debugPrint("장소 검색 오류: $e");

      if (mounted) {
        _showSnackBar(
          "장소 검색에 실패했습니다.\n"
              "주소를 조금 더 자세하게 입력해주세요.",
        );
      }
    }
  }

  Future<void> _showDeviceGeocodeResults(
      List<Map<String, dynamic>> results,
      String keyword,
      ) async {
    if (!mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark
          ? const Color(0xFF1E1E1E)
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Column(
              children: [
                const SizedBox(height: 14),

                Container(
                  width: 45,
                  height: 5,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white30
                        : Colors.black26,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),

                const SizedBox(height: 18),

                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                  ),
                  child: Row(
                    children: [
                      Text(
                        "장소 검색 결과",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? Colors.white
                              : Colors.black,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "${results.length}개",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: pointColor,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                Divider(
                  height: 1,
                  color: isDark
                      ? Colors.white12
                      : Colors.black12,
                ),

                Expanded(
                  child: ListView.separated(
                    itemCount: results.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: isDark
                          ? Colors.white12
                          : Colors.black12,
                    ),
                    itemBuilder: (context, index) {
                      final result = results[index];

                      final name =
                          result["name"]?.toString() ?? keyword;

                      final address =
                          result["address"]?.toString() ?? "";

                      final latitude =
                      (result["latitude"] as num).toDouble();

                      final longitude =
                      (result["longitude"] as num).toDouble();

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        leading: Icon(
                          Icons.location_on,
                          color: pointColor,
                          size: 28,
                        ),
                        title: Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            address.isNotEmpty
                                ? address
                                : "주소 정보 없음",
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white60
                                  : Colors.black54,
                            ),
                          ),
                        ),
                        trailing: Icon(
                          Icons.chevron_right,
                          color: isDark
                              ? Colors.white38
                              : Colors.black38,
                        ),
                        onTap: () {
                          Navigator.pop(sheetContext);

                          _onLocationSelected(
                            NLatLng(
                              latitude,
                              longitude,
                            ),
                            name,
                            address: address,
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
      },
    );
  }


  Future<void> _showGeocodeResults(
      List<dynamic> addresses,
      String keyword,
      ) async {
    if (!mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark
          ? const Color(0xFF1E1E1E)
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Column(
              children: [
                const SizedBox(height: 14),

                Container(
                  width: 45,
                  height: 5,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white30
                        : Colors.black26,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),

                const SizedBox(height: 18),

                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                  ),
                  child: Row(
                    children: [
                      Text(
                        '장소 검색 결과',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? Colors.white
                              : Colors.black,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${addresses.length}개',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: pointColor,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                Divider(
                  height: 1,
                  color: isDark
                      ? Colors.white12
                      : Colors.black12,
                ),

                Expanded(
                  child: ListView.separated(
                    itemCount: addresses.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: isDark
                          ? Colors.white12
                          : Colors.black12,
                    ),
                    itemBuilder: (context, index) {
                      final item =
                      addresses[index] as Map<String, dynamic>;

                      final roadAddress =
                          item['roadAddress']?.toString() ?? '';

                      final jibunAddress =
                          item['jibunAddress']?.toString() ?? '';

                      final englishAddress =
                          item['englishAddress']?.toString() ?? '';

                      final displayAddress =
                      roadAddress.isNotEmpty
                          ? roadAddress
                          : jibunAddress.isNotEmpty
                          ? jibunAddress
                          : englishAddress;

                      final latitude =
                      double.tryParse(
                        item['y']?.toString() ?? '',
                      );

                      final longitude =
                      double.tryParse(
                        item['x']?.toString() ?? '',
                      );

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        leading: Icon(
                          Icons.location_on,
                          color: pointColor,
                          size: 28,
                        ),
                        title: Text(
                          displayAddress.isNotEmpty
                              ? displayAddress
                              : keyword,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? Colors.white
                                : Colors.black,
                          ),
                        ),
                        subtitle: jibunAddress.isNotEmpty &&
                            jibunAddress != displayAddress
                            ? Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(
                            '지번 $jibunAddress',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isDark
                                  ? Colors.white60
                                  : Colors.black54,
                            ),
                          ),
                        )
                            : null,
                        trailing: Icon(
                          Icons.chevron_right,
                          color: isDark
                              ? Colors.white38
                              : Colors.black38,
                        ),
                        onTap: () async {
                          if (latitude == null || longitude == null) {
                            _showSnackBar(
                              '해당 장소의 좌표가 올바르지 않습니다.',
                            );
                            return;
                          }

                          Navigator.pop(sheetContext);

                          _onLocationSelected(
                            NLatLng(latitude, longitude),
                            keyword,
                            address: displayAddress,
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
      },
    );
  }

  Future<void> _showPlaceList(List<dynamic> items) async {
    if (!mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 45,
                  height: 5,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white30 : Colors.black26,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Text(
                        "장소 검색 결과",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "${items.length}개",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: pointColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Divider(
                  height: 1,
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      indent: 72,
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                    itemBuilder: (context, index) {
                      final place = items[index];

                      final title = _removeHtmlTags(
                        place["title"]?.toString() ?? "이름 없음",
                      );
                      final roadAddress = place["roadAddress"]?.toString() ?? "";
                      final address = place["address"]?.toString() ?? "";
                      final displayAddress =
                      roadAddress.isNotEmpty ? roadAddress : address;

                      final double mapx = double.tryParse(place["mapx"]?.toString() ?? "0") ?? 0;
                      final double mapy = double.tryParse(place["mapy"]?.toString() ?? "0") ?? 0;

                      return InkWell(
                        onTap: () async {
                          Navigator.pop(sheetContext);

                          await _selectSearchPlace(
                            name: title,
                            address: displayAddress,
                            roadAddress: roadAddress,
                            jibunAddress: address,
                            mapx: mapx,
                            mapy: mapy,
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: pointColor.withOpacity(0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.location_on,
                                  color: pointColor,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? Colors.white : Colors.black,
                                      ),
                                    ),
                                    const SizedBox(height: 7),
                                    if (roadAddress.isNotEmpty)
                                      Text(
                                        roadAddress,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: isDark ? Colors.white70 : Colors.black54,
                                        ),
                                      ),
                                    if (address.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          "지번 $address",
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isDark ? Colors.white38 : Colors.black45,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.chevron_right,
                                color: isDark ? Colors.white38 : Colors.black38,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _removeHtmlTags(String text) {
    return text
        .replaceAll(RegExp(r"<[^>]*>"), "")
        .replaceAll("&amp;", "&")
        .replaceAll("&lt;", "<")
        .replaceAll("&gt;", ">")
        .replaceAll("&quot;", '"')
        .replaceAll("&#39;", "'")
        .trim();
  }
  Future<void> _selectSearchPlace({
    required String name,
    required String address,
    String roadAddress = "",
    String jibunAddress = "",
    double mapx = 0,
    double mapy = 0,
  }) async {
    if (!mounted) return;

    BuildContext? dialogContext;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        dialogContext = context;
        return const Center(child: CircularProgressIndicator());
      },
    );

    try {
      List<geo.Location> locations = [];

      // 1. 도로명 주소로 좌표 조회
      if (roadAddress.trim().isNotEmpty) {
        try {
          locations = await geo.locationFromAddress(roadAddress);
        } catch (_) {}
      }

      // 2. 지번 주소로 좌표 조회
      if (locations.isEmpty && jibunAddress.trim().isNotEmpty) {
        try {
          locations = await geo.locationFromAddress(jibunAddress);
        } catch (_) {}
      }

      // 3. 일반 주소로 좌표 조회
      if (locations.isEmpty && address.trim().isNotEmpty) {
        try {
          locations = await geo.locationFromAddress(address);
        } catch (_) {}
      }

      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
      }

      if (!mounted) return;

      NLatLng selectedLatLng;

      if (locations.isNotEmpty) {
        final location = locations.first;
        selectedLatLng = NLatLng(location.latitude, location.longitude);
      } else if (mapx > 0 && mapy > 0) {
        // Geocoding 실패 시 TM128 좌표를 위경도로 직접 변환
        selectedLatLng = _convertTM128ToLatLng(mapx, mapy);
      } else {
        _showSnackBar("해당 장소의 좌표를 찾을 수 없습니다.");
        return;
      }

      _onLocationSelected(
        selectedLatLng,
        name,
        address: address,
      );
    } catch (e) {
      debugPrint("검색 장소 좌표 변환 오류: $e");

      if (dialogContext != null && dialogContext!.mounted) {
        Navigator.of(dialogContext!).pop();
      }

      if (mounted) {
        _showSnackBar("장소 위치를 불러오지 못했습니다.");
      }
    }
  }

  // TM128 정수 좌표를 WGS84 위경도 좌표로 변환하는 로직
  NLatLng _convertTM128ToLatLng(double mapx, double mapy) {
    if (mapx <= 0 || mapy <= 0) return _initialCenter;

    // 이미 위경도 형태 데이터일 경우 예외 처리
    if (mapx < 200 && mapy < 200) {
      return NLatLng(mapy, mapx);
    }

    final double x = mapx;
    final double y = mapy;

    final double lng = (x - 300000) / 88000.0 + 127.5;
    final double lat = (y - 500000) / 111000.0 + 38.0;

    final double realLat = lat + (y - (38.0 + (lat - 38.0)) * 111000.0 - 500000.0) / 110900.0 * 0.00001;
    final double realLng = lng + (x - (127.5 + (lng - 127.5)) * 88000.0 - 300000.0) / 88500.0 * 0.00001;

    return NLatLng(realLat, realLng);
  }

  void _onLocationSelected(
      NLatLng latlng,
      String name, {
        String address = "",
      }) {
    setState(() {
      selectedLocation = latlng;
      selectedName = name;
      selectedAddress = address;

      _searchController.text = name;
    });

    _checkFavoriteStatus(latlng);
    _updateMarker();
  }

  Future<void> _updateMarker() async {
    if (selectedLocation == null) return;
    await _mapController?.clearOverlays();

    final marker = NMarker(id: "selected", position: selectedLocation!);
    await _mapController?.addOverlay(marker);

    final infoWindow = NInfoWindow.onMarker(id: "info", text: selectedName);
    marker.openInfoWindow(infoWindow);

    // 좌표 선택 시 해당 위치로 지도 카메라 이동 연출
    final cameraUpdate = NCameraUpdate.withParams(
      target: selectedLocation!,
      zoom: 16,
    )..setAnimation(duration: const Duration(milliseconds: 500));

    await _mapController?.updateCamera(cameraUpdate);
  }

  void _editPlaceNickname() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final controller = TextEditingController(
      text: selectedName == "직접 선택한 위치" ? "" : selectedName,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          "장소 이름 수정",
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
          ),
          decoration: InputDecoration(
            hintText: "예: 학교 도서관",
            hintStyle: TextStyle(
              color: isDark ? Colors.white54 : Colors.black45,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: pointColor,
                width: 2,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              "취소",
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                setState(() {
                  selectedName = controller.text.trim();
                  _searchController.text = selectedName;
                });

                _updateMarker();
              }

              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: pointColor,
              foregroundColor: Colors.white,
            ),
            child: const Text("확인"),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleFavorite() async {
    if (selectedLocation == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final collection = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('favorite_locations');

    if (isFavorite) {
      if (currentFavoriteDocId != null) {
        await collection.doc(currentFavoriteDocId).delete();
        setState(() {
          isFavorite = false;
          currentFavoriteDocId = null;
        });
        _showSnackBar("'$selectedName' 즐겨찾기 해제");
      }
    } else {
      final docRef = await collection.add({
        'location_name': selectedName,
        'address': selectedAddress,
        'latitude': selectedLocation!.latitude,
        'longitude': selectedLocation!.longitude,
        'created_at': FieldValue.serverTimestamp(),
      });
      setState(() {
        isFavorite = true;
        currentFavoriteDocId = docRef.id;
      });
      _showSnackBar("'$selectedName' 즐겨찾기 저장 완료");
    }
  }

  void _save() {
    if (selectedLocation == null) {
      _showSnackBar("장소를 선택해주세요.");
      return;
    }

    Navigator.pop(context, {
      "location": {
        "name": selectedName,
        "address": selectedAddress,
        "latitude": selectedLocation!.latitude,
        "longitude": selectedLocation!.longitude,
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? const Color(0xFF121212) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;

    return Scaffold(
      backgroundColor: backgroundColor,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          "장소 지정",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: textColor,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoadingLocation
          ? Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(pointColor),
        ),
      )
          : Stack(
        children: [
          NaverMap(
            options: NaverMapViewOptions(
              locationButtonEnable: false,
              consumeSymbolTapEvents: true,
              initialCameraPosition: NCameraPosition(
                target: _initialCenter,
                zoom: 15,
              ),
            ),
            onMapReady: _onMapReady,
            onSymbolTapped: (symbol) {
              _onLocationSelected(
                symbol.position,
                symbol.caption,
              );
            },
            onMapTapped: (point, latlng) async {
              String addressText = "";

              try {
                final placemarks = await geo.placemarkFromCoordinates(
                  latlng.latitude,
                  latlng.longitude,
                );

                if (placemarks.isNotEmpty) {
                  final p = placemarks.first;
                  addressText = "${p.locality ?? ''} ${p.subLocality ?? ''} ${p.thoroughfare ?? ''}".trim();
                }
              } catch (e) {
                debugPrint("주소 변환 실패: $e");
              }

              _onLocationSelected(
                latlng,
                addressText.isNotEmpty ? addressText : "선택한 위치",
                address: addressText,
              );
            },
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 60,
            left: 20,
            right: 20,
            child: Container(
              height: 55,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.star,
                      color: Colors.orange,
                    ),
                    onPressed: _showFavoriteList,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: TextStyle(color: textColor),
                      textInputAction: TextInputAction.search,
                      onSubmitted: _searchPlace,
                      decoration: InputDecoration(
                        hintText: "장소 검색",
                        hintStyle: TextStyle(
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                        border: InputBorder.none,
                        prefixIcon: IconButton(
                          icon: Icon(
                            Icons.search,
                            color: pointColor,
                          ),
                          onPressed: () {
                            _searchPlace(_searchController.text);
                          },
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            Icons.my_location,
                            color: pointColor,
                          ),
                          onPressed: _moveToCurrent,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (selectedLocation != null)
            Positioned(
              left: 20,
              right: 20,
              bottom: 40,
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    margin: const EdgeInsets.only(bottom: 15),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 15,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: _editPlaceNickname,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        selectedName,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: textColor,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      Icons.edit_note,
                                      color: pointColor,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  selectedAddress.isEmpty ? "주소 없음" : selectedAddress,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark ? Colors.white70 : Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            isFavorite ? Icons.star : Icons.star_border,
                            color: Colors.orange,
                            size: 32,
                          ),
                          onPressed: _toggleFavorite,
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: pointColor,
                      minimumSize: const Size.fromHeight(60),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: const Text(
                      "이 위치 선택",
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}