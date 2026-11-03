import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/institute_location_service.dart';
import '../services/native_notifications_service.dart';
import '../services/supabase_snapshot_service.dart';

const _storeKey = 'jsk_attendance_v37';
const _supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://xzjwslwvgqxcvqslllfq.supabase.co',
);
const _supabaseKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'sb_publishable_Pqc-XDW9Vb4lluagQ-AhUQ_IiqoOD_J',
);

extension FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class AppStore extends ChangeNotifier {
  Map<String, dynamic> _data = <String, dynamic>{};
  SharedPreferences? _prefs;
  final SupabaseSnapshotService _cloud = SupabaseSnapshotService();
  final InstituteLocationService _location = InstituteLocationService();
  bool loading = true;
  bool cloudEnabled = false;
  bool syncing = false;
  String? cloudMessage;
  Timer? _saveTimer;

  Map<String, dynamic> get data => _data;
  Map<String, dynamic> get ui => _data['ui'] as Map<String, dynamic>;
  Map<String, dynamic>? get currentUser {
    final id = (_data['session'] as Map?)?['userId'];
    if (id == null) return null;
    for (final user in rows('users')) {
      if (user['id'] == id && user['ghost'] != true) return user;
    }
    return null;
  }

  bool get isDark => ui['theme'] == 'dark';
  bool get onlineSyncConfigured => cloudEnabled;

  List<Map<String, dynamic>> rows(String key) {
    final value = _data[key];
    if (value is List<Map<String, dynamic>>) return value;
    final converted = _rows(value);
    _data[key] = converted;
    return converted;
  }

