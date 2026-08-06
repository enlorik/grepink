import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'database_initializer_stub.dart'
    if (dart.library.io) 'database_initializer_io.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDatabase();
  runApp(
    const ProviderScope(
      child: GrepinkApp(),
    ),
  );
}
