import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:minicrm/objectbox.g.dart';
import 'package:objectbox/objectbox.dart' as obx;
import 'package:path_provider/path_provider.dart';

class ObjectBoxStore {
  ObjectBoxStore._(this.store);

  final Store store;

  static String directoryFor(String docsPath) => '$docsPath/objectbox';

  /// Open a Store from a given docs directory. Safe to call from any
  /// isolate, and from the same isolate across hot restarts: if a Store
  /// is already open at this path (e.g. because the worker isolate is
  /// still alive after a UI hot restart, or because two isolates share
  /// the same db), we [obx.Store.attach] to it instead of opening a new
  /// one — which would otherwise throw `OBX_ERROR 10001`.
  static Future<Store> openAt(String docsPath) async {
    final dir = directoryFor(docsPath);
    if (Store.isOpen(dir)) {
      return obx.Store.attach(getObjectBoxModel(), dir);
    }
    return openStore(directory: dir);
  }

  static Future<ObjectBoxStore> create() async {
    final docs = await getApplicationDocumentsDirectory();
    final store = await openAt(docs.path);
    return ObjectBoxStore._(store);
  }

  void close() => store.close();
}

final objectBoxStoreProvider = FutureProvider<ObjectBoxStore>((ref) async {
  final box = await ObjectBoxStore.create();
  ref.onDispose(box.close);
  return box;
});
