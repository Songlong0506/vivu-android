class AutocompletePrediction {
  final String description;
  final String placeId;

  AutocompletePrediction({required this.description, required this.placeId});

  static List<AutocompletePrediction> fromJsonList(List list) {
    return list
        .map((e) => AutocompletePrediction(
              description: e['description'] as String? ?? '',
              placeId: e['place_id'] as String? ?? '',
            ))
        .toList();
  }
}
