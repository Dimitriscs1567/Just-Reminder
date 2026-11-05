import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:material_ui/material_ui.dart';

import '../../../services/widget/widget_bridge.dart';
import '../../../services/widget/widget_snapshot.dart';
import '../../components/empty_state.dart';
import '../../components/status_icon.dart';
import 'widget_setup_app.dart';

/// Android: picks the reminders a list widget shows, in the order they are
/// ticked (drag to change it). Runs in its own activity and engine, opened
/// by the launcher when the widget is added or set up again (and by
/// tapping an archived or deleted row).
class ListWidgetConfigurationApp extends StatelessWidget {
  const ListWidgetConfigurationApp({required this.appWidgetId, super.key});

  final int appWidgetId;

  @override
  Widget build(BuildContext context) => WidgetSetupApp(
    title: 'Choose reminders',
    home: ListWidgetConfigurationScreen(appWidgetId: appWidgetId),
  );
}

class ListWidgetConfigurationScreen extends StatefulWidget {
  const ListWidgetConfigurationScreen({
    required this.appWidgetId,
    this.bridge = const WidgetBridge(),
    this.onFinished = HomeWidget.finishHomeWidgetConfigure,
    super.key,
  });

  final int appWidgetId;
  final WidgetBridge bridge;

  /// Called after saving: hands the widget back to the launcher.
  final Future<void> Function() onFinished;

  @override
  State<ListWidgetConfigurationScreen> createState() =>
      _ListWidgetConfigurationScreenState();
}

/// A reminder that is or can be on the widget.
class _Choice {
  const _Choice({
    required this.id,
    required this.name,
    required this.displayName,
    required this.status,
  });

  final String id;
  final String name;
  final String displayName;
  final WidgetStatus status;

  /// Archived or deleted: it stays on the widget until it is unticked, but
  /// can't be picked again.
  bool get isGone =>
      status.kind == WidgetStatusKind.archived ||
      status.kind == WidgetStatusKind.deleted;
}

class _ListWidgetConfigurationScreenState
    extends State<ListWidgetConfigurationScreen> {
  /// Every reminder that can be listed, by id, in the app's order.
  Map<String, _Choice>? _choices;

  /// The ids on the widget, in its order.
  final _picked = <String>[];

  /// The widget was set up before (Save) or is being added (Add widget).
  bool _existing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bridge = widget.bridge;
    final now = DateTime.now();
    final picked = await bridge.readAndroidList(widget.appWidgetId);
    final choices = <String, _Choice>{};
    for (final entry in await bridge.readIndex()) {
      if (entry.archived && !picked.contains(entry.id)) continue;
      final snapshot = await bridge.readSnapshot(entry.id);
      choices[entry.id] = _Choice(
        id: entry.id,
        name: entry.name,
        displayName: entry.displayName,
        status: snapshot != null
            ? widgetStatusAt(snapshot, now)
            : WidgetStatus(
                entry.archived
                    ? WidgetStatusKind.archived
                    : WidgetStatusKind.done,
              ),
      );
    }
    // Deleted since it was picked: its tombstone still has the names.
    for (final id in picked) {
      if (choices.containsKey(id)) continue;
      final snapshot = await bridge.readSnapshot(id);
      choices[id] = _Choice(
        id: id,
        name: snapshot?['name'] as String? ?? '',
        displayName: snapshot?['displayName'] as String? ?? '',
        status: const WidgetStatus(WidgetStatusKind.deleted),
      );
    }
    if (!mounted) return;
    setState(() {
      _choices = choices;
      _picked.addAll(picked.toSet());
      _existing = picked.isNotEmpty;
    });
  }

  void _toggle(String id) => setState(() {
    if (!_picked.remove(id)) _picked.add(id);
  });

  /// [to] is the index after removing it from [from].
  void _reorder(int from, int to) => setState(() {
    _picked.insert(to, _picked.removeAt(from));
  });

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.bridge.assignAndroidList(widget.appWidgetId, List.of(_picked));
    await widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final choices = _choices;
    final ready = choices != null && choices.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(onPressed: SystemNavigator.pop),
        title: const Text('Choose reminders'),
      ),
      body: switch (choices) {
        null => const Center(child: CircularProgressIndicator()),
        final all when all.isEmpty => const EmptyState(
          icon: Icons.widgets_outlined,
          title: 'No reminders yet',
          message:
              'Create a reminder in Just Reminder first, then add the widget '
              'again.',
          action: FilledButton(
            onPressed: SystemNavigator.pop,
            child: Text('Close'),
          ),
        ),
        final all => _list(context, all),
      },
      bottomNavigationBar: ready
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: _picked.isEmpty || _saving ? null : _save,
                  child: Text(_existing ? 'Save' : 'Add widget'),
                ),
              ),
            )
          : null,
    );
  }

  Widget _list(BuildContext context, Map<String, _Choice> choices) {
    final theme = Theme.of(context);
    final picked = [for (final id in _picked) choices[id]!];
    final others = [
      for (final choice in choices.values)
        if (!_picked.contains(choice.id) && !choice.isGone) choice,
    ];
    Widget header(String text) => SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      sliver: SliverToBoxAdapter(
        child: Text(
          text,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          sliver: SliverToBoxAdapter(
            child: Text(
              'Tick the reminders to show. The widget lists them in the '
              'order you tick them; drag to change it. When one is due, tap '
              'its thumbs-up on the widget to mark it done.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        if (picked.isNotEmpty) ...[
          header('On the widget'),
          SliverReorderableList(
            itemCount: picked.length,
            onReorderItem: _reorder,
            proxyDecorator: (child, index, animation) => Material(
              elevation: 4,
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(12),
              child: child,
            ),
            itemBuilder: (context, index) => _tile(
              context,
              picked[index],
              key: ValueKey(picked[index].id),
              position: index,
            ),
          ),
        ],
        if (others.isNotEmpty) ...[
          header(picked.isEmpty ? 'Reminders' : 'More reminders'),
          SliverList.list(
            children: [
              for (final choice in others)
                _tile(context, choice, key: ValueKey(choice.id)),
            ],
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }

  /// A reminder; [position] is its place on the widget (null: not on it).
  Widget _tile(
    BuildContext context,
    _Choice choice, {
    required Key key,
    int? position,
  }) {
    final picked = position != null;
    return ListTile(
      key: key,
      enabled: !_saving,
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      leading: StatusIcon(
        kind: widgetStatusIconKind(choice.status.kind),
        size: 36,
      ),
      title: Text(
        choice.displayName.isEmpty ? 'Deleted reminder' : choice.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        switch (choice.status.kind) {
          WidgetStatusKind.archived => 'Archived',
          WidgetStatusKind.deleted => 'Deleted',
          _ => choice.name,
        },
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => _toggle(choice.id),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: picked,
            onChanged: _saving ? null : (_) => _toggle(choice.id),
          ),
          if (position != null)
            ReorderableDragStartListener(
              index: position,
              enabled: !_saving,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(
                  Icons.drag_handle_rounded,
                  semanticLabel: 'Drag to reorder',
                ),
              ),
            ),
        ],
      ),
    );
  }
}
