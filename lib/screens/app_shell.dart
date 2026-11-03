import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_role.dart';
import '../providers/app_store.dart';
import '../widgets/common_widgets.dart';
import 'login_screen.dart';
import 'role_pages.dart';

class _RouteSpec {
  const _RouteSpec(this.key, this.label, this.icon);
  final String key;
  final String label;
  final IconData icon;
}

const _adminRoutes = <_RouteSpec>[
  _RouteSpec('notices', 'Send Notices', Icons.campaign_outlined),
  _RouteSpec('notifications', 'Notifications', Icons.notifications_none),
  _RouteSpec('students', 'Students', Icons.school_outlined),
  _RouteSpec('guardians', 'Guardians', Icons.family_restroom_outlined),
  _RouteSpec('fees', 'Fees', Icons.fact_check_outlined),
  _RouteSpec(
    'teachers',
    'Teachers & Batches',
    Icons.cast_for_education_outlined,
  ),
  _RouteSpec('staff', 'Staff', Icons.badge_outlined),
  _RouteSpec('admins', 'Admins', Icons.admin_panel_settings_outlined),
  _RouteSpec('settings', 'Settings', Icons.settings_outlined),
];
const _teacherRoutes = <_RouteSpec>[
  _RouteSpec('attendance', 'Mark Attendance', Icons.fact_check_outlined),
  _RouteSpec('schedule', 'Schedule Lecture', Icons.calendar_month_outlined),
  _RouteSpec('myatt', 'My Attendance', Icons.timelapse_outlined),
  _RouteSpec('notifications', 'Notifications', Icons.notifications_none),
  _RouteSpec('settings', 'Settings', Icons.settings_outlined),
];
const _staffRoutes = <_RouteSpec>[
  _RouteSpec('attendance', 'Attendance', Icons.location_on_outlined),
  _RouteSpec('notifications', 'Notifications', Icons.notifications_none),
  _RouteSpec('settings', 'Settings', Icons.settings_outlined),
];
const _guardianRoutes = <_RouteSpec>[
  _RouteSpec('home', 'Home', Icons.home_outlined),
  _RouteSpec('attendance', 'Attendance', Icons.fact_check_outlined),
  _RouteSpec('notifications', 'Notifications', Icons.notifications_none),
  _RouteSpec('settings', 'Settings', Icons.settings_outlined),
];
const _studentRoutes = <_RouteSpec>[
  _RouteSpec('home', 'Home', Icons.home_outlined),
  _RouteSpec('attendance', 'Attendance', Icons.fact_check_outlined),
  _RouteSpec('notifications', 'Notifications', Icons.notifications_none),
  _RouteSpec('profile', 'My Profile', Icons.person_outline),
  _RouteSpec('settings', 'Settings', Icons.settings_outlined),
];

