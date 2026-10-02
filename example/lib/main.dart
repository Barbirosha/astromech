import 'package:astromech_driver/astromech_driver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const ExampleApp());
  // Debug builds only - a no-op in release.
  registerAstromech();
}

enum Status { open, done }

class Task {
  const Task(this.id, this.title, this.status);

  final int id;
  final String title;
  final Status status;
}

const tasks = [
  Task(1, 'Buy milk', Status.open),
  Task(2, 'Write report', Status.done),
  Task(3, 'Call Anna', Status.open),
  Task(4, 'Fix the bike', Status.done),
];

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(title: 'astromech example', home: TasksPage());
  }
}

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  Set<Status> _filter = {};

  Future<void> _openFilter() async {
    final chosen = await showModalBottomSheet<Set<Status>>(
      context: context,
      builder: (_) => FilterSheet(initial: _filter),
    );
    if (chosen != null) setState(() => _filter = chosen);
  }

  @override
  Widget build(BuildContext context) {
    final visible = tasks.where((t) => _filter.isEmpty || _filter.contains(t.status)).toList();
    final filterLabel = _filter.isEmpty
        ? 'Filter'
        : 'Filter: ${_filter.map((s) => s.name).join(', ')}';
    return Scaffold(
      appBar: AppBar(title: const Text('Tasks')),
      body: Column(
        children: [
          Semantics(
            identifier: 'filter_button',
            child: TextButton(onPressed: _openFilter, child: Text(filterLabel)),
          ),
          for (final task in visible)
            Semantics(
              identifier: 'task_${task.id}',
              child: ListTile(
                title: Text(task.title),
                trailing: Text(task.status.name),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => TaskPage(task: task)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Checkboxes under MergeSemantics: their ids are hidden from the OS
/// accessibility tree (so OS-level tools can't tap them), but not from astromech.
class FilterSheet extends StatefulWidget {
  const FilterSheet({required this.initial, super.key});

  final Set<Status> initial;

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late final Set<Status> _chosen = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final status in Status.values)
          MergeSemantics(
            child: Semantics(
              identifier: 'filter_${status.name}',
              child: CheckboxListTile(
                title: Text(status.name),
                value: _chosen.contains(status),
                onChanged: (on) =>
                    setState(() => (on ?? false) ? _chosen.add(status) : _chosen.remove(status)),
              ),
            ),
          ),
        Semantics(
          identifier: 'filter_apply',
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(_chosen),
            child: const Text('Apply'),
          ),
        ),
      ],
    );
  }
}

class TaskPage extends StatelessWidget {
  const TaskPage({required this.task, super.key});

  final Task task;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(task.title)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Semantics(
          identifier: 'note_input',
          child: TextField(
            decoration: const InputDecoration(labelText: 'Note (upper case)'),
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              TextInputFormatter.withFunction(
                (_, value) => value.copyWith(text: value.text.toUpperCase()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
