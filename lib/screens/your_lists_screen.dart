import 'package:flutter/material.dart';

import '../models/place_list.dart';
import 'edit_list_screen.dart';

class YourListsScreen extends StatefulWidget {
  const YourListsScreen({super.key});

  @override
  State<YourListsScreen> createState() => _YourListsScreenState();
}

class _YourListsScreenState extends State<YourListsScreen> {
  final service = ListService.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your lists'),
      ),
      body: ListView.builder(
        itemCount: service.lists.length,
        itemBuilder: (context, index) {
          final list = service.lists[index];
          return ListTile(
            leading: Icon(list.id == 'favorites' ? Icons.favorite : Icons.list),
            title: Text(list.name),
            subtitle: Text('${list.places.length} places'),
            trailing: PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'edit') {
                  await Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => EditListScreen(list: list)));
                  setState(() {});
                } else if (v == 'delete') {
                  setState(() => service.deleteList(list.id));
                }
              },
              itemBuilder: (context) {
                return [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  if (list.id != 'favorites')
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ];
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const EditListScreen()));
          setState(() {});
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
