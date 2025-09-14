import 'package:flutter/material.dart';

import '../models/place_item.dart';
import '../models/place_list.dart';

class EditListScreen extends StatefulWidget {
  final PlaceList? list;
  final PlaceItem? initialPlace;

  const EditListScreen({super.key, this.list, this.initialPlace});

  @override
  State<EditListScreen> createState() => _EditListScreenState();
}

class _EditListScreenState extends State<EditListScreen> {
  final nameCtl = TextEditingController();
  final descCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.list != null) {
      nameCtl.text = widget.list!.name;
      descCtl.text = widget.list!.description ?? '';
    }
  }

  @override
  void dispose() {
    nameCtl.dispose();
    descCtl.dispose();
    super.dispose();
  }

  void _save() {
    final name = nameCtl.text.trim();
    if (name.isEmpty) return;
    final service = ListService.instance;
    if (widget.list == null) {
      final newList = PlaceList(name: name, description: descCtl.text.trim());
      if (widget.initialPlace != null) {
        newList.places.add(widget.initialPlace!);
      }
      service.addList(newList);
    } else {
      widget.list!..name = name..description = descCtl.text.trim();
      service.updateList(widget.list!);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.list == null ? 'New list' : 'Edit list'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: nameCtl,
              decoration: const InputDecoration(labelText: 'List name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtl,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
          ],
        ),
      ),
    );
  }
}
