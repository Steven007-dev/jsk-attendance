import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_store.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

String _str(dynamic value, [String fallback = '—']) =>
    value == null || value.toString().trim().isEmpty
    ? fallback
    : value.toString();
String _monthKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';
String _dateLabel(String date) {
  final parsed = DateTime.tryParse(date);
  if (parsed == null) return date;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${parsed.day.toString().padLeft(2, '0')} ${months[parsed.month - 1]} ${parsed.year}';
}

String _timeLabel(dynamic millis) {
  if (millis is! num || millis == 0) return '—';
  final date = DateTime.fromMillisecondsSinceEpoch(millis.toInt());
  final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
  return '$hour:${date.minute.toString().padLeft(2, '0')} ${date.hour >= 12 ? 'PM' : 'AM'}';
}

String _batchName(AppStore store, dynamic id) =>
    store
        .rows('batches')
        .where((row) => row['id'] == id)
        .firstOrNull?['name']
        ?.toString() ??
    'Batch not set';
String _subjectName(AppStore store, dynamic id) =>
    store
        .rows('subjects')
        .where((row) => row['id'] == id)
        .firstOrNull?['name']
        ?.toString() ??
    'Subject';
Map<String, dynamic>? _studentFor(AppStore store, Map<String, dynamic> user) =>
    store.studentsForUser(user).firstOrNull;
int _percent(List<Map<String, dynamic>> records) {
  if (records.isEmpty) return 0;
  return (records.where((row) => row['status'] == 'present').length *
          100 /
          records.length)
      .round();
}

class StudentHomePage extends StatelessWidget {
  const StudentHomePage({required this.user, super.key});
  final Map<String, dynamic> user;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final students = store.studentsForUser(user);
    final isGuardian = user['role'] == 'guardian';
    if (students.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          PageHeading('Home'),
          EmptyState(
            title: 'No student profile linked',
            message: 'Contact the institute office to link this account.',
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
      children: [
        PageHeading(
          isGuardian ? 'Student overview' : 'Welcome, ${_str(user['name'])}',
          subtitle: isGuardian
              ? 'Attendance, fees and institute updates'
              : 'Your attendance, classes and institute updates',
        ),
        for (final student in students) ...[
          if (isGuardian)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                _str(student['name']),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          _StudentSummary(student: student),
          const SizedBox(height: 14),
        ],
        const SizedBox(height: 4),
        const PageHeading('Latest notices'),
        ...store
            .rows('announcements')
            .take(5)
            .map((notice) => _NoticeCard(notice: notice)),
        if (store.rows('announcements').isEmpty)
          const EmptyState(title: 'No new notices'),
        const SizedBox(height: 10),
        const PageHeading('Upcoming classes'),
        ..._visibleSchedules(
          store,
          students,
        ).take(5).map((schedule) => _ScheduleCard(schedule: schedule)),
        if (_visibleSchedules(store, students).isEmpty)
          const EmptyState(title: 'No class schedules yet'),
      ],
    );
  }
}

