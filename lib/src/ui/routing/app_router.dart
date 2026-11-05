import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../services/app_events.dart';
import '../../state/providers.dart';
import '../screens/archive/archive_screen.dart';
import '../screens/details/reminder_details_screen.dart';
import '../screens/editor/editor_controller.dart';
import '../screens/editor/reminder_editor_screen.dart';
import '../screens/home/home_screen.dart';

/// Routes:
/// - `/` reminder list
/// - `/new` editor for a new reminder
/// - `/archive` archived reminders
/// - `/reminder/:id` details (also the deep link from widgets and
///   notifications)
/// - `/reminder/:id/edit` editor; `?mode=restore` restores with changes
///
/// Widget and notification links never reach the router as platform
/// routes: Flutter's deep linking is off (AndroidManifest, Info.plist), and
/// `SyncScope` navigates for them. When a widget or notification launched
/// the app, the router starts at its reminder, so neither the home screen
/// nor an error page shows first.
final routerProvider = Provider<GoRouter>((ref) {
  final launch = ref.watch(appEventsProvider).launchEvent;
  final router = GoRouter(
    initialLocation: switch (launch) {
      OpenReminder(:final reminderId) => reminderLocation(reminderId),
      _ => '/',
    },
    overridePlatformDefaultLocation: true,
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const HomeScreen(),
        routes: [
          GoRoute(
            path: 'new',
            pageBuilder: (_, state) => MaterialPage(
              key: state.pageKey,
              fullscreenDialog: true,
              child: const ReminderEditorScreen(
                target: (mode: EditorMode.create, reminderId: null),
              ),
            ),
          ),
          GoRoute(
            path: 'archive',
            builder: (_, _) => const ArchiveScreen(),
          ),
          GoRoute(
            path: 'reminder/:id',
            builder: (_, state) => ReminderDetailsScreen(
              reminderId: state.pathParameters['id']!,
            ),
            routes: [
              GoRoute(
                path: 'edit',
                pageBuilder: (_, state) => MaterialPage(
                  key: state.pageKey,
                  fullscreenDialog: true,
                  child: ReminderEditorScreen(
                    target: (
                      mode: state.uri.queryParameters['mode'] == 'restore'
                          ? EditorMode.restore
                          : EditorMode.edit,
                      reminderId: state.pathParameters['id']!,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// The details screen of a reminder.
String reminderLocation(String reminderId) => '/reminder/$reminderId';
