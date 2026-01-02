import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Import the shared provider
import 'shared_prefs_provider.dart';

// Simple role state provider (in-memory)
final selectedRoleProvider = StateProvider<String?>((ref) => null);

// Role service provider
final roleServiceProvider = Provider<RoleService>((ref) {
  final prefs = ref.read(sharedPreferencesProvider);
  return RoleService(prefs);
});

// Role service class
class RoleService {
  final SharedPreferences _prefs;

  RoleService(this._prefs);

  Future<void> saveRole(String role) async {
    await _prefs.setString('user_role', role);
  }

  Future<String?> getSavedRole() async {
    return _prefs.getString('user_role');
  }

  Future<void> clearRole() async {
    await _prefs.remove('user_role');
  }
}