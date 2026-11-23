/// Asking why something is being reported: a reason and optional details.
library;

import 'package:material_ui/material_ui.dart';

/// Pops with the reason (and details, as `reason: details`), or null.
class ReportDialog extends StatefulWidget {
  const ReportDialog({
    required this.title,
    required this.explanation,
    super.key,
  });

  final String title;
  final String explanation;

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  static const _reasons = [
    'Nudity or sexual content',
    'Harassment or hate',
    'Violence or threats',
    'Spam or scam',
    'Something else',
  ];
  String? _reason;
  final _details = TextEditingController();

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.explanation),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: _reason,
              onChanged: (v) => setState(() => _reason = v),
              child: Column(
                children: [
                  for (final r in _reasons)
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      title: Text(r),
                      value: r,
                    ),
                ],
              ),
            ),
            TextField(
              controller: _details,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Details (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _reason == null
              ? null
              : () => Navigator.pop(
                  context,
                  [
                    _reason!,
                    _details.text.trim(),
                  ].where((s) => s.isNotEmpty).join(': '),
                ),
          child: const Text('Report'),
        ),
      ],
    );
  }
}
