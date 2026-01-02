import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Define sharedPreferencesProvider ONLY here
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Will be overridden in main.dart');
});