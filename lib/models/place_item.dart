import 'package:google_maps_flutter/google_maps_flutter.dart';

class PlaceItem {
  final String placeId;
  final String name;
  final double? rating;
  final int? userRatingsTotal;
  final LatLng latLng;
  final String? address;
  final String? types;

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
