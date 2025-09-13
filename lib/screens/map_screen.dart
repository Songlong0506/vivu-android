import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'login_screen.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../constants/api_keys.dart';
import '../models/autocomplete_prediction.dart';
import '../models/gm_category.dart';
import '../models/place_item.dart';
import '../models/scored_place.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final Map<String, BitmapDescriptor> _catIcons = {};

  Future<void> _loadCatIcons() async {
    for (final entry in kGmCategoryGroups.entries) {
      for (final c in entry.value) {
        if (!_catIcons.containsKey(c.id)) {
          final icon = await BitmapDescriptor.asset(
            const ImageConfiguration(size: Size(48, 48)),
            'assets/icons/${c.id}.png',
          );
          _catIcons[c.id] = icon;
        }
      }
    }
  }

  // Màu marker theo group để phân biệt nhiều category
  final Map<GmGroup, double> _groupHue = {
    GmGroup.foodDrink: BitmapDescriptor.hueRed,
    GmGroup.thingsToDo: BitmapDescriptor.hueAzure,
    GmGroup.shopping: BitmapDescriptor.hueGreen,
    GmGroup.services: BitmapDescriptor.hueViolet,
  };

  // Helper: tra group của một category id
  GmGroup _groupOfCat(String catId) {
    for (final entry in kGmCategoryGroups.entries) {
      if (entry.value.any((c) => c.id == catId)) return entry.key;
    }
    return GmGroup.foodDrink;
  }

  final Completer<GoogleMapController> _mapCtrl = Completer();
  LatLng? _current;

  // Loading + markers/circles
  bool _loading = false;
  Set<Marker> _markers = {};
  Set<Circle> _circles = {};
  List<ScoredPlace> _top = [];

  // Info window popup state
  PlaceItem? _selectedPlace;
  Offset? _infoWindowOffset;

  // Search state
  final TextEditingController _searchCtl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _suppressAutocomplete = false;
  Timer? _debounce;
  List<AutocompletePrediction> _suggests = [];
  bool _searching = false;
  String? _sessionToken;

  // Filter state (rating, reviews, radius)
  double _minRating = 4.0;
  int _minReviews = 1000;
  int _radiusKm = 10;
  final TextEditingController _radiusCustomCtl = TextEditingController();

  final List<double> _ratingOptions = [4.0, 4.5, 5.0];
  final List<int> _reviewsOptions = [500, 1000, 5000, 10000];
  final List<int> _radiusOptions = [5, 10, 20];

  // Category state (Google Maps-like)
  GmGroup _activeGroup = GmGroup.foodDrink;
  final Set<String> _selectedCatIds = {}; // default empty

  // Marker/circle for picked search center
  LatLng? _searchCenter;
  Marker? _searchMarker;

  static const _initSaigon = LatLng(10.776530, 106.700981);

  @override
  void initState() {
    super.initState();
    _loadCatIcons();
    _ensurePermissionAndLocate();
    _searchCtl.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _radiusCustomCtl.dispose();
    _searchCtl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ============== Helpers ==============
  String _newSessionToken() {
    final rnd = math.Random();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  double _distanceMeters(LatLng a, LatLng b) {
    const R = 6371000.0;
    final dLat = (b.latitude - a.latitude) * (math.pi / 180.0);
    final dLng = (b.longitude - a.longitude) * (math.pi / 180.0);
    final la1 = a.latitude * (math.pi / 180.0);
    final la2 = b.latitude * (math.pi / 180.0);
    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(la1) * math.cos(la2) * math.sin(dLng / 2) * math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    return R * c;
  }

  void _renderSearchMarkerAndCircle({bool showMarker = true}) {
    if (_searchCenter == null) {
      setState(() {
        _searchMarker = null;
        _circles = {};
      });
      return;
    }

    final circle = Circle(
      circleId: const CircleId('search_radius'),
      center: _searchCenter!,
      radius: (_radiusKm * 1000).toDouble(),
      strokeWidth: 2,
      strokeColor: const Color(0xFF1E88E5).withOpacity(0.7),
      fillColor: const Color(0xFF1E88E5).withOpacity(0.12),
    );

    Marker? mk;
    if (showMarker) {
      mk = Marker(
        markerId: const MarkerId('search_target'),
        position: _searchCenter!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'Vị trí đã chọn'),
      );
    }

    setState(() {
      _searchMarker = mk; // có thể là null nếu showMarker=false
      _circles = {circle};
    });
  }

  // ============== Permissions + locate ==============
  Future<void> _ensurePermissionAndLocate() async {
    try {
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
          desiredAccuracy: LocationAccuracy.high,
        );
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }

      final here = (pos != null)
          ? LatLng(pos.latitude, pos.longitude)
          : _initSaigon;

      if (mounted) {
        setState(() {
          _current = here;
          _searchCenter = here; // <- dùng chính current làm tâm
        });
      }

      // vẽ RADIUS nhưng KHÔNG vẽ marker (để không đè chấm xanh)
      _renderSearchMarkerAndCircle(showMarker: false);

      final ctrl = await _mapCtrl.future;
      await ctrl.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: here, zoom: 14.5),
        ),
      );

      await _fetchAndShow();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Không thể định vị: $e')));
      }
    }
  }

  // ============== Autocomplete ==============
  void _onQueryChanged() {
    if (_suppressAutocomplete || !_searchFocus.hasFocus) return;
    final q = _searchCtl.text.trim();
    _debounce?.cancel();
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
    setState(() => _searching = true);
    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/autocomplete/json',
      <String, String>{
        'input': input,
        'language': 'vi',
        'types': 'geocode',
        'key': placesWebApiKeyB,
        'sessiontoken': token,
      },
    );
    try {
      final resp = await http.get(uri);
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final preds = AutocompletePrediction.fromJsonList(
        (data['predictions'] as List?) ?? [],
      );
      setState(() => _suggests = preds);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _onSelectPrediction(AutocompletePrediction p) async {
    final token = _sessionToken ?? _newSessionToken();
    _sessionToken = null;

    // chặn listener + ẩn list + bỏ focus
    _suppressAutocomplete = true;
    _debounce?.cancel();
    _searchCtl.removeListener(_onQueryChanged);
    _searchCtl.text = p.description;
    _searchFocus.unfocus();
    setState(() => _suggests = []);
    _searchCtl.addListener(_onQueryChanged);

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

      final target = LatLng(
        (loc['lat'] as num).toDouble(),
        (loc['lng'] as num).toDouble(),
      );

      setState(() {
        _current = target;
        _searchCenter = target;
      });
      _renderSearchMarkerAndCircle(showMarker: true);

      final ctrl = await _mapCtrl.future;
      await ctrl.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: target, zoom: 14.5),
        ),
      );

      await _fetchAndShow();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Place Details lỗi: $e')));
      }
    } finally {
      _suppressAutocomplete = false;
    }
  }

  // ============== Nearby + Filter + Scoring ==============
  Future<List<PlaceItem>> _nearby({
    required String type,
    required int radius,
    String? keyword, // mới
  }) async {
    final lat = _current!.latitude;
    final lng = _current!.longitude;

    final params = <String, String>{
      'location': '$lat,$lng',
      'radius': '$radius',
      'type': type,
      'language': 'vi',
      'key': placesWebApiKeyB,
    };
    if (keyword != null && keyword.trim().isNotEmpty) {
      params['keyword'] = keyword;
    }

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/nearbysearch/json',
      params,
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

    return results
        .map((raw) {
          final pid = raw['place_id'] as String? ?? '';
          final name = raw['name'] as String? ?? 'Unknown';
          final rating = (raw['rating'] is num)
              ? (raw['rating'] as num).toDouble()
              : null;
          final userTotal = (raw['user_ratings_total'] is num)
              ? (raw['user_ratings_total'] as num).toInt()
              : null;
          final geo = raw['geometry']?['location'];
          final plat = (geo?['lat'] as num?)?.toDouble() ?? 0.0;
          final plng = (geo?['lng'] as num?)?.toDouble() ?? 0.0;
          final vicinity = raw['vicinity'] as String?;
          final types = (raw['types'] as List?)
              ?.cast<String>()
              .take(3)
              .join(' · ');
          final photos = raw['photos'] as List?;
          final photoRef = (photos != null && photos.isNotEmpty)
              ? photos.first['photo_reference'] as String?
              : null;
          final photoUrl = (photoRef != null)
              ? 'https://maps.googleapis.com/maps/api/place/photo?maxwidth=400&photo_reference=$photoRef&key=$placesWebApiKeyB'
              : null;

          return PlaceItem(
            placeId: pid,
            name: name,
            rating: rating,
            userRatingsTotal: userTotal,
            latLng: LatLng(plat, plng),
            address: vicinity,
            types: types,
            photoUrl: photoUrl,
          );
        })
        .where((p) => p.latLng.latitude != 0.0 && p.rating != null)
        .toList();
  }

  Future<void> _fetchAndShow() async {
    if (_current == null) return;
    setState(() => _loading = true);

    try {
      // 1) Tập category đã chọn (có thể đến từ nhiều group)
      final selectedCats = <GmCat>[
        for (final entry in kGmCategoryGroups.entries)
          ...entry.value.where((c) => _selectedCatIds.contains(c.id)),
      ];

      // Nếu không chọn gì -> coi như chọn tất cả category
      final cats = selectedCats.isEmpty
          ? [for (final group in kGmCategoryGroups.values) ...group]
          : selectedCats;

      // 2) Chuẩn bị các lời gọi Nearby: giữ kèm catId để gán icon/nhãn
      final futures = <Future<MapEntry<String, List<PlaceItem>>>>[];
      for (final cat in cats) {
        for (final call in cat.apiCalls) {
          futures.add(() async {
            final list = await _nearby(
              type: call['type']!,
              radius: _radiusKm * 1000,
              keyword: call['keyword'],
            );
            return MapEntry(cat.id, list);
          }());
        }
      }

      // 3) Chạy tất cả và gộp theo place_id (union)
      final results = await Future.wait(futures);

      // all[placeId] -> (item, firstCatIdFound)
      final Map<String, (PlaceItem, String)> all = {};
      for (final entry in results) {
        final catId = entry.key;
        for (final p in entry.value) {
          all.putIfAbsent(p.placeId, () => (p, catId));
        }
      }

      // 4) Lọc theo rating/reviews/distance
      final origin = _current!;
      final filtered = <(PlaceItem, String)>[];
      for (final e in all.values) {
        final p = e.$1;
        final rOk = (p.rating ?? 0.0) >= _minRating;
        final vOk = (p.userRatingsTotal ?? 0) >= _minReviews;
        final dOk = _distanceMeters(origin, p.latLng) <= (_radiusKm * 1000);
        if (rOk && vOk && dOk) filtered.add(e);
      }

      // 5) Tính điểm & sort
      const m = 50.0, C = 4.2;
      final scored = filtered.map((e) {
        final p = e.$1;
        final catId = e.$2;
        final R = p.rating ?? 0.0;
        final v = (p.userRatingsTotal ?? 0).toDouble();
        final weighted = (v / (v + m)) * R + (m / (v + m)) * C;
        return (ScoredPlace(p, weighted), catId);
      }).toList();

      scored.sort((a, b) {
        final c = b.$1.score.compareTo(a.$1.score);
        if (c != 0) return c;
        final da = _distanceMeters(origin, a.$1.item.latLng);
        final db = _distanceMeters(origin, b.$1.item.latLng);
        return da.compareTo(db);
      });

      final top = scored; // tăng nhẹ để đa dạng category

      // 6) Vẽ marker:
      // - Nếu đã có icon cho category -> dùng icon riêng (giống Google Maps)
      // - Nếu chưa có -> fallback dùng màu theo group
      final newMarkers = <Marker>{};
      if (_searchMarker != null) newMarkers.add(_searchMarker!);

      for (int i = 0; i < top.length; i++) {
        final sp = top[i].$1;
        final catId = top[i].$2;
        final p = sp.item;

        // icon theo category (nếu có), fallback dùng màu theo group
        final group = _groupOfCat(catId);
        final hue = _groupHue[group] ?? BitmapDescriptor.hueRed;
        final BitmapDescriptor iconForCat = (_catIcons[catId] != null)
            ? _catIcons[catId]!
            : BitmapDescriptor.defaultMarkerWithHue(hue);

        newMarkers.add(
          Marker(
            markerId: MarkerId('${p.placeId}::$catId'),
            position: p.latLng,
            consumeTapEvents: true,
            onTap: () => _onMarkerTapped(p),
            icon: iconForCat,
          ),
        );
      }

      setState(() {
        _top = top.map((e) => e.$1).toList();
        _markers = newMarkers;
      });

      if (mounted) {
        final catCount = cats.length;
        final total = top.length;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã áp dụng $catCount category • $total kết quả'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Không tải được địa điểm: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openNavigation(LatLng to, String name) async {
    final google = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${to.latitude},${to.longitude}&travelmode=walking',
    );
    final apple = Uri.parse(
      'http://maps.apple.com/?daddr=${to.latitude},${to.longitude}&dirflg=w',
    );
    if (await canLaunchUrl(google)) {
      await launchUrl(google, mode: LaunchMode.externalApplication);
    } else if (await canLaunchUrl(apple)) {
      await launchUrl(apple, mode: LaunchMode.externalApplication);
    } else {
      final geo = Uri.parse(
        'geo:${to.latitude},${to.longitude}?q=${Uri.encodeComponent(name)}',
      );
      await launchUrl(geo, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _onMarkerTapped(PlaceItem p) async {
    final ctrl = await _mapCtrl.future;
    final screen = await ctrl.getScreenCoordinate(p.latLng);
    final ratio = MediaQuery.of(context).devicePixelRatio;
    setState(() {
      _selectedPlace = p;
      _infoWindowOffset = Offset(screen.x / ratio, screen.y / ratio);
    });
  }

  Future<void> _updateInfoWindow() async {
    if (_selectedPlace == null) return;
    final ctrl = await _mapCtrl.future;
    final screen = await ctrl.getScreenCoordinate(_selectedPlace!.latLng);
    final ratio = MediaQuery.of(context).devicePixelRatio;
    setState(() {
      _infoWindowOffset = Offset(screen.x / ratio, screen.y / ratio);
    });
  }

  Widget _buildPlacePopup() {
    final p = _selectedPlace!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 260,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black26)],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (p.photoUrl != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    p.photoUrl!,
                    width: 70,
                    height: 70,
                    fit: BoxFit.cover,
                  ),
                )
              else
                Container(
                  width: 70,
                  height: 70,
                  color: Colors.grey.shade300,
                  child: const Icon(Icons.photo, color: Colors.white70),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.star, size: 14, color: Colors.amber),
                        const SizedBox(width: 2),
                        Text(
                          p.rating?.toStringAsFixed(1) ?? '—',
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '(${p.userRatingsTotal ?? 0})',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      p.address ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.directions),
                onPressed: () => _openNavigation(p.latLng, p.name),
              ),
            ],
          ),
        ),
        Transform.translate(
          offset: const Offset(0, -6),
          child: const Icon(
            Icons.arrow_drop_down,
            color: Colors.white,
            size: 32,
          ),
        ),
      ],
    );
  }

  // =================== FILTER SHEET (UI) ===================
  Future<void> _openFilterSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        double tmpRating = _minRating;
        int tmpReviews = _minReviews;
        int tmpRadius = _radiusKm;
        final Set<String> tmpSelectedCatIds = Set.of(_selectedCatIds);
        GmGroup tmpActive = _activeGroup;

        int? tmpPreset = _radiusOptions.contains(_radiusKm) ? _radiusKm : null;
        _radiusCustomCtl.text = (_radiusOptions.contains(_radiusKm))
            ? ''
            : _radiusKm.toString();

        Widget section({
          required String title,
          required Widget child,
          Widget? trailing,
        }) {
          final sc = Theme.of(context).colorScheme;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: sc.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sc.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    if (trailing != null) trailing,
                  ],
                ),
                const SizedBox(height: 12),
                child,
              ],
            ),
          );
        }

        Widget pill({
          required String label,
          required bool selected,
          IconData? icon,
          VoidCallback? onTap,
        }) {
          final sc = Theme.of(context).colorScheme;
          return InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? sc.primaryContainer : sc.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: sc.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: 18,
                      color: selected
                          ? sc.onPrimaryContainer
                          : sc.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: selected ? sc.onPrimaryContainer : sc.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return StatefulBuilder(
          builder: (context, setModal) {
            Widget radiusSection() {
              return section(
                title: 'Bán kính tìm kiếm',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _radiusOptions.map((km) {
                        return pill(
                          label: '<${km}km',
                          icon: Icons.near_me_outlined,
                          selected: tmpPreset == km,
                          onTap: () => setModal(() {
                            tmpPreset = km;
                            tmpRadius = km;
                            _radiusCustomCtl.clear();
                          }),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Checkbox(
                          value: tmpPreset == null,
                          onChanged: (v) => setModal(() {
                            tmpPreset = v == true
                                ? null
                                : (tmpPreset ?? _radiusOptions.first);
                          }),
                        ),
                        const Text('Tự nhập:'),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 110,
                          child: TextField(
                            controller: _radiusCustomCtl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              hintText: 'km',
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (v) => setModal(() {
                              tmpPreset = null;
                              final n = int.tryParse(v);
                              if (n != null && n > 0) {
                                tmpRadius = n;
                              }
                            }),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }

            Widget ratingSection() {
              return section(
                title: 'Số điểm sao',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _ratingOptions.map((v) {
                    final sel = tmpRating == v;
                    return pill(
                      label: v == 5.0 ? '⭐ 5' : '⭐ ≥ ${v.toStringAsFixed(1)}',
                      selected: sel,
                      onTap: () => setModal(() => tmpRating = v),
                    );
                  }).toList(),
                ),
              );
            }

            Widget reviewsSection() {
              return section(
                title: 'Số lượt đánh giá',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _reviewsOptions.map((v) {
                    final sel = tmpReviews == v;
                    return pill(
                      label: '≥$v',
                      selected: sel,
                      onTap: () => setModal(() => tmpReviews = v),
                    );
                  }).toList(),
                ),
              );
            }

            Widget gmCatsSection() {
              final tabs = const [
                Tab(text: 'Food & Drink'),
                Tab(text: 'Things to do'),
                Tab(text: 'Shopping'),
                Tab(text: 'Services'),
              ];
              return section(
                title: 'Categories',
                child: DefaultTabController(
                  length: 4,
                  initialIndex: tmpActive.index,
                  child: Column(
                    children: [
                      TabBar(
                        isScrollable: true,
                        tabs: tabs,
                        onTap: (i) {
                          setModal(() => tmpActive = GmGroup.values[i]);
                        },
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: kGmCategoryGroups[tmpActive]!.map((c) {
                            final sel = tmpSelectedCatIds.contains(c.id);
                            return pill(
                              label: c.label,
                              icon: c.icon,
                              selected: sel,
                              onTap: () => setModal(() {
                                if (sel) {
                                  tmpSelectedCatIds.remove(c.id);
                                } else {
                                  tmpSelectedCatIds.add(c.id);
                                }
                              }),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Row(
                        children: [
                          const Text(
                            'Bộ lọc',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _minRating = 4.0;
                                _minReviews = 1000;
                                _radiusKm = 10;
                                _activeGroup = GmGroup.foodDrink;
                                _selectedCatIds
                                  ..clear()
                                  ..add('restaurants');
                              });
                              _renderSearchMarkerAndCircle();
                              Navigator.pop(context);
                              _fetchAndShow();
                            },
                            child: const Text('Đặt lại'),
                          ),
                        ],
                      ),
                      radiusSection(),
                      ratingSection(),
                      reviewsSection(),
                      gmCatsSection(),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Hủy'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                setState(() {
                                  _minRating = tmpRating;
                                  _minReviews = tmpReviews;
                                  _radiusKm = tmpRadius;
                                  _activeGroup = tmpActive;
                                  _selectedCatIds
                                    ..clear()
                                    ..addAll(tmpSelectedCatIds);
                                });
                                _renderSearchMarkerAndCircle();
                                Navigator.pop(context);
                                _fetchAndShow();
                              },
                              child: const Text('Áp dụng bộ lọc'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // =================== BUILD ===================
  @override
  Widget build(BuildContext context) {
    final cameraTarget = _current ?? _initSaigon;
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: cameraTarget,
              zoom: 13,
            ),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            markers: _markers,
            circles: _circles,
            onMapCreated: (c) => _mapCtrl.complete(c),
            onTap: (_) => setState(() => _selectedPlace = null),
            onCameraMove: (_) => _updateInfoWindow(),
          ),

          // Search box
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 12,
            right: 12,
            child: Column(
              children: [
                Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(12),
                  child: TextField(
                    focusNode: _searchFocus,
                    controller: _searchCtl,
                    decoration: InputDecoration(
                      hintText: 'Nhập địa điểm (vd: Tokyo, Japan)',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_searchCtl.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchCtl.clear();
                                setState(() => _suggests = []);
                              },
                            ),
                          Padding(
                            padding: const EdgeInsets.only(
                              right: 4,
                              top: 4,
                              bottom: 4,
                            ),
                            child: _buildAccountButton(),
                          ),
                        ],
                      ),
                      suffixIconConstraints:
                          const BoxConstraints(minWidth: 0, minHeight: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
                if (_suggests.isNotEmpty || _searching)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(blurRadius: 8, color: Colors.black12),
                      ],
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
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
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

          if (_selectedPlace != null && _infoWindowOffset != null)
            Positioned(
              left: _infoWindowOffset!.dx - 130,
              top: _infoWindowOffset!.dy - 120,
              child: _buildPlacePopup(),
            ),

          // Bottom small list top 5
          if (_top.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: SizedBox(
                height: 120,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  scrollDirection: Axis.horizontal,
                  itemCount: _top.length,
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
                        await _onMarkerTapped(p);
                      },
                      child: Container(
                        width: 240,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(blurRadius: 8, color: Colors.black12),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${i + 1}. ${p.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '⭐ ${p.rating?.toStringAsFixed(1) ?? "—"}   ·   ${p.userRatingsTotal ?? 0} reviews',
                              style: const TextStyle(fontSize: 12),
                            ),
                            const Spacer(),
                            Text(
                              p.address ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

          Positioned(
            right: 16,
            bottom: (_top.isNotEmpty ? 140 : 16) + 64,
            child: RawMaterialButton(
              onPressed: _openFilterSheet,
              elevation: 4.0,
              fillColor: Colors.white,
              shape: const CircleBorder(),
              constraints: const BoxConstraints.tightFor(
                width: 48,
                height: 48,
              ),
              child: const Icon(Icons.filter_list, color: Colors.black87),
            ),
          ),
          Positioned(
            right: 16,
            bottom: _top.isNotEmpty ? 140 : 16,
            child: RawMaterialButton(
              onPressed: _ensurePermissionAndLocate,
              elevation: 4.0,
              fillColor: Colors.white,
              shape: const CircleBorder(),
              constraints: const BoxConstraints.tightFor(
                width: 48,
                height: 48,
              ),
              child: const Icon(Icons.my_location, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountButton() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return IconButton(
        icon: const Icon(Icons.login),
        tooltip: 'Đăng nhập',
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          ).then((_) => setState(() {}));
        },
      );
    }
    return PopupMenuButton<String>(
      onSelected: (value) async {
        if (value == 'logout') {
          await FirebaseAuth.instance.signOut();
          await GoogleSignIn().signOut();
          setState(() {});
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'logout', child: Text('Đăng xuất')),
      ],
      child: CircleAvatar(
        backgroundImage:
            user.photoURL != null ? NetworkImage(user.photoURL!) : null,
        child: user.photoURL == null ? const Icon(Icons.person) : null,
      ),
    );
  }
}
