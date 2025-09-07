import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// ===============================================================
/// ===============  CẤU HÌNH API KEYS (QUAN TRỌNG)  ==============
/// ===============================================================
/// Key A (Maps SDK) đã khai trong AndroidManifest/Info.plist.
/// Key B (REST - Places API) dùng cho Autocomplete/Nearby/Details.
/// - Hãy hạn chế API chỉ cho Places và đặt quota.
/// - Production: cân nhắc gọi qua proxy server để giấu key.
const String placesWebApiKeyB = 'AIzaSyCsxalL8q8DYpCm3wfyuU_y9yAenj6Mifw';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TopRatedPlacesApp());
}

class TopRatedPlacesApp extends StatelessWidget {
  const TopRatedPlacesApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Top Rated Places',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const MapScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// ====== MODELs ======
class PlaceItem {
  final String placeId;
  final String name;
  final double? rating;
  final int? userRatingsTotal;
  final LatLng latLng;
  final String? address;
  final String? types; // gộp vài loại để hiển thị nhanh

  PlaceItem({
    required this.placeId,
    required this.name,
    required this.rating,
    required this.userRatingsTotal,
    required this.latLng,
    required this.address,
    required this.types,
  });
}

class ScoredPlace {
  final PlaceItem item;
  final double score;
  ScoredPlace(this.item, this.score);
}

class AutocompletePrediction {
  final String description;
  final String placeId;

  AutocompletePrediction({required this.description, required this.placeId});

  static List<AutocompletePrediction> fromJsonList(List list) {
    return list.map((e) {
      return AutocompletePrediction(
        description: e['description'] as String? ?? '',
        placeId: e['place_id'] as String? ?? '',
      );
    }).toList();
  }
}

/// ====== UI ======
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final Completer<GoogleMapController> _mapCtrl = Completer();
  LatLng? _current;
  bool _loading = false;
  Set<Marker> _markers = {};
  List<ScoredPlace> _top = [];

  // ====== Search state (Autocomplete) ======
  final TextEditingController _searchCtl = TextEditingController();
  Timer? _debounce;
  List<AutocompletePrediction> _suggests = [];
  bool _searching = false;
  String? _sessionToken; // session token cho Autocomplete

  // ====== Filter state ======
  double _minRating = 4.0;
  int _minReviews = 1000;
  int _radiusKm = 10;

  final List<double> _ratingOptions = [4.0, 4.5, 5.0];
  final List<int> _reviewsOptions = [1000, 5000, 10000];
  final List<int> _radiusOptions = [10, 20, 30];

  // ====== Place type filter ======
  final List<String> _placeTypesOptions = [
    'tourist_attraction',
    'restaurant',
    'park',
    'museum',
    'cafe',
    'bar',
    'shopping_mall',
    'zoo',
    'aquarium',
  ];
  final Set<String> _selectedTypes = {'tourist_attraction', 'restaurant'};

  static const _initSaigon = LatLng(10.776530, 106.700981);

  @override
  void initState() {
    super.initState();
    _ensurePermissionAndLocate();
    _searchCtl.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtl.dispose();
    super.dispose();
  }

