enum AppRole { admin, teacher, staff, student, guardian, unknown }

extension AppRoleValue on AppRole {
  String get value => switch (this) {
    AppRole.admin => 'admin',
    AppRole.teacher => 'teacher',
    AppRole.staff => 'staff',
    AppRole.student => 'student',
    AppRole.guardian => 'guardian',
    AppRole.unknown => 'student',
  };
}

AppRole parseRole(Object? value) => switch (value?.toString()) {
  'admin' => AppRole.admin,
  'teacher' => AppRole.teacher,
  'staff' => AppRole.staff,
  'student' => AppRole.student,
  'guardian' => AppRole.guardian,
  _ => AppRole.unknown,
};
