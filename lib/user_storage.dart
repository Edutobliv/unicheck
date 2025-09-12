import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class UserStorage {
  static Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/users.json');
  }

  static Future<List<Map<String, dynamic>>> _readUsers() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final data = jsonDecode(content) as List;
      return data.map((e) => (e as Map).cast<String, dynamic>()).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveUser(Map<String, dynamic> user) async {
    final users = await _readUsers();
    users.removeWhere((u) => u['email'] == user['email']);
    users.add(user);
    final file = await _getFile();
    await file.writeAsString(jsonEncode(users));
  }

  static Future<Map<String, dynamic>?> findUser(String email) async {
    final users = await _readUsers();
    for (final u in users) {
      if (u['email'] == email) return u;
    }
    return null;
  }
}
