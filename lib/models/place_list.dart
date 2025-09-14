import 'place_item.dart';

class PlaceList {
  final String id;
  String name;
  String? description;
  final List<PlaceItem> places;

  PlaceList({
    String? id,
    required this.name,
    this.description,
    List<PlaceItem>? places,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        places = places ?? [];
}

class ListService {
  static final ListService instance = ListService._();
  ListService._() {
    lists = [PlaceList(id: 'favorites', name: 'Favorites')];
  }

  late List<PlaceList> lists;

  void addList(PlaceList list) {
    lists.add(list);
  }

  void updateList(PlaceList list) {
    final i = lists.indexWhere((l) => l.id == list.id);
    if (i != -1) {
      lists[i] = list;
    }
  }

  void deleteList(String id) {
    lists.removeWhere((l) => l.id == id);
  }

  void addPlace(String listId, PlaceItem p) {
    final list = lists.firstWhere((l) => l.id == listId);
    if (!list.places.any((e) => e.placeId == p.placeId)) {
      list.places.add(p);
    }
  }
}
