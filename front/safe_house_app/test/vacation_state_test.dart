// Covers the vacation-state handling on the Profile screen: that a pause is
// tracked per house rather than globally, that the screen redraws when the
// state moves underneath it, and that editing a trip already under way opens
// the date picker instead of tripping its assertions.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:safe_house_app/services/auth_state.dart';
import 'package:safe_house_app/screens/customer/profile_screen.dart';

Map<String, dynamic> _house(String id, String name,
        {bool vacation = false, Map<String, dynamic>? schedule}) =>
    {
      'house_id': id,
      'resident_name': name,
      'address': '$name St',
      'is_vacation': vacation,
      'sensor_mask': [1, 1, 1, 1, 1, 1, 1],
      'vacation_schedule': ?schedule,
    };

/// A trip that started yesterday and runs for three more days — the state that
/// keeps a start date in the past for the whole of its duration.
Map<String, dynamic> _runningTrip() {
  final start = DateTime.now().subtract(const Duration(days: 1));
  final end = DateTime.now().add(const Duration(days: 3));
  String d(DateTime x) =>
      '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
  return {
    'startDate': d(start), 'startTime': '09:00',
    'endDate': d(end), 'endTime': '17:00',
    'startUtc': DateTime(start.year, start.month, start.day, 9)
        .toUtc()
        .toIso8601String(),
    'endUtc':
        DateTime(end.year, end.month, end.day, 17).toUtc().toIso8601String(),
  };
}

/// The profile page is far taller than the default 800x600 test surface, and
/// widgets below the fold are not hit-testable. A tall viewport puts the whole
/// card on screen so taps land where they would on a scrolled phone.
Future<void> _pumpProfile(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final tab = ValueNotifier<int>(3);
  addTearDown(tab.dispose);
  await tester.pumpWidget(MaterialApp(
    home: ProfileScreen(activeTab: tab, tabIndex: 3),
  ));
  await tester.pump();
}

Future<void> _signIn(List<Map<String, dynamic>> houses) async {
  await AuthState.instance.clear();
  AuthState.instance.setUser({
    'user_id': 'u1',
    'username': 'mara_r',
    'email': 'mara@family.com',
    'role': 'user',
    'houses': houses,
  });
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('vacation mode is per house', () {
    test('a pause on one house does not follow you to another', () async {
      await _signIn([_house('h1', 'Eleanor'), _house('h2', 'Walter')]);
      await AuthState.instance.setActiveHouse('h1');

      await AuthState.instance.setVacationMode(true);
      expect(AuthState.instance.vacationMode.value, isTrue);

      await AuthState.instance.setActiveHouse('h2');
      expect(AuthState.instance.vacationMode.value, isFalse,
          reason: "h2 is not on vacation — h1's pause must not carry over");

      await AuthState.instance.setActiveHouse('h1');
      expect(AuthState.instance.vacationMode.value, isTrue,
          reason: 'switching back restores h1\'s own state');
    });

    test('a switch adopts what the server last said about that house', () async {
      await _signIn([
        _house('h1', 'Eleanor'),
        _house('h2', 'Walter', vacation: true),
      ]);
      await AuthState.instance.setActiveHouse('h1');
      expect(AuthState.instance.vacationMode.value, isFalse);

      await AuthState.instance.setActiveHouse('h2');
      expect(AuthState.instance.vacationMode.value, isTrue,
          reason: 'h2 arrived from /me already flagged as on vacation');
    });

    test('the flag survives a restart, per house', () async {
      await _signIn([_house('h1', 'Eleanor'), _house('h2', 'Walter')]);
      await AuthState.instance.setActiveHouse('h2');
      await AuthState.instance.setVacationMode(true);

      // Simulate a cold start: state object reset, prefs intact.
      AuthState.instance.vacationMode.value = false;
      await AuthState.instance.loadFromStorage();
      expect(AuthState.instance.vacationMode.value, isTrue);
    });

    test('signing out clears every cached house', () async {
      await _signIn([_house('h1', 'Eleanor'), _house('h2', 'Walter')]);
      await AuthState.instance.setActiveHouse('h1');
      await AuthState.instance.setVacationMode(true);
      await AuthState.instance.setActiveHouse('h2');
      await AuthState.instance.setVacationMode(true);

      await AuthState.instance.clear();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.startsWith('vacation_mode')),
          isEmpty);
      expect(AuthState.instance.vacationMode.value, isFalse);
    });
  });

  group('the toggle tracks state it does not own', () {
    testWidgets('a pause started elsewhere redraws the card', (tester) async {
      await _signIn([_house('h1', 'Eleanor')]);
      await AuthState.instance.setActiveHouse('h1');

      await _pumpProfile(tester);
      expect(find.text('Monitoring active'), findsOneWidget);

      // What the dashboard's poll does when the server's scheduler starts a
      // trip: the Profile tab is alive but unbuilt, and must notice anyway.
      await AuthState.instance.setVacationMode(true);
      await tester.pump();

      expect(find.text('Monitoring paused — vacation mode is on'),
          findsOneWidget);
      expect(find.text('Monitoring active'), findsNothing);
    });
  });

  group('a trip already under way', () {
    testWidgets('presents as running, not as a manual pause', (tester) async {
      await _signIn(
          [_house('h1', 'Eleanor', vacation: true, schedule: _runningTrip())]);
      await AuthState.instance.setActiveHouse('h1');

      await _pumpProfile(tester);

      expect(find.text('Trip in progress'), findsOneWidget);
      expect(find.text('Paused · scheduled'), findsOneWidget);
      expect(find.text('End trip now'), findsOneWidget);
      expect(find.textContaining('Monitoring paused — trip ends'),
          findsOneWidget);
    });

    testWidgets('opens the date picker instead of asserting', (tester) async {
      await _signIn(
          [_house('h1', 'Eleanor', vacation: true, schedule: _runningTrip())]);
      await AuthState.instance.setActiveHouse('h1');

      await _pumpProfile(tester);

      // .last — the first 'Edit' belongs to the Username row above.
      await tester.tap(find.text('Edit').last);
      await tester.pumpAndSettle();

      // The start date is in the past; before the fix showDatePicker asserted
      // initialDate >= firstDate and threw the moment this was tapped.
      await tester.tap(find.byIcon(Icons.calendar_today_outlined).first);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(DatePickerDialog), findsOneWidget);
    });
  });

  group('a future trip', () {
    testWidgets('reads as scheduled, with monitoring still live',
        (tester) async {
      final start = DateTime.now().add(const Duration(days: 5));
      final end = DateTime.now().add(const Duration(days: 9));
      String d(DateTime x) =>
          '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
      await _signIn([
        _house('h1', 'Eleanor', schedule: {
          'startDate': d(start), 'startTime': '09:00',
          'endDate': d(end), 'endTime': '17:00',
        })
      ]);
      await AuthState.instance.setActiveHouse('h1');

      await _pumpProfile(tester);

      expect(find.text('Trip scheduled'), findsOneWidget);
      expect(find.text('Scheduled'), findsOneWidget);
      expect(find.text('Monitoring active · scheduled trip ahead'),
          findsOneWidget);
      expect(find.text('Cancel trip'), findsOneWidget);
    });
  });
}
