import 'package:go_router/go_router.dart';

import '../screens/home/home_screen.dart';

/// App-wide route table. Screens are added as the app grows.
final appRouter = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
  ],
);