  // ====== Helpers ======
  String _newSessionToken() {
    final rnd = math.Random();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  double _distanceMeters(LatLng a, LatLng b) {
    const R = 6371000.0; // Earth radius (m)
    final dLat = (b.latitude - a.latitude) * (math.pi / 180.0);
    final dLng = (b.longitude - a.longitude) * (math.pi / 180.0);
    final la1 = a.latitude * (math.pi / 180.0);
    final la2 = b.latitude * (math.pi / 180.0);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(la1) * math.cos(la2) *
            math.sin(dLng / 2) * math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    return R * c;
  }

  // ====== Permissions + Center to user ======
  Future<void> _ensurePermissionAndLocate() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
    }

    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
    } catch (_) {
      pos = await Geolocator.getLastKnownPosition();
    }

    setState(() {
      _current = (pos != null) ? LatLng(pos.latitude, pos.longitude) : _initSaigon;
    });

    final ctrl = await _mapCtrl.future;
    await ctrl.animateCamera(CameraUpdate.newCameraPosition(
      CameraPosition(target: _current!, zoom: 14.5),
    ));

    _fetchAndShow();
  }

  // ====== Autocomplete ======
  void _onQueryChanged() {
    final q = _searchCtl.text.trim();
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (q.isEmpty) {
        setState(() => _suggests = []);
        return;
      }
      _sessionToken ??= _newSessionToken();
      _fetchAutocomplete(q, _sessionToken!);
    });
  }

  Future<void> _fetchAutocomplete(String input, String token) async {
    setState(() {
      _searching = true;
    });

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/autocomplete/json',
      <String, String>{
        'input': input,
        'language': 'vi',
        'types': 'geocode', // địa danh/địa chỉ
        'key': placesWebApiKeyB,
        'sessiontoken': token,
      },
    );

    try {
      final resp = await http.get(uri);
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final status = data['status'] as String?;
      if (status != 'OK' && status != 'ZERO_RESULTS') {
        final error = data['error_message'] ?? status ?? 'UNKNOWN_ERROR';
        throw Exception(error);
      }
      final preds = AutocompletePrediction.fromJsonList(
          (data['predictions'] as List?) ?? []);
      setState(() {
        _suggests = preds;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Autocomplete lỗi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _onSelectPrediction(AutocompletePrediction p) async {
    final token = _sessionToken ?? _newSessionToken();
    _sessionToken = null; // chốt phiên
    setState(() {
      _searchCtl.text = p.description;
      _suggests = [];
    });

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/details/json',
      <String, String>{
        'place_id': p.placeId,
        'fields': 'geometry,name,formatted_address',
        'language': 'vi',
        'key': placesWebApiKeyB,
        'sessiontoken': token,
      },
    );

    try {
      final resp = await http.get(uri);
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final status = data['status'] as String?;
      if (status != 'OK') {
        final error = data['error_message'] ?? status ?? 'UNKNOWN_ERROR';
        throw Exception(error);
      }
      final result = data['result'] as Map<String, dynamic>;
      final loc = result['geometry']?['location'];
      if (loc == null) throw Exception('Không có geometry');

      final lat = (loc['lat'] as num).toDouble();
      final lng = (loc['lng'] as num).toDouble();
      final target = LatLng(lat, lng);

      setState(() {
        _current = target;
      });

      final ctrl = await _mapCtrl.future;
      await ctrl.animateCamera(CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: 14.5),
      ));

      _fetchAndShow(); // tải top quanh vị trí mới
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Place Details lỗi: $e')),
        );
      }
    }
  }

  // ====== Nearby + Filter + Scoring ======
  Future<void> _fetchAndShow() async {
    if (_current == null) return;
    setState(() => _loading = true);

    try {
      // Lấy theo loại user đã chọn (nếu rỗng -> default 2 loại)
      final types = _selectedTypes.isNotEmpty
          ? _selectedTypes.toList()
          : ['tourist_attraction', 'restaurant'];

      final futures = <Future<List<PlaceItem>>>[
        for (final t in types) _nearby(type: t, radius: _radiusKm * 1000),
      ];
      final results = await Future.wait(futures);

      // Gộp unique theo place_id
      final all = <String, PlaceItem>{};
      for (final list in results) {
        for (final p in list) {
          all[p.placeId] = p;
        }
      }

      // Lọc theo filter người dùng
      final origin = _current!;
      final filtered = all.values.where((p) {
        final rOk = (p.rating ?? 0.0) >= _minRating;
        final vOk = (p.userRatingsTotal ?? 0) >= _minReviews;
        final dOk = _distanceMeters(origin, p.latLng) <= (_radiusKm * 1000);
        return rOk && vOk && dOk;
      }).toList();

      // Tính điểm Weighted Rating
      const m = 50.0; // min reviews threshold
      const C = 4.2;  // ước lượng rating trung bình chung
      final scored = filtered.map((p) {
        final R = p.rating ?? 0.0;
        final v = (p.userRatingsTotal ?? 0).toDouble();
        final weighted = (v / (v + m)) * R + (m / (v + m)) * C;
        return ScoredPlace(p, weighted);
      }).toList();

      // Sắp xếp: theo điểm, nếu bằng thì ưu tiên gần hơn
      scored.sort((a, b) {
        final c = b.score.compareTo(a.score);
        if (c != 0) return c;
        final da = _distanceMeters(origin, a.item.latLng);
        final db = _distanceMeters(origin, b.item.latLng);
        return da.compareTo(db);
      });

      final top = scored.take(20).toList();

      // Vẽ markers + InfoWindow mở chỉ đường
      final newMarkers = <Marker>{};
      for (int i = 0; i < top.length; i++) {
        final sp = top[i];
        final p = sp.item;
        final hue = (i == 0)
            ? BitmapDescriptor.hueOrange
            : (i < 5 ? BitmapDescriptor.hueRose : BitmapDescriptor.hueRed);

        final rating = p.rating != null ? p.rating!.toStringAsFixed(1) : '—';
        final reviews = p.userRatingsTotal ?? 0;
        final snippet = [
          '⭐ $rating  |  $reviews reviews',
          if ((p.types ?? '').isNotEmpty) p.types!,
          if ((p.address ?? '').isNotEmpty) p.address!,
          '(Nhấn info để chỉ đường)'
        ].join('\n');

        final marker = Marker(
          markerId: MarkerId(p.placeId),
          position: p.latLng,
          infoWindow: InfoWindow(
            title: '${i + 1}. ${p.name}',
            snippet: snippet,
            onTap: () => _openNavigation(p.latLng, p.name),
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(hue),
        );
        newMarkers.add(marker);
      }

      setState(() {
        _top = top;
        _markers = newMarkers;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Áp dụng: ⭐≥${_minRating.toStringAsFixed(1)}, reviews ≥ $_minReviews, radius ${_radiusKm}km — ${top.length} kết quả',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không tải được địa điểm: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<PlaceItem>> _nearby({required String type, required int radius}) async {
    final lat = _current!.latitude;
    final lng = _current!.longitude;

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/nearbysearch/json',
      <String, String>{
        'location': '$lat,$lng',
        'radius': '$radius',
        'type': type,         // ví dụ: tourist_attraction, restaurant, park...
        'language': 'vi',
        'key': placesWebApiKeyB,
        // 'opennow': 'true',  // bật nếu muốn chỉ những nơi đang mở cửa
      },
    );

    final resp = await http.get(uri);
    if (resp.statusCode != 200) {
      throw Exception('HTTP ${resp.statusCode}');
    }
    final data = json.decode(resp.body) as Map<String, dynamic>;
    final status = data['status'] as String?;
    if (status != 'OK' && status != 'ZERO_RESULTS') {
      final error = data['error_message'] ?? status ?? 'UNKNOWN_ERROR';
      throw Exception(error);
    }
    final List results = (data['results'] as List?) ?? [];

    return results.map((raw) {
      final pid = raw['place_id'] as String? ?? '';
      final name = raw['name'] as String? ?? 'Unknown';
      final rating = (raw['rating'] is num) ? (raw['rating'] as num).toDouble() : null;
      final userTotal = (raw['user_ratings_total'] is num)
          ? (raw['user_ratings_total'] as num).toInt()
          : null;
      final geo = raw['geometry']?['location'];
      final plat = (geo?['lat'] as num?)?.toDouble() ?? 0.0;
      final plng = (geo?['lng'] as num?)?.toDouble() ?? 0.0;
      final vicinity = raw['vicinity'] as String?;
      final types = (raw['types'] as List?)?.cast<String>().take(3).join(' · ');

      return PlaceItem(
        placeId: pid,
        name: name,
        rating: rating,
        userRatingsTotal: userTotal,
        latLng: LatLng(plat, plng),
        address: vicinity,
        types: types,
      );
    }).where((p) => p.latLng.latitude != 0.0 && p.rating != null).toList();
  }

  Future<void> _openNavigation(LatLng to, String name) async {
    // Ưu tiên Google Maps; nếu không có, thử Apple Maps; cuối cùng geo:
    final google = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${to.latitude},${to.longitude}&travelmode=walking');
    final apple = Uri.parse(
        'http://maps.apple.com/?daddr=${to.latitude},${to.longitude}&dirflg=w');
    if (await canLaunchUrl(google)) {
      await launchUrl(google, mode: LaunchMode.externalApplication);
    } else if (await canLaunchUrl(apple)) {
      await launchUrl(apple, mode: LaunchMode.externalApplication);
    } else {
      final geo = Uri.parse('geo:${to.latitude},${to.longitude}?q=${Uri.encodeComponent(name)}');
      await launchUrl(geo, mode: LaunchMode.externalApplication);
    }
  }

  // ====== UI: Filter Sheet ======
  Future<void> _openFilterSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        double tmpRating = _minRating;
        int tmpReviews = _minReviews;
        int tmpRadius = _radiusKm;
        final tmpTypes = Set<String>.from(_selectedTypes);

        return StatefulBuilder(
          builder: (context, setModal) {
            Widget buildSingleChoiceChips<T>({
              required String title,
              required List<T> options,
              required T selected,
              required void Function(T v) onSelected,
              String Function(T v)? label,
            }) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0, top: 8.0),
                    child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: options.map((opt) {
                      final isSel = opt == selected;
                      return ChoiceChip(
                        label: Text(label != null ? label(opt) : opt.toString()),
                        selected: isSel,
                        onSelected: (_) => setModal(() => onSelected(opt)),
                      );
                    }).toList(),
                  ),
                ],
              );
            }

            Widget buildMultiChoiceChips({
              required String title,
              required List<String> options,
              required Set<String> selectedSet,
            }) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0, top: 8.0),
                    child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: options.map((opt) {
                      final isSel = selectedSet.contains(opt);
                      return FilterChip(
                        label: Text(opt.replaceAll('_', ' ')),
                        selected: isSel,
                        onSelected: (_) => setModal(() {
                          if (isSel) selectedSet.remove(opt); else selectedSet.add(opt);
                        }),
                      );
                    }).toList(),
                  ),
                ],
              );
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    buildSingleChoiceChips<double>(
                      title: 'Điểm số tối thiểu',
                      options: _ratingOptions,
                      selected: tmpRating,
                      onSelected: (v) => tmpRating = v,
                      label: (v) => v.toStringAsFixed(1),
                    ),
                    buildSingleChoiceChips<int>(
                      title: 'Số review tối thiểu',
                      options: _reviewsOptions,
                      selected: tmpReviews,
                      onSelected: (v) => tmpReviews = v,
                      label: (v) => '>$v',
                    ),
                    buildSingleChoiceChips<int>(
                      title: 'Bán kính (km)',
                      options: _radiusOptions,
                      selected: tmpRadius,
                      onSelected: (v) => tmpRadius = v,
                      label: (v) => '$v km',
                    ),
                    buildMultiChoiceChips(
                      title: 'Loại địa điểm (chọn nhiều)',
                      options: _placeTypesOptions,
                      selectedSet: tmpTypes,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.refresh),
                            label: const Text('Đặt lại mặc định'),
                            onPressed: () {
                              setModal(() {
                                tmpRating = 4.0;
                                tmpReviews = 1000;
                                tmpRadius = 10;
                                tmpTypes
                                  ..clear()
                                  ..addAll({'tourist_attraction', 'restaurant'});
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.check),
                            label: const Text('Áp dụng'),
                            onPressed: () {
                              setState(() {
                                _minRating = tmpRating;
                                _minReviews = tmpReviews;
                                _radiusKm = tmpRadius;
                                _selectedTypes
                                  ..clear()
                                  ..addAll(tmpTypes);
                              });
                              Navigator.pop(context);
                              _fetchAndShow(); // tải lại
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cameraTarget = _current ?? _initSaigon;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Top Rated Nearby'),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'Về vị trí của tôi',
            onPressed: _ensurePermissionAndLocate,
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Bộ lọc',
            onPressed: _openFilterSheet,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới',
            onPressed: _fetchAndShow,
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(target: cameraTarget, zoom: 13),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            markers: _markers,
            onMapCreated: (c) => _mapCtrl.complete(c),
          ),

          // ==== Thanh tìm kiếm + gợi ý ====
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Column(
              children: [
                Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(12),
                  child: TextField(
                    controller: _searchCtl,
                    decoration: InputDecoration(
                      hintText: 'Nhập địa điểm (vd: Tokyo, Japan)',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchCtl.text.isNotEmpty
                          ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchCtl.clear();
                            _suggests = [];
                          });
                        },
                      )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                  ),
                ),
                if (_suggests.isNotEmpty || _searching)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black12)],
                    ),
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: _searching
                        ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [CircularProgressIndicator()],
                      ),
                    )
                        : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _suggests.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final s = _suggests[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.place_outlined),
                          title: Text(
                            s.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => _onSelectPrediction(s),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          if (_loading)
            const Positioned.fill(
              child: IgnorePointer(
                child: Center(child: CircularProgressIndicator()),
              ),
            ),

          // ==== Thanh danh sách nhỏ top 5 ====
          if (_top.isNotEmpty)
            Positioned(
              left: 0, right: 0, bottom: 12,
              child: SizedBox(
                height: 120,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  scrollDirection: Axis.horizontal,
                  itemCount: math.min(5, _top.length),
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final sp = _top[i];
                    final p = sp.item;
                    return GestureDetector(
                      onTap: () async {
                        final ctrl = await _mapCtrl.future;
                        await ctrl.animateCamera(
                          CameraUpdate.newLatLngZoom(p.latLng, 16),
                        );
                      },
                      child: Container(
                        width: 240,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black12)],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${i + 1}. ${p.name}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            Text('⭐ ${p.rating?.toStringAsFixed(1) ?? "—"}   ·   ${p.userRatingsTotal ?? 0} reviews',
                                style: const TextStyle(fontSize: 12)),
                            const Spacer(),
                            Text(p.address ?? '',
                                maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _fetchAndShow,
        icon: const Icon(Icons.star),
        label: const Text('Tìm địa điểm nhiều sao'),
      ),
    );
  }
}
