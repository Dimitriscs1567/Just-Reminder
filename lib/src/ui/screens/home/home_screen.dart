import 'package:material_ui/material_ui.dart';

/// Placeholder home screen; replaced by the reminder list in the UI step.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Just Reminder')),
      body: const Center(child: Text('No reminders yet')),
    );
  }
}
