// Shared bottom-sheet chrome + form fields for all the editor sheets.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/symbols.dart';
import '../../theme.dart';

class EditorScaffold extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Future<void> Function() onSave;
  final Future<void> Function()? onDelete;
  const EditorScaffold({
    super.key,
    required this.title,
    required this.children,
    required this.onSave,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      decoration: BoxDecoration(
        color: pal.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border.all(color: pal.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: pal.line, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: TextStyle(
                          color: pal.textHi,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                ),
                if (onDelete != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: NqeColors.loss),
                    onPressed: onDelete,
                  ),
                IconButton(
                  icon: Icon(Icons.close, color: pal.textLo),
                  onPressed: () => Navigator.pop(context, false),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 6, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 16 + bottomInset),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onSave,
                child: const Text('Save'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EditorField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final int maxLines;
  final String? hint;
  final bool obscure;
  const EditorField({
    super.key,
    required this.label,
    required this.controller,
    this.keyboardType,
    this.maxLines = 1,
    this.hint,
    this.obscure = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: obscure ? 1 : maxLines,
        obscureText: obscure,
        decoration: InputDecoration(labelText: label, hintText: hint),
      ),
    );
  }
}

/// A searchable "Stock code" field: type a ticker or company name and pick from
/// live suggestions (bundled catalogue). Free-text is still allowed — any symbol
/// not in the list can be typed and saved as-is. Wraps an externally-owned
/// [controller] so the parent editor keeps ownership of the value.
class EditorSymbolField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  const EditorSymbolField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
  });

  @override
  State<EditorSymbolField> createState() => _EditorSymbolFieldState();
}

class _EditorSymbolFieldState extends State<EditorSymbolField> {
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RawAutocomplete<StockSymbol>(
        textEditingController: widget.controller,
        focusNode: _focus,
        optionsBuilder: (TextEditingValue v) => searchSymbols(v.text),
        displayStringForOption: (s) => s.code,
        onSelected: (s) {
          widget.controller.text = s.code;
          _focus.unfocus();
        },
        fieldViewBuilder: (context, controller, focusNode, onSubmit) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              TextInputFormatter.withFunction((oldV, newV) =>
                  newV.copyWith(text: newV.text.toUpperCase())),
            ],
            decoration: InputDecoration(
              labelText: widget.label,
              hintText: widget.hint ?? 'Search e.g. SM, BDO, Jollibee',
              suffixIcon: Icon(Icons.search, size: 18, color: pal.textLo),
            ),
            onSubmitted: (_) => onSubmit(),
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          final width = MediaQuery.of(context).size.width - 40;
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              color: pal.surface,
              elevation: 6,
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(maxHeight: 280, maxWidth: width > 0 ? width : 360),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, i) {
                    final s = options.elementAt(i);
                    return ListTile(
                      dense: true,
                      title: Text(s.code,
                          style: TextStyle(
                              color: pal.textHi, fontWeight: FontWeight.w700)),
                      subtitle: Text(s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: pal.textLo, fontSize: 12)),
                      trailing: Text(s.market,
                          style: TextStyle(color: pal.textLo, fontSize: 11)),
                      onTap: () => onSelected(s),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class EditorDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> items;
  final ValueChanged<T?> onChanged;
  final String Function(T)? display;
  const EditorDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.display,
  });

  @override
  Widget build(BuildContext context) {
    // Match EditorField's bottom spacing so fields line up when side-by-side.
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<T>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: items
            .map((e) => DropdownMenuItem<T>(
                  value: e,
                  child: Text(display?.call(e) ?? e.toString()),
                ))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}

Future<bool> confirmDelete(
    BuildContext context, String title, String message) async {
  final pal = context.nqe;
  final res = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: pal.surface,
      title: Text(title, style: TextStyle(color: pal.textHi)),
      content: Text(message, style: TextStyle(color: pal.textLo)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: NqeColors.loss),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return res ?? false;
}

class DatePickerField extends StatelessWidget {
  final String label;
  final String isoDate;
  final ValueChanged<String> onChanged;
  const DatePickerField({
    super.key,
    required this.label,
    required this.isoDate,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final pal = context.nqe;
    final d = DateTime.tryParse(isoDate) ?? DateTime.now();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: d,
            firstDate: DateTime(2015),
            lastDate: DateTime(2100),
          );
          if (picked != null) {
            onChanged(picked.toIso8601String().substring(0, 10));
          }
        },
        child: InputDecorator(
          decoration: InputDecoration(labelText: label),
          child: Row(
            children: [
              Icon(Icons.calendar_today, size: 16, color: pal.textLo),
              const SizedBox(width: 10),
              Text(isoDate,
                  style: TextStyle(color: pal.textHi, fontSize: 15)),
            ],
          ),
        ),
      ),
    );
  }
}