List<_RouteSpec> _routesFor(AppRole role) => switch (role) {
  AppRole.admin => _adminRoutes,
  AppRole.teacher => _teacherRoutes,
  AppRole.staff => _staffRoutes,
  AppRole.guardian => _guardianRoutes,
  _ => _studentRoutes,
};

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) => Consumer<AppStore>(
    builder: (context, store, _) {
      if (store.loading) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final user = store.currentUser;
      if (user == null) return const LoginScreen();
      final role = user['role']?.toString() ?? 'student';
      final routes = _routesFor(parseRole(role));
      final page = store.ui['page']?.toString() ?? routes.first.key;
      final current =
          routes.where((route) => route.key == page).firstOrNull ??
          routes.first;
      final bottom = switch (role) {
        'admin' => const <String>[
          'notices',
          'notifications',
          'students',
          'fees',
        ],
        'teacher' => const <String>[
          'attendance',
          'schedule',
          'notifications',
          'settings',
        ],
        _ => routes.map((route) => route.key).take(4).toList(),
      };
      final bottomIndex = bottom.indexOf(page);
      return Scaffold(
        appBar: AppBar(
          titleSpacing: 16,
          title: Row(
            children: [
              ClipOval(
                child: Image.asset(
                  'assets/jsk_logo.png',
                  width: 34,
                  height: 34,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      current.label,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'JSK Institute',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: store.onlineSyncConfigured
                  ? (store.syncing ? 'Syncing' : 'Refresh cloud data')
                  : 'Offline mode',
              onPressed: store.onlineSyncConfigured && !store.syncing
                  ? store.refreshCloud
                  : null,
              icon: Icon(
                store.syncing
                    ? Icons.sync
                    : store.onlineSyncConfigured
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_off_outlined,
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
        drawer: _AppDrawer(user: user, routes: routes, selected: page),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: PageRouter(page: page, user: user),
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: bottomIndex < 0 ? 0 : bottomIndex,
          onDestinationSelected: (index) => store.navigate(bottom[index]),
          destinations: bottom.map((key) {
            final route = routes.where((item) => item.key == key).firstOrNull;
            return NavigationDestination(
              icon: Icon(route?.icon ?? Icons.circle_outlined),
              label: route?.label ?? key,
            );
          }).toList(),
        ),
      );
    },
  );
}

class _AppDrawer extends StatelessWidget {
  const _AppDrawer({
    required this.user,
    required this.routes,
    required this.selected,
  });
  final Map<String, dynamic> user;
  final List<_RouteSpec> routes;
  final String selected;

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppStore>();
    final name = user['name']?.toString() ?? 'JSK user';
    final role = user['role']?.toString() ?? 'student';
    return NavigationDrawer(
      selectedIndex: routes.indexWhere((route) => route.key == selected),
      onDestinationSelected: (index) {
        Navigator.pop(context);
        if (index < routes.length) store.navigate(routes[index].key);
      },
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 16, 18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 25,
                child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'J'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      role.toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        for (final route in routes)
          NavigationDrawerDestination(
            icon: Icon(route.icon),
            label: Text(route.label),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Divider(),
        ),
        ListTile(
          leading: Icon(
            Icons.logout,
            color: Theme.of(context).colorScheme.error,
          ),
          title: const Text('Sign out'),
          onTap: () async {
            Navigator.pop(context);
            await store.logout();
          },
        ),
      ],
    );
  }
}

class PageRouter extends StatelessWidget {
  const PageRouter({required this.page, required this.user, super.key});
  final String page;
  final Map<String, dynamic> user;

  @override
  Widget build(BuildContext context) {
    switch (page) {
      case 'notices':
        return NoticesPage(user: user);
      case 'notifications':
        return InboxPage(user: user);
      case 'students':
        return const AdminStudentsPage();
      case 'guardians':
        return const AdminPeoplePage(role: 'guardian', title: 'Guardians');
      case 'fees':
        return AdminFeesPage();
      case 'teachers':
        return AdminPeoplePage(role: 'teacher', title: 'Teachers & batches');
      case 'staff':
        return AdminPeoplePage(role: 'staff', title: 'Staff');
      case 'admins':
        return AdminPeoplePage(role: 'admin', title: 'Admins');
      case 'attendance':
        if (user['role'] == 'teacher') return TeacherAttendancePage(user: user);
        if (user['role'] == 'staff') return StaffAttendancePage(user: user);
        return StudentAttendancePage(user: user);
      case 'myatt':
        return StaffAttendancePage(user: user, teacherView: true);
      case 'schedule':
        return SchedulePage(user: user);
      case 'home':
        return StudentHomePage(user: user);
      case 'profile':
        return ProfilePage(user: user);
      case 'settings':
        return SettingsPage(user: user);
      default:
        return Padding(
          padding: const EdgeInsets.all(22),
          child: EmptyState(
            title: 'Page not found',
            message: 'Choose a section from the menu.',
          ),
        );
    }
  }
}
