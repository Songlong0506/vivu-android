import "package:flutter/material.dart";
enum GmGroup { foodDrink, thingsToDo, shopping, services }

class GmCat {
  final String id;
  final String label;
  final IconData icon;
  /// Mỗi item ánh xạ thành 1 hoặc nhiều call Nearby: {type, keyword?}
  final List<Map<String, String?>> apiCalls;
  const GmCat({
    required this.id,
    required this.label,
    required this.icon,
    required this.apiCalls,
  });
}

final Map<GmGroup, List<GmCat>> kGmCategoryGroups = {
  GmGroup.foodDrink: [
    GmCat(
      id: 'restaurants',
      label: 'Restaurants',
      icon: Icons.restaurant,
      apiCalls: [
        {'type': 'restaurant', 'keyword': null},
      ],
    ),
    GmCat(
      id: 'bars',
      label: 'Bars',
      icon: Icons.local_bar_outlined,
      apiCalls: [
        {'type': 'bar', 'keyword': null},
      ],
    ),
    GmCat(
      id: 'coffee',
      label: 'Coffee',
      icon: Icons.local_cafe_outlined,
      apiCalls: [
        {'type': 'cafe', 'keyword': null},
      ],
    ),
    GmCat(
      id: 'takeout',
      label: 'Takeout',
      icon: Icons.shopping_bag_outlined,
      apiCalls: [
        {'type': 'restaurant', 'keyword': 'takeout'},
        {'type': 'meal_takeaway', 'keyword': null},
      ],
    ),
    GmCat(
      id: 'delivery',
      label: 'Delivery',
      icon: Icons.delivery_dining_outlined,
      apiCalls: [
        {'type': 'restaurant', 'keyword': 'delivery'},
        {'type': 'meal_delivery', 'keyword': null},
      ],
    ),
  ],
  GmGroup.thingsToDo: [
    GmCat(
      id: 'parks',
      label: 'Parks',
      icon: Icons.park_outlined,
      apiCalls: [
        {'type': 'park', 'keyword': null},
      ],
    ),
    GmCat(
      id: 'gyms',
      label: 'Gyms',
      icon: Icons.fitness_center_outlined,
      apiCalls: [
        {'type': 'gym', 'keyword': null},
      ],
    ),
    GmCat(
      id: 'art',
      label: 'Art',
      icon: Icons.brush_outlined,
      apiCalls: [
        {'type': 'art_gallery', 'keyword': null},
      ],
    ),
    GmCat(
      id: 'attractions',
      label: 'Attractions',
      icon: Icons.attractions, // nếu thiếu icon này dùng Icons.place_outlined
      apiCalls: [
        {'type': 'tourist_attraction', 'keyword': null},
      ],
    ),
    GmCat(
      id: 'nightlife',
      label: 'Nightlife',
      icon: Icons.nightlife_outlined,
      apiCalls: [
        {'type': 'night_club', 'keyword': null},
        {'type': 'bar', 'keyword': 'nightlife'},
      ],
    ),
    GmCat(
      id: 'live_music',
      label: 'Live music',
      icon: Icons.music_note_outlined,
      apiCalls: [
        {'type': 'bar', 'keyword': 'live music'},
        {'type': 'night_club', 'keyword': 'live music'},
      ],
    ),
    GmCat(
      id: 'movies',
      label: 'Movies',
      icon: Icons.movie_outlined,
      apiCalls: [
        {'type': 'movie_theater', 'keyword': null},
      ],
    ),
    GmCat(
      id: 'museums',
      label: 'Museums',
      icon: Icons.museum_outlined,
      apiCalls: [
        {'type': 'museum', 'keyword': null},
      ],
    ),
    GmCat(
      id: 'libraries',
      label: 'Libraries',
      icon: Icons.local_library_outlined,
      apiCalls: [
        {'type': 'library', 'keyword': null},
      ],
    ),
  ],
  GmGroup.shopping: [
    GmCat(
      id: 'groceries',
      label: 'Groceries',
      icon: Icons.shopping_cart_outlined,
      apiCalls: [
        {'type': 'supermarket', 'keyword': null},
        {'type': 'grocery_or_supermarket', 'keyword': null},
      ],
    ),
    GmCat(
      id: 'beauty',
      label: 'Beauty supplies',
      icon: Icons.brush_outlined,
      apiCalls: [
        {'type': 'beauty_salon', 'keyword': 'beauty supplies'},
        {'type': 'store', 'keyword': 'beauty supplies'},
      ],
    ),
    GmCat(
      id: 'car_dealers',
      label: 'Car dealers',
      icon: Icons.directions_car_filled_outlined,
      apiCalls: [
        {'type': 'car_dealer', 'keyword': null},
      ],
    ),
    GmCat(
      id: 'home_garden',
      label: 'Home & garden',
      icon: Icons.chair_outlined,
      apiCalls: [
        {'type': 'home_goods_store', 'keyword': null},
      ],
    ),
    GmCat(
      id: 'shopping_centers',
      label: 'Shopping centers',
      icon: Icons.store_mall_directory_outlined,
      apiCalls: [
        {'type': 'shopping_mall', 'keyword': null},
      ],
    ),
    GmCat(
      id: 'electronics',
      label: 'Electronics',
      icon: Icons.devices_other_outlined,
      apiCalls: [
        {'type': 'electronics_store', 'keyword': null},
      ],
    ),
    GmCat(
      id: 'sporting_goods',
      label: 'Sporting goods',
      icon: Icons.sports_basketball_outlined,
      apiCalls: [
        {'type': 'store', 'keyword': 'sporting goods'},
      ],
    ),
    GmCat(
      id: 'convenience',
      label: 'Convenience stores',
      icon: Icons.local_convenience_store_outlined,
      apiCalls: [
        {'type': 'convenience_store', 'keyword': null},
      ],
    ),
    GmCat(
      id: 'apparel',
      label: 'Apparel',
      icon: Icons.checkroom_outlined,
      apiCalls: [
        {'type': 'clothing_store', 'keyword': null},
      ],
    ),
  ],
  GmGroup.services: [
    GmCat(
      id: 'hotels',
      label: 'Hotels',
      icon: Icons.hotel_outlined,
      apiCalls: [
        {'type': 'lodging', 'keyword': null},
      ],
    ),
    GmCat(
      id: 'gas',
      label: 'Gas',
      icon: Icons.local_gas_station_outlined,
      apiCalls: [
        {'type': 'gas_station', 'keyword': null},
      ],
    ),
    GmCat(
      id: 'atms',
      label: 'ATMs',
      icon: Icons.atm_outlined,
      apiCalls: [
        {'type': 'atm', 'keyword': null},
      ],
    ),
    GmCat(
      id: 'hospitals',
      label: 'Hospitals & clinics',
      icon: Icons.local_hospital_outlined,
      apiCalls: [
        {'type': 'hospital', 'keyword': null},
        {'type': 'doctor', 'keyword': null},
      ],
    ),
    GmCat(
      id: 'mail_shipping',
      label: 'Mail & shipping',
      icon: Icons.local_post_office_outlined,
      apiCalls: [
        {'type': 'post_office', 'keyword': null},
      ],
    ),
    GmCat(
      id: 'parking',
      label: 'Parking',
      icon: Icons.local_parking_outlined,
      apiCalls: [
        {'type': 'parking', 'keyword': null},
      ],
    ),
    GmCat(
      id: 'pharmacies',
      label: 'Pharmacies',
      icon: Icons.local_pharmacy_outlined,
      apiCalls: [
        {'type': 'pharmacy', 'keyword': null},
      ],
    ),
    GmCat(
      id: 'beauty_salon',
      label: 'Beauty salons',
      icon: Icons.face_3_outlined,
      apiCalls: [
        {'type': 'beauty_salon', 'keyword': null},
      ],
    ),
    GmCat(
      id: 'car_rental',
      label: 'Car rental',
      icon: Icons.car_rental_outlined,
      apiCalls: [
        {'type': 'car_rental', 'keyword': null},
      ],
    ),
    GmCat(
      id: 'car_wash',
      label: 'Car wash',
      icon: Icons.local_car_wash_outlined,
      apiCalls: [
        {'type': 'car_wash', 'keyword': null},
      ],
    ),
    GmCat(
      id: 'dry_cleaning',
      label: 'Dry cleaning',
      icon: Icons.local_laundry_service_outlined,
      apiCalls: [
        {'type': 'laundry', 'keyword': 'dry cleaning'},
      ],
    ),
    GmCat(
      id: 'charging',
      label: 'Charging stations',
      icon: Icons.electric_bolt_outlined,
      apiCalls: [
        {'type': 'charging_station', 'keyword': null},
      ],
    ),
  ],
};

