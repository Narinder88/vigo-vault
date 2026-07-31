import 'package:flutter/material.dart';

Future<String?> showRenameLockDialog({
  required BuildContext context,
  required String initialName,
  String title = 'Rename Lock',
  Color backgroundColor = const Color(0xFF2C2D31),
  Color labelColor = const Color(0xFFFFFFFF),
  Color subtextColor = const Color(0xFF9E9E9E),
  Color accentColor = const Color(0xFF00E676),
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: true,
    useRootNavigator: true,
    builder: (dialogContext) {
      return _RenameLockDialog(
        initialName: initialName,
        title: title,
        backgroundColor: backgroundColor,
        labelColor: labelColor,
        subtextColor: subtextColor,
        accentColor: accentColor,
      );
    },
  );
}

class _RenameLockDialog extends StatefulWidget {
  const _RenameLockDialog({
    required this.initialName,
    required this.title,
    required this.backgroundColor,
    required this.labelColor,
    required this.subtextColor,
    required this.accentColor,
  });

  final String initialName;
  final String title;
  final Color backgroundColor;
  final Color labelColor;
  final Color subtextColor;
  final Color accentColor;

  @override
  State<_RenameLockDialog> createState() => _RenameLockDialogState();
}

class _RenameLockDialogState extends State<_RenameLockDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: widget.backgroundColor,
      title: Text(
        widget.title,
        style: TextStyle(color: widget.labelColor),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        style: TextStyle(color: widget.labelColor),
        decoration: InputDecoration(
          hintText: 'Lock name',
          hintStyle: TextStyle(
            color: widget.subtextColor.withValues(alpha: 0.8),
          ),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(
              color: widget.subtextColor.withValues(alpha: 0.5),
            ),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: widget.accentColor),
          ),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: TextStyle(
              color: widget.subtextColor.withValues(alpha: 0.9),
            ),
          ),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            backgroundColor: widget.accentColor,
            foregroundColor: widget.backgroundColor,
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
