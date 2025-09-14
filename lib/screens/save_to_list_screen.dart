import 'package:flutter/material.dart';

import '../models/place_item.dart';
import '../models/place_list.dart';
import 'edit_list_screen.dart';

class SaveToListScreen extends StatefulWidget {
  final PlaceItem place;
  const SaveToListScreen({super.key, required this.place});

  @override
  State<SaveToListScreen> createState() => _SaveToListScreenState();
}

class _SaveToListScreenState extends State<SaveToListScreen> {
  final service = ListService.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Save to list'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          )
        ],
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('New list'),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EditListScreen(initialPlace: widget.place),
                ),
              );
              setState(() {});
            },
          ),
          for (final list in service.lists)
            CheckboxListTile(
              title: Text(list.name),
              subtitle: Text('${list.places.length} places'),
              value:
                  list.places.any((p) => p.placeId == widget.place.placeId),
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    service.addPlace(list.id, widget.place);
                  } else {
                    list.places
                        .removeWhere((p) => p.placeId == widget.place.placeId);
                  }
                });
              },
            ),
        ],
      ),
    );
  }
}
