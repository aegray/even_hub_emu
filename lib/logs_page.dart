import 'package:flutter/material.dart';

class LogsPage extends StatelessWidget {
  const LogsPage({
    super.key,
    required this.consoleLines,
    required this.errorLines,
  });

  final List<String> consoleLines;
  final List<String> errorLines;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Logs'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Console'),
              Tab(text: 'Errors'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildList(consoleLines),
            _buildList(errorLines),
          ],
        ),
      ),
    );
  }

  Widget _buildList(List<String> lines) {
    return ListView.builder(
      itemCount: lines.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: SelectableText(
            lines[index],
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        );
      },
    );
  }
}
