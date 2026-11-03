import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseSnapshotService {
  bool initialized = false;

  Future<void> initialize({
    required String url,
    required String publishableKey,
  }) async {
    await Supabase.initialize(url: url, publishableKey: publishableKey);
    initialized = true;
  }

  Future<Map<String, dynamic>?> load() async {
    if (!initialized) return null;
    final response = await Supabase.instance.client
        .from('app_data')
        .select('content')
        .eq('id', 'main_state')
        .maybeSingle();
    final content = response?['content'];
    if (content is! Map) return null;
    return content.map((key, value) => MapEntry(key.toString(), value));
  }

  Future<void> save(Map<String, dynamic> state) async {
    if (!initialized) return;
    final snapshot = jsonDecode(jsonEncode(state)) as Map<String, dynamic>;
    snapshot['session'] = null;
    await Supabase.instance.client.from('app_data').upsert(<String, dynamic>{
      'id': 'main_state',
      'content': snapshot,
    });
  }

  void logError(String message, Object error) {
    debugPrint('$message: $error');
  }
}