class _StudentSummary extends StatelessWidget {
  const _StudentSummary({required this.student});
  final Map<String, dynamic> student;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final records = store
        .rows('attendance')
        .where((row) => row['studentId'] == student['id'])
        .toList();
    final fee = store.feePaid(_str(student['id']), _monthKey(DateTime.now()));
    final recent = records
        .where((row) => row['date'] == AppStore.today())
        .length;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: MetricCard(
                label: 'Attendance',
                value: '${_percent(records)}%',
                icon: Icons.fact_check_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: MetricCard(
                label: 'Classes recorded',
                value: '${records.length}',
                icon: Icons.menu_book_outlined,
                color: AppTheme.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        AppCard(
          child: Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Current month fees',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              StatusPill(fee ? 'PAID' : 'NOT PAID', good: fee),
            ],
          ),
        ),
        if (recent > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '$recent attendance record${recent == 1 ? '' : 's'} today',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class StudentAttendancePage extends StatelessWidget {
  const StudentAttendancePage({required this.user, super.key});
  final Map<String, dynamic> user;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final students = store.studentsForUser(user);
    if (students.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          PageHeading('Attendance'),
          EmptyState(title: 'No student linked'),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const PageHeading(
          'Attendance',
          subtitle: 'Subject-wise attendance records',
        ),
        for (final student in students) ...[
          if (user['role'] == 'guardian')
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _str(student['name']),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          _AttendanceStudentCard(student: student),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _AttendanceStudentCard extends StatelessWidget {
  const _AttendanceStudentCard({required this.student});
  final Map<String, dynamic> student;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final rows =
        store
            .rows('attendance')
            .where((row) => row['studentId'] == student['id'])
            .toList()
          ..sort((a, b) => _str(b['date']).compareTo(_str(a['date'])));
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      groups
          .putIfAbsent(_subjectName(store, row['subjectId']), () => [])
          .add(row);
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _str(student['name']),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              StatusPill('${_percent(rows)}%'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${rows.where((row) => row['status'] == 'present').length} present of ${rows.length} recorded classes',
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty) const Text('No attendance has been recorded yet.'),
          for (final entry in groups.entries) ...[
            const Divider(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    entry.key,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                StatusPill('${_percent(entry.value)}%'),
              ],
            ),
            for (final row in entry.value.take(8))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  row['status'] == 'present'
                      ? Icons.check_circle_outline
                      : Icons.cancel_outlined,
                  color: row['status'] == 'present'
                      ? AppTheme.green
                      : AppTheme.brick,
                ),
                title: Text(_dateLabel(_str(row['date'], ''))),
                trailing: Text(
                  _str(row['status']).toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class TeacherAttendancePage extends StatefulWidget {
  const TeacherAttendancePage({required this.user, super.key});
  final Map<String, dynamic> user;

  @override
  State<TeacherAttendancePage> createState() => _TeacherAttendancePageState();
}

class _TeacherAttendancePageState extends State<TeacherAttendancePage> {
  String? _batchId;
  String? _subjectId;
  String _date = AppStore.today();
  final Map<String, String> _draft = <String, String>{};

  Future<void> _chooseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_date) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(
        () => _date =
            '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final assignments = store
        .rows('assignments')
        .where((row) => row['teacherId'] == widget.user['id'])
        .toList();
    final batchIds = assignments
        .map((row) => row['batchId']?.toString())
        .whereType<String>()
        .toSet();
    var batches = store
        .rows('batches')
        .where(
          (row) => batchIds.isEmpty || batchIds.contains(row['id']?.toString()),
        )
        .toList();
    if (batches.isEmpty) batches = store.rows('batches');
    final selectedBatch =
        batches.where((row) => row['id'] == _batchId).firstOrNull ??
        batches.firstOrNull;
    final batchId = selectedBatch?['id']?.toString();
    final subjectIds = assignments
        .where((row) => row['batchId'] == batchId)
        .map((row) => row['subjectId']?.toString())
        .whereType<String>()
        .toSet();
    var subjects = store
        .rows('subjects')
        .where(
          (row) =>
              subjectIds.isEmpty || subjectIds.contains(row['id']?.toString()),
        )
        .toList();
    final selectedSubject =
        subjects.where((row) => row['id'] == _subjectId).firstOrNull ??
        subjects.firstOrNull;
    final subjectId = selectedSubject?['id']?.toString();
    final students =
        store
            .rows('students')
            .where((row) => batchId != null && row['batchId'] == batchId)
            .toList()
          ..sort((a, b) => _str(a['name']).compareTo(_str(b['name'])));
    final existing = store.rows('attendance');

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 32),
      children: [
        const PageHeading(
          'Mark attendance',
          subtitle:
              'Choose the class, date and subject. Attendance is shared with students and guardians.',
        ),
        AppCard(
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: batchId,
                decoration: const InputDecoration(labelText: 'Batch'),
                items: batches
                    .map(
                      (batch) => DropdownMenuItem(
                        value: batch['id']?.toString(),
                        child: Text(_str(batch['name'])),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() {
                  _batchId = value;
                  _subjectId = null;
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedSubject?['id']?.toString(),
                decoration: const InputDecoration(labelText: 'Subject'),
                items: subjects
                    .map(
                      (subject) => DropdownMenuItem(
                        value: subject['id']?.toString(),
                        child: Text(_str(subject['name'])),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _subjectId = value),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _chooseDate,
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text(_dateLabel(_date)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (students.isEmpty)
          const EmptyState(
            title: 'No students in this batch',
            message: 'Ask an admin to assign students and teacher batches.',
          ),
        for (final student in students)
          Builder(
            builder: (context) {
              final old = existing
                  .where(
                    (record) =>
                        record['studentId'] == student['id'] &&
                        record['batchId'] == batchId &&
                        record['subjectId'] == subjectId &&
                        record['date'] == _date,
                  )
                  .firstOrNull;
              final status =
                  _draft[student['id']?.toString()] ??
                  old?['status']?.toString();
              return AppCard(
                margin: const EdgeInsets.only(bottom: 9),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 19,
                      child: Text(
                        _str(
                          student['name'],
                          'S',
                        ).characters.first.toUpperCase(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _str(student['name']),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            _str(student['rollNo'], _batchName(store, batchId)),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 'present', label: Text('P')),
                        ButtonSegment(value: 'absent', label: Text('A')),
                      ],
                      selected: status == null ? <String>{} : <String>{status},
                      onSelectionChanged: (selection) => setState(
                        () =>
                            _draft[student['id'].toString()] = selection.first,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        if (students.isNotEmpty)
          FilledButton.icon(
            onPressed: subjectId == null
                ? null
                : () {
                    var count = 0;
                    for (final student in students) {
                      final status = _draft[student['id']?.toString()];
                      if (status != null) {
                        store.setAttendance(
                          studentId: student['id'].toString(),
                          batchId: batchId.toString(),
                          subjectId: subjectId,
                          date: _date,
                          status: status,
                        );
                        count++;
                      }
                    }
                    _draft.clear();
                    showMessage(
                      context,
                      count == 0
                          ? 'Select present or absent for each student first.'
                          : 'Attendance saved for $count student${count == 1 ? '' : 's'}.',
                    );
                  },
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save attendance'),
          ),
      ],
    );
  }
}

class AdminStudentsPage extends StatelessWidget {
  const AdminStudentsPage({super.key});

  Future<void> _addStudent(BuildContext context) async {
    final name = TextEditingController();
    final email = TextEditingController();
    final password = TextEditingController();
    final course = TextEditingController();
    final roll = TextEditingController();
    final guardianName = TextEditingController();
    final guardianContact = TextEditingController();
    final guardianEmail = TextEditingController();
    final guardianPassword = TextEditingController();
    final store = context.read<AppStore>();
    String? batchId = store.rows('batches').firstOrNull?['id']?.toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add student account'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Student name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Login email'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: password,
                  decoration: const InputDecoration(
                    labelText: 'Initial password',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: course,
                  decoration: const InputDecoration(labelText: 'Course'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: roll,
                  decoration: const InputDecoration(labelText: 'Roll number'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue:
                      store.rows('batches').any((item) => item['id'] == batchId)
                      ? batchId
                      : null,
                  decoration: const InputDecoration(labelText: 'Batch'),
                  items: store
                      .rows('batches')
                      .map(
                        (item) => DropdownMenuItem(
                          value: item['id']?.toString(),
                          child: Text(_str(item['name'])),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setDialogState(() => batchId = value),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: guardianName,
                  decoration: const InputDecoration(
                    labelText: 'Guardian name (optional)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: guardianContact,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Guardian contact',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: guardianEmail,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Guardian login email (optional)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: guardianPassword,
                  decoration: const InputDecoration(
                    labelText: 'Guardian initial password',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (ok == true &&
        context.mounted &&
        name.text.trim().isNotEmpty &&
        email.text.trim().isNotEmpty &&
        password.text.isNotEmpty) {
      store.createPerson(
        name: name.text,
        email: email.text,
        password: password.text,
        role: 'student',
      );
      final student = store.rows('students').last;
      student['course'] = course.text.trim();
      student['rollNo'] = roll.text.trim();
      student['batchId'] = batchId ?? '';
      student['guardianName'] = guardianName.text.trim();
      student['guardianContact'] = guardianContact.text.trim();
      if (guardianEmail.text.trim().isNotEmpty &&
          guardianPassword.text.isNotEmpty) {
        store.createPerson(
          name: guardianName.text.trim().isEmpty
              ? 'Guardian of ${name.text.trim()}'
              : guardianName.text,
          email: guardianEmail.text,
          password: guardianPassword.text,
          role: 'guardian',
        );
        student['guardianUserId'] = store.rows('users').last['id'];
      }
      store.save();
      if (context.mounted) showMessage(context, 'Student account created.');
    }
    name.dispose();
    email.dispose();
    password.dispose();
    course.dispose();
    roll.dispose();
    guardianName.dispose();
    guardianContact.dispose();
    guardianEmail.dispose();
    guardianPassword.dispose();
  }

  Future<void> _editStudent(
    BuildContext context,
    Map<String, dynamic> student,
  ) async {
    final name = TextEditingController(text: _str(student['name'], ''));
    final course = TextEditingController(text: _str(student['course'], ''));
    final standard = TextEditingController(text: _str(student['standard'], ''));
    final roll = TextEditingController(text: _str(student['rollNo'], ''));
    final guardianName = TextEditingController(
      text: _str(student['guardianName'], ''),
    );
    final guardianContact = TextEditingController(
      text: _str(student['guardianContact'], ''),
    );
    final store = context.read<AppStore>();
    String? batchId = student['batchId']?.toString();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Edit ${_str(student['name'])}'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Student name',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: course,
                    decoration: const InputDecoration(labelText: 'Course'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: standard,
                    decoration: const InputDecoration(labelText: 'Standard'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: roll,
                    decoration: const InputDecoration(labelText: 'Roll number'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue:
                        store
                            .rows('batches')
                            .any((item) => item['id'] == batchId)
                        ? batchId
                        : null,
                    decoration: const InputDecoration(labelText: 'Batch'),
                    items: store
                        .rows('batches')
                        .map(
                          (item) => DropdownMenuItem(
                            value: item['id']?.toString(),
                            child: Text(_str(item['name'])),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setDialogState(() => batchId = value),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: guardianName,
                    decoration: const InputDecoration(
                      labelText: 'Guardian name',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: guardianContact,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Guardian contact',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved == true && context.mounted) {
      student['name'] = name.text.trim();
      student['course'] = course.text.trim();
      student['standard'] = standard.text.trim();
      student['rollNo'] = roll.text.trim();
      student['batchId'] = batchId ?? '';
      student['guardianName'] = guardianName.text.trim();
      student['guardianContact'] = guardianContact.text.trim();
      store.save();
      showMessage(context, 'Student profile updated.');
    }
    name.dispose();
    course.dispose();
    standard.dispose();
    roll.dispose();
    guardianName.dispose();
    guardianContact.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final students = store.rows('students')
      ..sort((a, b) => _str(a['name']).compareTo(_str(b['name'])));
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        PageHeading(
          'Students',
          subtitle: '${students.length} student profiles',
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: () => _addStudent(context),
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Add student'),
          ),
        ),
        const SizedBox(height: 14),
        if (students.isEmpty)
          const EmptyState(title: 'No student profiles yet'),
        for (final student in students)
          AppCard(
            margin: const EdgeInsets.only(bottom: 9),
            child: Row(
              children: [
                const CircleAvatar(child: Icon(Icons.school_outlined)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _str(student['name']),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${_str(student['course'], 'Course not set')} · ${_batchName(store, student['batchId'])}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        _str(
                          student['rollNo'],
                          _str(student['email'], 'No login linked'),
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text(
                  '${_percent(store.rows('attendance').where((row) => row['studentId'] == student['id']).toList())}%',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                IconButton(
                  tooltip: 'Edit student profile',
                  onPressed: () => _editStudent(context, student),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class AdminFeesPage extends StatefulWidget {
  const AdminFeesPage({super.key});

  @override
  State<AdminFeesPage> createState() => _AdminFeesPageState();
}

class _AdminFeesPageState extends State<AdminFeesPage> {
  String _month = _monthKey(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final students = store.rows('students')
      ..sort((a, b) => _str(a['name']).compareTo(_str(b['name'])));
    final months = List.generate(8, (i) {
      final d = DateTime(DateTime.now().year, DateTime.now().month - i, 1);
      return _monthKey(d);
    });
    final paid = students
        .where((student) => store.feePaid(_str(student['id']), _month))
        .length;
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const PageHeading(
          'Fees',
          subtitle:
              'Mark each student paid or not paid for the selected month.',
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: months.contains(_month) ? _month : months.first,
                decoration: const InputDecoration(labelText: 'Fee month'),
                items: months
                    .map(
                      (month) =>
                          DropdownMenuItem(value: month, child: Text(month)),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _month = value ?? _month),
              ),
              const SizedBox(height: 12),
              Text('$paid of ${students.length} marked paid'),
              const SizedBox(height: 7),
              LinearProgressIndicator(
                value: students.isEmpty ? 0 : paid / students.length,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        for (final student in students) ...[
          Builder(
            builder: (context) {
              final isPaid = store.feePaid(_str(student['id']), _month);
              return AppCard(
                margin: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _str(student['name']),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            _str(
                              student['rollNo'],
                              _batchName(store, student['batchId']),
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    StatusPill(isPaid ? 'PAID' : 'NOT PAID', good: isPaid),
                    const SizedBox(width: 8),
                    Switch(
                      value: isPaid,
                      onChanged: (value) =>
                          store.setFeePaid(_str(student['id']), _month, value),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}

class NoticesPage extends StatefulWidget {
  const NoticesPage({required this.user, super.key});
  final Map<String, dynamic> user;

  @override
  State<NoticesPage> createState() => _NoticesPageState();
}

class _NoticesPageState extends State<NoticesPage> {
  final _title = TextEditingController();
  final _message = TextEditingController();
  String _audience = 'everyone';

  @override
  void dispose() {
    _title.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final notices = store.rows('announcements')
      ..sort(
        (a, b) => ((b['ts'] as num?) ?? 0).compareTo((a['ts'] as num?) ?? 0),
      );
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const PageHeading(
          'Send notices',
          subtitle: 'Publish an institute notice to selected account roles.',
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Notice title'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _message,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Message'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _audience,
                decoration: const InputDecoration(labelText: 'Send to'),
                items: const [
                  DropdownMenuItem(value: 'everyone', child: Text('Everyone')),
                  DropdownMenuItem(value: 'student', child: Text('Students')),
                  DropdownMenuItem(value: 'guardian', child: Text('Guardians')),
                  DropdownMenuItem(value: 'teacher', child: Text('Teachers')),
                  DropdownMenuItem(value: 'staff', child: Text('Staff')),
                ],
                onChanged: (value) =>
                    setState(() => _audience = value ?? 'everyone'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  if (_title.text.trim().isEmpty ||
                      _message.text.trim().isEmpty) {
                    showMessage(context, 'Enter a title and message first.');
                    return;
                  }
                  store.publishNotice(
                    title: _title.text,
                    message: _message.text,
                    audience: _audience,
                  );
                  _title.clear();
                  _message.clear();
                  showMessage(context, 'Notice published.');
                },
                icon: const Icon(Icons.send_outlined),
                label: const Text('Publish notice'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        PageHeading('Published notices (${notices.length})'),
        if (notices.isEmpty)
          const EmptyState(title: 'No notices have been published'),
        ...notices.map((notice) => _NoticeCard(notice: notice)),
      ],
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.notice});
  final Map<String, dynamic> notice;

  @override
  Widget build(BuildContext context) => AppCard(
    margin: const EdgeInsets.only(bottom: 9),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _str(notice['title'], 'Institute notice'),
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (notice['audience'] != null)
              StatusPill(_str(notice['audience']).toUpperCase()),
          ],
        ),
        const SizedBox(height: 7),
        Text(_str(notice['body'] ?? notice['message'], '')),
        const SizedBox(height: 7),
        Text(
          _dateLabel(_str(notice['date'], '')),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class InboxPage extends StatelessWidget {
  const InboxPage({required this.user, super.key});
  final Map<String, dynamic> user;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final isAdmin = user['role'] == 'admin';
    final messages =
        store
            .rows('inbox')
            .where((item) => isAdmin || item['recipientUserId'] == user['id'])
            .toList()
          ..sort(
            (a, b) =>
                ((b['ts'] as num?) ?? 0).compareTo((a['ts'] as num?) ?? 0),
          );
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        PageHeading(
          isAdmin ? 'Notifications & activity' : 'Notifications',
          subtitle: isAdmin
              ? 'Institute inbox and staff attendance events'
              : 'Attendance, fees, class schedules and office notices',
        ),
        if (messages.any(
          (item) =>
              item['read'] != true && item['recipientUserId'] == user['id'],
        ))
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: store.markAllRead,
              icon: const Icon(Icons.done_all),
              label: const Text('Mark all read'),
            ),
          ),
        if (isAdmin)
          ...store
              .rows('staffNotifications')
              .take(20)
              .map(
                (event) => AppCard(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(_str(event['text'], 'Staff attendance event')),
                    subtitle: Text(_timeLabel(event['ts'])),
                  ),
                ),
              ),
        if (messages.isEmpty &&
            (!isAdmin || store.rows('staffNotifications').isEmpty))
          const EmptyState(title: 'You are all caught up'),
        for (final message in messages)
          AppCard(
            margin: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                if (message['id'] != null) {
                  store.markRead(message['id'].toString());
                }
              },
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    message['read'] == true
                        ? Icons.mark_email_read_outlined
                        : Icons.mark_email_unread_outlined,
                    color: message['read'] == true
                        ? null
                        : Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _str(message['title'], 'Institute update'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(_str(message['message'], '')),
                        const SizedBox(height: 6),
                        Text(
                          _timeLabel(message['ts']),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class SchedulePage extends StatefulWidget {
  const SchedulePage({required this.user, super.key});
  final Map<String, dynamic> user;

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  String? _batch;
  String? _subject;
  final _date = TextEditingController(text: AppStore.today());
  final _topic = TextEditingController();
  final _time = TextEditingController(text: '10:00');
  final _endTime = TextEditingController(text: '11:00');
  final _room = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _date.dispose();
    _topic.dispose();
    _time.dispose();
    _endTime.dispose();
    _room.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final teacherMode = widget.user['role'] == 'teacher';
    final assignments = store
        .rows('assignments')
        .where((item) => !teacherMode || item['teacherId'] == widget.user['id'])
        .toList();
    final batchIds = assignments.map((item) => item['batchId']).toSet();
    final batches = store
        .rows('batches')
        .where((item) => !teacherMode || batchIds.contains(item['id']))
        .toList();
    final selectedBatch =
        batches.where((item) => item['id'] == _batch).firstOrNull ??
        batches.firstOrNull;
    final subjectIds = assignments
        .where((item) => item['batchId'] == selectedBatch?['id'])
        .map((item) => item['subjectId'])
        .toSet();
    final subjects = store
        .rows('subjects')
        .where((item) => !teacherMode || subjectIds.contains(item['id']))
        .toList();
    final schedule = store.rows('schedules').where((item) {
      if (!teacherMode) {
        final studentIds = store
            .studentsForUser(widget.user)
            .map((student) => student['batchId'])
            .toSet();
        return studentIds.contains(item['batchId']);
      }
      return item['teacherId'] == widget.user['id'];
    }).toList()..sort((a, b) => _str(a['date']).compareTo(_str(b['date'])));
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        PageHeading(
          teacherMode ? 'Schedule lecture' : 'Class schedule',
          subtitle: teacherMode
              ? 'Add a class schedule for your assigned batch.'
              : 'Upcoming lessons for your class.',
        ),
        if (teacherMode)
          AppCard(
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedBatch?['id']?.toString(),
                  decoration: const InputDecoration(labelText: 'Batch'),
                  items: batches
                      .map(
                        (item) => DropdownMenuItem(
                          value: item['id']?.toString(),
                          child: Text(_str(item['name'])),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() {
                    _batch = value;
                    _subject = null;
                  }),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue:
                      subjects
                          .where((item) => item['id'] == _subject)
                          .firstOrNull?['id']
                          ?.toString() ??
                      subjects.firstOrNull?['id']?.toString(),
                  decoration: const InputDecoration(labelText: 'Subject'),
                  items: subjects
                      .map(
                        (item) => DropdownMenuItem(
                          value: item['id']?.toString(),
                          child: Text(_str(item['name'])),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _subject = value),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _date,
                  decoration: const InputDecoration(
                    labelText: 'Date (YYYY-MM-DD)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _topic,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Topic'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _time,
                        decoration: const InputDecoration(
                          labelText: 'Start time',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _endTime,
                        decoration: const InputDecoration(
                          labelText: 'End time',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _room,
                  decoration: const InputDecoration(
                    labelText: 'Room / location (optional)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _note,
                  decoration: const InputDecoration(
                    labelText: 'Class note (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: selectedBatch == null || subjects.isEmpty
                      ? null
                      : () {
                          if (_topic.text.trim().isEmpty ||
                              _date.text.trim().isEmpty ||
                              _time.text.trim().isEmpty) {
                            showMessage(
                              context,
                              'Enter the topic, date and start time.',
                            );
                            return;
                          }
                          final subject =
                              subjects
                                  .where((item) => item['id'] == _subject)
                                  .firstOrNull ??
                              subjects.first;
                          store.createSchedule(
                            batchId: selectedBatch['id'].toString(),
                            subjectId: subject['id'].toString(),
                            date: _date.text.trim(),
                            topic: _topic.text.trim(),
                            time: _time.text.trim(),
                            endTime: _endTime.text.trim(),
                            room: _room.text.trim(),
                            note: _note.text.trim(),
                          );
                          showMessage(context, 'Lecture scheduled.');
                        },
                  icon: const Icon(Icons.event_available_outlined),
                  label: const Text('Publish schedule'),
                ),
              ],
            ),
          ),
        if (teacherMode) const SizedBox(height: 16),
        PageHeading(teacherMode ? 'Your schedules' : 'Upcoming classes'),
        if (schedule.isEmpty) const EmptyState(title: 'No schedules yet'),
        ...schedule.map((item) => _ScheduleCard(schedule: item)),
      ],
    );
  }
}

List<Map<String, dynamic>> _visibleSchedules(
  AppStore store,
  List<Map<String, dynamic>> students,
) {
  final batches = students.map((student) => student['batchId']).toSet();
  return store
      .rows('schedules')
      .where((row) => batches.contains(row['batchId']))
      .toList()
    ..sort((a, b) => _str(a['date']).compareTo(_str(b['date'])));
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.schedule});
  final Map<String, dynamic> schedule;

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppStore>();
    return AppCard(
      margin: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.menu_book_outlined),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _str(
                    schedule['topic'],
                    _subjectName(store, schedule['subjectId']),
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${_dateLabel(_str(schedule['date'], ''))} · ${_str(schedule['time'])}${_str(schedule['endTime'], '').isEmpty ? '' : '–${_str(schedule['endTime'], '')}'}',
                ),
                Text(
                  '${_batchName(store, schedule['batchId'])} · ${_str(schedule['teacherName'], 'Teacher')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_str(schedule['room'], '').isNotEmpty)
                  Text(
                    _str(schedule['room']),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (_str(schedule['note'], '').isNotEmpty)
                  Text(
                    _str(schedule['note'], ''),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class StaffAttendancePage extends StatefulWidget {
  const StaffAttendancePage({
    required this.user,
    this.teacherView = false,
    super.key,
  });
  final Map<String, dynamic> user;
  final bool teacherView;

  @override
  State<StaffAttendancePage> createState() => _StaffAttendancePageState();
}

class _StaffAttendancePageState extends State<StaffAttendancePage> {
  bool _busy = false;

  Future<void> _record(bool checkout) async {
    setState(() => _busy = true);
    final message = await context.read<AppStore>().staffCheck(
      checkOut: checkout,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (message != null) {
      showMessage(context, message);
    } else {
      showMessage(
        context,
        checkout ? 'Check-out recorded.' : 'Check-in recorded.',
      );
    }
  }

  Future<void> _leaveRequest() async {
    final reason = TextEditingController();
    var date = AppStore.today();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Request leave'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: date,
                decoration: const InputDecoration(
                  labelText: 'Date (YYYY-MM-DD)',
                ),
                onChanged: (value) => setDialogState(() => date = value),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: reason,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Reason'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Submit'),
            ),
          ],
        ),
      ),
    );
    if (submitted == true && reason.text.trim().isNotEmpty && mounted) {
      context.read<AppStore>().requestLeave(
        date: date.trim(),
        reason: reason.text.trim(),
      );
      showMessage(context, 'Leave request sent to the office.');
    }
    reason.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final userId = widget.user['id'];
    final role = widget.user['role']?.toString() ?? 'staff';
    final isAdmin = role == 'admin';
    final records =
        store
            .rows('staffRecords')
            .where((row) => isAdmin || row['userId'] == userId)
            .toList()
          ..sort((a, b) => _str(b['date']).compareTo(_str(a['date'])));
    final todayRecord = records
        .where(
          (row) => row['date'] == AppStore.today() && row['userId'] == userId,
        )
        .firstOrNull;
    final isOpen = todayRecord != null && todayRecord['outTs'] == null;
    final leaveRequests =
        store
            .rows('leaveRequests')
            .where((row) => isAdmin || row['userId'] == userId)
            .toList()
          ..sort(
            (a, b) =>
                ((b['ts'] as num?) ?? 0).compareTo((a['ts'] as num?) ?? 0),
          );
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        PageHeading(
          widget.teacherView
              ? 'My attendance'
              : isAdmin
              ? 'Staff attendance'
              : 'Attendance',
          subtitle: widget.teacherView
              ? 'Your daily check-in, check-out and leave requests.'
              : isAdmin
              ? 'Latest location-verified staff and teacher records.'
              : 'Check in and out inside the institute geofence.',
        ),
        if (!isAdmin)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Institute location required',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  'Your position is checked against the institute radius before recording attendance.',
                ),
                const SizedBox(height: 13),
                FilledButton.icon(
                  onPressed: _busy || isOpen ? null : () => _record(false),
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 17,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: const Text('Check in'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy || !isOpen ? null : () => _record(true),
                  icon: const Icon(Icons.logout),
                  label: const Text('Check out'),
                ),
                const SizedBox(height: 6),
                Text(
                  isOpen
                      ? 'Checked in at ${_timeLabel(todayRecord['inTs'])}'
                      : todayRecord == null
                      ? 'Not checked in today.'
                      : 'Shift completed at ${_timeLabel(todayRecord['outTs'])}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        if (!isAdmin) const SizedBox(height: 14),
        if (!isAdmin)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _leaveRequest,
              icon: const Icon(Icons.event_busy_outlined),
              label: const Text('Request leave'),
            ),
          ),
        const SizedBox(height: 12),
        PageHeading(isAdmin ? 'Recent staff check-ins' : 'Attendance history'),
        if (records.isEmpty)
          const EmptyState(title: 'No attendance records yet'),
        for (final record in records.take(40))
          AppCard(
            margin: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Icon(Icons.access_time),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.teacherView || isAdmin
                            ? _str(
                                store
                                    .rows('users')
                                    .where(
                                      (row) => row['id'] == record['userId'],
                                    )
                                    .firstOrNull?['name'],
                                'Staff member',
                              )
                            : _dateLabel(_str(record['date'], '')),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${_dateLabel(_str(record['date'], ''))} · ${_timeLabel(record['inTs'])}–${_timeLabel(record['outTs'])}',
                      ),
                    ],
                  ),
                ),
                StatusPill(
                  record['outTs'] == null ? 'OPEN' : 'DONE',
                  good: record['outTs'] != null,
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        PageHeading(isAdmin ? 'Leave requests' : 'My leave requests'),
        if (isAdmin)
          for (final request
              in store
                  .rows('leaveRequests')
                  .where((row) => row['status'] == 'pending'))
            AppCard(
              margin: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_str(request['name'])} · ${_dateLabel(_str(request['date'], ''))}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(_str(request['reason'], '')),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () =>
                            store.decideLeave(_str(request['id']), 'declined'),
                        child: const Text('Decline'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () =>
                            store.decideLeave(_str(request['id']), 'accepted'),
                        child: const Text('Accept'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        if (!isAdmin)
          ...leaveRequests
              .take(12)
              .map(
                (request) => AppCard(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_dateLabel(_str(request['date'], ''))),
                    subtitle: Text(_str(request['reason'], '')),
                    trailing: StatusPill(
                      _str(request['status']).toUpperCase(),
                      good: request['status'] == 'accepted',
                    ),
                  ),
                ),
              ),
      ],
    );
  }
}

class AdminPeoplePage extends StatelessWidget {
  const AdminPeoplePage({required this.role, required this.title, super.key});
  final String role;
  final String title;

  Future<void> _add(BuildContext context) async {
    final name = TextEditingController();
    final email = TextEditingController();
    final password = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Add ${role == 'teacher' ? 'teacher' : role} account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Login email'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: password,
              decoration: const InputDecoration(labelText: 'Initial password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (ok == true &&
        context.mounted &&
        name.text.trim().isNotEmpty &&
        email.text.trim().isNotEmpty &&
        password.text.isNotEmpty) {
      context.read<AppStore>().createPerson(
        name: name.text,
        email: email.text,
        password: password.text,
        role: role,
      );
      if (context.mounted) showMessage(context, 'Account created.');
    }
    name.dispose();
    email.dispose();
    password.dispose();
  }

  Future<void> _addBatch(BuildContext context) async {
    final name = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add batch'),
        content: TextField(
          controller: name,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Batch name'),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (accepted == true && context.mounted && name.text.trim().isNotEmpty) {
      context.read<AppStore>().createBatch(name.text);
      showMessage(context, 'Batch added.');
    }
    name.dispose();
  }

  Future<void> _editTeacherAssignments(
    BuildContext context,
    Map<String, dynamic> teacher,
  ) async {
    final store = context.read<AppStore>();
    final existing = store
        .rows('assignments')
        .where((item) => item['teacherId'] == teacher['id'])
        .map((item) => '${item['batchId']}|${item['subjectId']}')
        .toSet();
    final selected = <String>{...existing};
    final batches = store.rows('batches');
    final subjects = store.rows('subjects');
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Classes for ${_str(teacher['name'])}'),
          content: SizedBox(
            width: 420,
            height: 460,
            child: ListView(
              children: [
                for (final batch in batches)
                  ExpansionTile(
                    initiallyExpanded: batches.length == 1,
                    title: Text(_str(batch['name'])),
                    children: [
                      for (final subject in subjects)
                        CheckboxListTile(
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(_str(subject['name'])),
                          value: selected.contains(
                            '${batch['id']}|${subject['id']}',
                          ),
                          onChanged: (checked) => setDialogState(() {
                            final key = '${batch['id']}|${subject['id']}';
                            if (checked == true) {
                              selected.add(key);
                            } else {
                              selected.remove(key);
                            }
                          }),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && context.mounted) {
      context.read<AppStore>().setTeacherAssignments(
        teacher['id'].toString(),
        selected,
      );
      showMessage(context, 'Teacher assignments saved.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final people =
        store
            .rows('users')
            .where((user) => user['role'] == role && user['ghost'] != true)
            .toList()
          ..sort((a, b) => _str(a['name']).compareTo(_str(b['name'])));
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        PageHeading(title, subtitle: '${people.length} accounts'),
        if (role != 'admin')
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => _add(context),
              icon: const Icon(Icons.person_add_alt_1),
              label: Text('Add ${role == 'teacher' ? 'teacher' : 'staff'}'),
            ),
          ),
        if (role == 'admin')
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => _add(context),
              icon: const Icon(Icons.admin_panel_settings_outlined),
              label: const Text('Add admin'),
            ),
          ),
        if (role == 'teacher') ...[
          const SizedBox(height: 14),
          PageHeading('Batches (${store.rows('batches').length})'),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _addBatch(context),
              icon: const Icon(Icons.add),
              label: const Text('Add batch'),
            ),
          ),
          if (store.rows('batches').isEmpty)
            const EmptyState(
              title: 'No batches yet',
              message: 'Add a batch before assigning teacher classes.',
            ),
          for (final batch in store.rows('batches'))
            AppCard(
              margin: const EdgeInsets.only(bottom: 7),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.groups_2_outlined),
                title: Text(_str(batch['name'])),
                subtitle: Text(
                  '${store.rows('students').where((student) => student['batchId'] == batch['id']).length} students',
                ),
              ),
            ),
        ],
        const SizedBox(height: 14),
        if (people.isEmpty) const EmptyState(title: 'No accounts yet'),
        for (final person in people)
          AppCard(
            margin: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                CircleAvatar(
                  child: Icon(
                    role == 'teacher'
                        ? Icons.cast_for_education_outlined
                        : role == 'admin'
                        ? Icons.admin_panel_settings_outlined
                        : Icons.badge_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _str(person['name']),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        _str(person['email']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (role == 'teacher')
                        Text(
                          '${store.rows('assignments').where((item) => item['teacherId'] == person['id']).length} class assignments',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                if (role == 'teacher')
                  IconButton(
                    tooltip: 'Assign batches and subjects',
                    onPressed: () => _editTeacherAssignments(context, person),
                    icon: const Icon(Icons.tune),
                  ),
                StatusPill(role.toUpperCase()),
              ],
            ),
          ),
        if (role == 'teacher') ...[
          const SizedBox(height: 12),
          const PageHeading('Teacher assignments'),
          for (final item in store.rows('assignments'))
            AppCard(
              margin: const EdgeInsets.only(bottom: 7),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.class_outlined),
                title: Text(_subjectName(store, item['subjectId'])),
                subtitle: Text(
                  '${_batchName(store, item['batchId'])} · ${_str(store.rows('users').where((person) => person['id'] == item['teacherId']).firstOrNull?['name'], 'Teacher')}',
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({required this.user, super.key});
  final Map<String, dynamic> user;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final student = _studentFor(store, user);
    final fields = <String, dynamic>{
      'Account name': user['name'],
      'Email': user['email'],
      'Role': user['role'],
      if (student != null) 'Roll number': student['rollNo'],
      if (student != null) 'Course': student['course'],
      if (student != null) 'Standard': student['standard'],
      if (student != null) 'Batch': _batchName(store, student['batchId']),
      if (student != null) 'Guardian': student['guardianName'],
      if (student != null) 'Guardian contact': student['guardianContact'],
    };
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const PageHeading(
          'My profile',
          subtitle: 'Your institute account and student details',
        ),
        AppCard(
          child: Column(
            children: [
              CircleAvatar(
                radius: 34,
                child: Text(
                  _str(user['name'], 'J').characters.first.toUpperCase(),
                  style: const TextStyle(fontSize: 24),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _str(user['name']),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                _str(user['role']).toUpperCase(),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            children: [
              for (final entry in fields.entries)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    entry.key,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  subtitle: Text(_str(entry.value)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({required this.user, super.key});
  final Map<String, dynamic> user;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const PageHeading(
          'Settings',
          subtitle: 'Appearance, notifications and account',
        ),
        AppCard(
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Dark appearance'),
            subtitle: const Text('Use the dark institute color scheme'),
            value: store.isDark,
            onChanged: store.setDark,
            secondary: const Icon(Icons.dark_mode_outlined),
          ),
        ),
        const SizedBox(height: 9),
        AppCard(
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Phone notifications'),
            subtitle: const Text('Attendance, fees and institute notices'),
            value: user['phoneNotifs'] == true,
            onChanged: store.setPushEnabled,
            secondary: const Icon(Icons.notifications_active_outlined),
          ),
        ),
        const SizedBox(height: 9),
        AppCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.language_outlined),
            title: const Text('Language'),
            subtitle: Text(_str(store.ui['language'], 'en').toUpperCase()),
            trailing: DropdownButton<String>(
              value: <String>['en', 'hi', 'mr'].contains(store.ui['language'])
                  ? store.ui['language'] as String
                  : 'en',
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'en', child: Text('English')),
                DropdownMenuItem(value: 'hi', child: Text('Hindi')),
                DropdownMenuItem(value: 'mr', child: Text('Marathi')),
              ],
              onChanged: (value) {
                if (value != null) {
                  store.ui['language'] = value;
                  store.save();
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 9),
        AppCard(
          child: ListTile(
            leading: Icon(
              store.onlineSyncConfigured
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_off_outlined,
            ),
            title: const Text('Data sync'),
            subtitle: Text(store.cloudMessage ?? 'Offline mode'),
            trailing: IconButton(
              tooltip: 'Refresh',
              onPressed: store.onlineSyncConfigured ? store.refreshCloud : null,
              icon: const Icon(Icons.refresh),
            ),
          ),
        ),
        const SizedBox(height: 9),
        AppCard(
          child: ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: Text(_str(user['name'])),
            subtitle: Text(
              '${_str(user['email'])}\n${_str(user['role']).toUpperCase()}',
            ),
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: store.logout,
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
        const SizedBox(height: 12),
        Text(
          'JSK Attendance · 1.5.17',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