  static Map<String, dynamic> _map(dynamic value) {
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  static List<Map<String, dynamic>> _rows(dynamic value) {
    if (value is! List) return <Map<String, dynamic>>[];
    return value.whereType<Map>().map((row) => _map(row)).toList();
  }

  static String _id(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${math.Random().nextInt(9999)}';
  static String today() {
    final d = DateTime.now();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> initialize() async {
    NativeNotificationsService.onNotificationOpened(
      () => navigate('notifications'),
    );
    _prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> local = <String, dynamic>{};
    try {
      final encoded = _prefs?.getString(_storeKey);
      if (encoded != null) local = _map(jsonDecode(encoded));
    } catch (_) {
      local = <String, dynamic>{};
    }
    _data = _normalize(local);

    if (_supabaseUrl.isNotEmpty && _supabaseKey.isNotEmpty) {
      try {
        await _cloud.initialize(
          url: _supabaseUrl,
          publishableKey: _supabaseKey,
        );
        cloudEnabled = true;
        final remote = _map(await _cloud.load());
        if (remote.isNotEmpty && remote['users'] is List) {
          final session = _map(local['session']);
          _data = _mergeSnapshots(_normalize(remote), _normalize(local));
          final userExists = rows('users').any(
            (user) => user['id'] == session['userId'] && user['ghost'] != true,
          );
          _data['session'] = userExists ? session : null;
          cloudMessage = 'Cloud data connected';
        } else if (remote.isEmpty && rows('users').isEmpty) {
          cloudMessage = 'Connected; waiting for institute data';
        }
      } catch (error) {
        cloudEnabled = false;
        cloudMessage =
            'Offline mode — changes will stay on this device until sync is configured.';
        _cloud.logError('Cloud sync unavailable', error);
      }
    } else {
      cloudMessage =
          'Offline mode — add SUPABASE_URL and SUPABASE_ANON_KEY to sync accounts and data.';
    }

    _data = _normalize(_data);
    final savedUser = currentUser;
    if (savedUser?['id'] != null) {
      NativeNotificationsService.signIn(savedUser!['id'].toString());
    }
    await _writeLocal();
    loading = false;
    notifyListeners();
  }

  Map<String, dynamic> _normalize(Map<String, dynamic> source) {
    final normalized = Map<String, dynamic>.from(source);
    for (final key in <String>[
      'users',
      'students',
      'batches',
      'subjects',
      'assignments',
      'attendance',
      'announcements',
      'notifications',
      'inbox',
      'feePayments',
      'feePlans',
      'feeClearances',
      'feeReminders',
      'schedules',
      'staffRecords',
      'staffNotifications',
      'lateRemarks',
      'hourAdjustments',
      'leaveRequests',
      'holidays',
    ]) {
      normalized[key] = _rows(source[key]);
    }
    normalized['settings'] = _map(source['settings']);
    normalized['ui'] = <String, dynamic>{
      'theme': 'dark',
      'page': null,
      'teacherBatch': null,
      'teacherSubject': null,
      'teacherDate': today(),
      'themeColor': 'violet',
      'textSize': 'default',
      'uiStyle': 'rounded',
      'language': 'en',
      'settingsSub': null,
      ..._map(source['ui']),
    };
    if (!normalized.containsKey('session')) normalized['session'] = null;
    return normalized;
  }

  Map<String, dynamic> _mergeSnapshots(
    Map<String, dynamic> remote,
    Map<String, dynamic> local,
  ) {
    final merged = Map<String, dynamic>.from(remote);
    for (final key in <String>[
      'users',
      'students',
      'batches',
      'subjects',
      'assignments',
      'schedules',
      'staffRecords',
      'staffNotifications',
      'lateRemarks',
      'inbox',
      'attendance',
      'feePayments',
      'announcements',
      'leaveRequests',
    ]) {
      final byId = <String, Map<String, dynamic>>{};
      for (final row in _rows(remote[key])) {
        final id = row['id']?.toString();
        if (id != null) byId[id] = row;
      }
      for (final row in _rows(local[key])) {
        final id = row['id']?.toString();
        if (id != null) byId[id] = row;
      }
      merged[key] = byId.values.toList();
    }
    merged['session'] = local['session'];
    merged['ui'] = <String, dynamic>{
      ..._map(remote['ui']),
      ..._map(local['ui']),
    };
    return _normalize(merged);
  }

  Future<void> _writeLocal() async {
    try {
      await _prefs?.setString(_storeKey, jsonEncode(_data));
    } catch (error) {
      debugPrint('Local save failed: $error');
    }
  }

  void save() {
    notifyListeners();
    unawaited(_writeLocal());
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 450),
      () => unawaited(_syncCloud()),
    );
  }

  Future<void> _syncCloud() async {
    if (!cloudEnabled || syncing) return;
    syncing = true;
    notifyListeners();
    try {
      final remote = _map(await _cloud.load());
      if (remote.isNotEmpty) _data = _mergeSnapshots(_normalize(remote), _data);
      await _writeLocal();
      await _cloud.save(_data);
      cloudMessage = 'Synced';
    } catch (error) {
      cloudMessage =
          'Saved on this device; cloud sync will retry after your next change.';
      _cloud.logError('Cloud save failed', error);
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> refreshCloud() async {
    if (!cloudEnabled || syncing) return;
    syncing = true;
    notifyListeners();
    try {
      final remote = _map(await _cloud.load());
      if (remote.isNotEmpty) _data = _mergeSnapshots(_normalize(remote), _data);
      await _writeLocal();
      cloudMessage = 'Synced';
    } catch (_) {
      cloudMessage = 'Could not refresh cloud data';
    }
    syncing = false;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    final normalizedEmail = email.trim().toLowerCase();
    final user = rows('users')
        .where(
          (row) =>
              (row['email'] ?? '').toString().toLowerCase() ==
                  normalizedEmail &&
              row['password']?.toString() == password &&
              row['ghost'] != true,
        )
        .firstOrNull;
    if (user == null) return false;
    _data['session'] = <String, dynamic>{'userId': user['id']};
    NativeNotificationsService.signIn(user['id'].toString());
    final role = user['role']?.toString();
    ui['page'] = switch (role) {
      'admin' => 'notices',
      'teacher' || 'staff' => 'attendance',
      _ => 'home',
    };
    await _writeLocal();
    notifyListeners();
    return true;
  }

  Future<void> logout() async {
    _data['session'] = null;
    NativeNotificationsService.signOut();
    ui['page'] = null;
    await _writeLocal();
    notifyListeners();
  }

  void navigate(String page) {
    ui['page'] = page;
    save();
  }

  void setDark(bool dark) {
    ui['theme'] = dark ? 'dark' : 'light';
    save();
  }

  Future<void> setPushEnabled(bool enabled) async {
    final user = currentUser;
    if (user == null) return;
    if (enabled) {
      await requestPushPermission();
    } else {
      user['phoneNotifs'] = false;
      NativeNotificationsService.optOut();
      save();
    }
  }

  Future<void> requestPushPermission() async {
    final user = currentUser;
    if (user == null) return;
    try {
      final accepted = await NativeNotificationsService.requestPermission();
      user['phoneNotifs'] = accepted;
      if (accepted) {
        NativeNotificationsService.optIn();
      } else {
        NativeNotificationsService.optOut();
      }
      save();
    } catch (error) {
      _cloud.logError('Push permission request failed', error);
    }
  }

  List<Map<String, dynamic>> studentsForUser(Map<String, dynamic> user) {
    final role = user['role'];
    if (role == 'admin' || role == 'teacher' || role == 'staff') {
      return rows('students');
    }
    return rows('students')
        .where(
          (student) =>
              student['userId'] == user['id'] ||
              student['guardianUserId'] == user['id'] ||
              _rows(
                student['additionalGuardians'],
              ).any((guardian) => guardian['userId'] == user['id']),
        )
        .toList();
  }

  void setAttendance({
    required String studentId,
    required String batchId,
    required String subjectId,
    required String date,
    required String status,
  }) {
    final student = rows(
      'students',
    ).where((row) => row['id'] == studentId).firstOrNull;
    if (student == null) return;
    final list = rows('attendance');
    final index = list.indexWhere(
      (row) =>
          row['studentId'] == studentId &&
          row['batchId'] == batchId &&
          row['subjectId'] == subjectId &&
          row['date'] == date,
    );
    final teacher = currentUser;
    final record = <String, dynamic>{
      'id': index >= 0 ? list[index]['id'] : _id('att'),
      'studentId': studentId,
      'batchId': batchId,
      'subjectId': subjectId,
      'date': date,
      'status': status,
      'teacherId': teacher?['id'],
      'teacherName': teacher?['name'],
      'ts': DateTime.now().millisecondsSinceEpoch,
    };
    if (index >= 0) {
      list[index] = record;
    } else {
      list.add(record);
    }
    for (final recipient in <String?>[
      student['userId']?.toString(),
      student['guardianUserId']?.toString(),
    ]) {
      if (recipient == null || recipient.isEmpty) continue;
      rows('inbox').add(<String, dynamic>{
        'id': _id('inbox'),
        'recipientUserId': recipient,
        'title': 'Attendance update',
        'message':
            '${student['name'] ?? 'Student'} was marked ${status.toUpperCase()} for ${_subjectName(subjectId)} on $date.',
        'type': 'ATTENDANCE_${status.toUpperCase()}',
        'refType': 'attendance',
        'refId': record['id'],
        'ts': DateTime.now().millisecondsSinceEpoch,
        'read': false,
      });
    }
    save();
  }

  String _subjectName(String subjectId) =>
      rows('subjects')
          .where((row) => row['id'] == subjectId)
          .firstOrNull?['name']
          ?.toString() ??
      'class';

  bool feePaid(String studentId, String month) => rows(
    'feePayments',
  ).any((row) => row['studentId'] == studentId && row['month'] == month);

  void setFeePaid(String studentId, String month, bool paid) {
    final payments = rows('feePayments');
    payments.removeWhere(
      (row) => row['studentId'] == studentId && row['month'] == month,
    );
    if (paid) {
      payments.add(<String, dynamic>{
        'id': _id('feepay'),
        'studentId': studentId,
        'month': month,
        'date': today(),
        'by': currentUser?['name'] ?? 'Office',
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
    }
    save();
  }

  void publishNotice({
    required String title,
    required String message,
    String audience = 'everyone',
  }) {
    final notice = <String, dynamic>{
      'id': _id('notice'),
      'title': title.trim(),
      'body': message.trim(),
      'message': message.trim(),
      'audience': audience,
      'published': true,
      'ts': DateTime.now().millisecondsSinceEpoch,
      'date': today(),
      'by': currentUser?['name'],
    };
    rows('announcements').insert(0, notice);
    final recipients = rows('users').where((user) {
      if (user['ghost'] == true || user['id'] == currentUser?['id']) {
        return false;
      }
      return audience == 'everyone' || user['role'] == audience;
    });
    for (final user in recipients) {
      rows('inbox').insert(0, <String, dynamic>{
        'id': _id('inbox'),
        'recipientUserId': user['id'],
        'title': title.trim(),
        'message': message.trim(),
        'type': 'NOTICE',
        'refType': 'announcement',
        'refId': notice['id'],
        'ts': notice['ts'],
        'read': false,
      });
    }
    save();
  }

  void markRead(String id) {
    final userId = currentUser?['id'];
    for (final item in rows('inbox')) {
      if (item['id'] == id && item['recipientUserId'] == userId) {
        item['read'] = true;
      }
    }
    save();
  }

  void markAllRead() {
    final userId = currentUser?['id'];
    for (final item in rows('inbox')) {
      if (item['recipientUserId'] == userId) item['read'] = true;
    }
    save();
  }

  void createSchedule({
    required String batchId,
    required String subjectId,
    required String date,
    required String topic,
    required String time,
    required String endTime,
    String room = '',
    String note = '',
  }) {
    rows('schedules').insert(0, <String, dynamic>{
      'id': _id('sch'),
      'batchId': batchId,
      'subjectId': subjectId,
      'teacherId': currentUser?['id'],
      'teacherName': currentUser?['name'],
      'kind': 'lecture',
      'topic': topic.trim(),
      'date': date,
      'time': time,
      'endTime': endTime,
      'room': room.trim(),
      'note': note,
      'status': 'scheduled',
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
    save();
  }

  void requestLeave({required String date, required String reason}) {
    rows('leaveRequests').insert(0, <String, dynamic>{
      'id': _id('leave'),
      'userId': currentUser?['id'],
      'name': currentUser?['name'],
      'role': currentUser?['role'],
      'date': date,
      'reason': reason,
      'status': 'pending',
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
    save();
  }

  void decideLeave(String id, String status) {
    final request = rows(
      'leaveRequests',
    ).where((row) => row['id'] == id).firstOrNull;
    if (request == null) return;
    request['status'] = status;
    request['decidedBy'] = currentUser?['name'];
    save();
  }

  void createPerson({
    required String name,
    required String email,
    required String password,
    required String role,
  }) {
    final userId = _id('user');
    rows('users').add(<String, dynamic>{
      'id': userId,
      'name': name.trim(),
      'email': email.trim(),
      'password': password,
      'role': role,
      'shiftTime': '09:00',
      'shiftEnd': '17:30',
    });
    if (role == 'student') {
      rows('students').add(<String, dynamic>{
        'id': _id('stu'),
        'userId': userId,
        'name': name.trim(),
        'email': email.trim(),
        'course': '',
        'standard': '',
        'batchId': '',
        'guardianName': '',
        'guardianContact': '',
      });
    }
    save();
  }

  void setTeacherAssignments(String teacherId, Set<String> assignmentKeys) {
    final assignments = rows('assignments')
      ..removeWhere((assignment) => assignment['teacherId'] == teacherId);
    for (final key in assignmentKeys) {
      final separator = key.indexOf('|');
      if (separator <= 0) continue;
      assignments.add(<String, dynamic>{
        'id': _id('asg'),
        'teacherId': teacherId,
        'batchId': key.substring(0, separator),
        'subjectId': key.substring(separator + 1),
      });
    }
    _data['assignments'] = assignments;
    save();
  }

  void createBatch(String name) {
    if (name.trim().isEmpty) return;
    rows(
      'batches',
    ).add(<String, dynamic>{'id': _id('batch'), 'name': name.trim()});
    save();
  }

  Future<String?> staffCheck({required bool checkOut}) async {
    final user = currentUser;
    if (user == null) return 'Please sign in again.';
    final records = rows('staffRecords');
    final openRecord = records
        .where(
          (row) =>
              row['userId'] == user['id'] &&
              row['date'] == today() &&
              row['outTs'] == null,
        )
        .firstOrNull;
    if (checkOut && openRecord == null) {
      return 'Check in first before checking out.';
    }
    if (!checkOut && openRecord != null) {
      return 'You are already checked in for today.';
    }
    final fence = _map(_data['geofence']);
    final lat = (fence['lat'] as num?)?.toDouble() ?? 19.19527;
    final lng = (fence['lng'] as num?)?.toDouble() ?? 72.97555;
    final radius = (fence['radius'] as num?)?.toDouble() ?? 150;
    final location = await _location.checkInside(
      latitude: lat,
      longitude: lng,
      radiusMeters: radius,
    );
    if (!location.accepted) {
      return location.error ?? 'Could not get your location.';
    }
    final distance = location.distanceMeters!;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (checkOut && openRecord != null) {
        openRecord['outTs'] = now;
        openRecord['outDist'] = distance.round();
      } else {
        records.add(<String, dynamic>{
          'id': _id('srec'),
          'staffId': user['id'],
          'userId': user['id'],
          'date': today(),
          'inTs': now,
          'inDist': distance.round(),
          'outTs': null,
          'outDist': null,
        });
      }
      save();
      return null;
    } catch (error) {
      return 'Could not get your location: $error';
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
