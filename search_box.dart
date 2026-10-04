import 'package:flutter/material.dart';

/// Type-ahead box: type part of a value (words in any order), pick from the
/// list. [v] shows the whole list, [x] clears. Same behaviour as the desktop
/// version, but the list opens inline under the field (better on a phone).
class SearchBox extends StatefulWidget {
  const SearchBox({
    super.key,
    required this.label,
    required this.getOptions,
    required this.onChanged,
  });

  final String label;
  final List<String> Function() getOptions;
  final VoidCallback onChanged;

  @override
  State<SearchBox> createState() => SearchBoxState();
}

class SearchBoxState extends State<SearchBox> {
  static const int maxShown = 300;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  /// Committed selection (null = nothing picked).
  String? value;

  bool _open = false;
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  // ---- public helpers -------------------------------------------------------
  /// Clear without notifying (used by Clear All / file switch).
  void reset() {
    _controller.clear();
    setState(() {
      value = null;
      _open = false;
      _showAll = false;
    });
  }

  void clear() {
    final had = value != null;
    reset();
    if (had) widget.onChanged();
    _focus.requestFocus();
  }

  // ---- internals --------------------------------------------------------------
  void _onFocus() {
    if (_focus.hasFocus) {
      setState(() {
        _open = true;
        _showAll = value != null;
      });
    } else {
      Future.delayed(const Duration(milliseconds: 200), _finalize);
    }
  }

  void _onText(String text) {
    if (value != null && text != value) {
      value = null;
      widget.onChanged();
    }
    setState(() {
      _open = true;
      _showAll = false;
    });
  }

  void _commit(String v) {
    _controller.text = v;
    _controller.selection = TextSelection.collapsed(offset: v.length);
    setState(() {
      value = v;
      _open = false;
      _showAll = false;
    });
    _focus.unfocus();
    widget.onChanged();
  }

  /// Called when the box loses focus: accept exact text or revert.
  void _finalize() {
    if (!mounted || _focus.hasFocus) return;
    if (value == null) {
      final text = _controller.text.trim().toLowerCase();
      if (text.isNotEmpty) {
        final exact =
            widget.getOptions().where((o) => o.toLowerCase() == text).toList();
        if (exact.isNotEmpty) {
          _commit(exact.first);
          return;
        }
        _controller.clear();
      }
    } else {
      _controller.text = value!;
    }
    setState(() => _open = false);
  }

  List<String> _filtered() {
    final options = widget.getOptions();
    final tokens = _controller.text
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (_showAll || tokens.isEmpty) return options;
    final hits = options.where((o) {
      final l = o.toLowerCase();
      return tokens.every((t) => l.contains(t));
    }).toList();
    final first = tokens.first;
    return [
      ...hits.where((o) => o.toLowerCase().startsWith(first)),
      ...hits.where((o) => !o.toLowerCase().startsWith(first)),
    ];
  }

  void _arrowClick() {
    if (_open && _focus.hasFocus) {
      setState(() => _open = false);
    } else {
      setState(() {
        _open = true;
        _showAll = true;
      });
      _focus.requestFocus();
    }
  }

  void _submit(String _) {
    final items = _filtered();
    if (items.isNotEmpty) {
      _commit(items.first);
    } else {
      _finalize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _open ? _filtered() : const <String>[];
    final extra = items.length - maxShown;
    final shown = items.length > maxShown ? items.sublist(0, maxShown) : items;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                onChanged: _onText,
                onSubmitted: _submit,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: widget.label,
                  isDense: true,
                  border: const OutlineInputBorder(),
                  filled: value != null,
                  fillColor: theme.colorScheme.primaryContainer,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Show all',
              onPressed: _arrowClick,
              icon: Icon(_open
                  ? Icons.keyboard_arrow_up
                  : Icons.keyboard_arrow_down),
            ),
            IconButton(
              tooltip: 'Clear',
              onPressed: clear,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        if (_open && shown.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 2, right: 8),
            constraints: const BoxConstraints(maxHeight: 240),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border.all(color: theme.colorScheme.outline),
              borderRadius: BorderRadius.circular(4),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: shown.length + (extra > 0 ? 1 : 0),
              itemBuilder: (context, i) {
                if (i >= shown.length) {
                  return Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      '... $extra more - keep typing to narrow down',
                      style: TextStyle(color: theme.hintColor),
                    ),
                  );
                }
                return InkWell(
                  onTap: () => _commit(shown[i]),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 11),
                    child: Text(shown[i]),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
