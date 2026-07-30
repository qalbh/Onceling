import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Six-slot entry for the partner's code.
///
/// A transparent [TextField] fills the tile so the platform keyboard, caret
/// movement and paste all work; the visible slots are painted underneath and
/// show a dot for every position not yet filled.
class PartnerCodeField extends StatefulWidget {
  const PartnerCodeField({
    super.key,
    required this.controller,
    this.length = 6,
    this.onChanged,
  });

  final TextEditingController controller;
  final int length;
  final ValueChanged<String>? onChanged;

  @override
  State<PartnerCodeField> createState() => _PartnerCodeFieldState();
}

class _PartnerCodeFieldState extends State<PartnerCodeField> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = widget.controller.text;

    return GestureDetector(
      onTap: _focusNode.requestFocus,
      child: Container(
        height: 62,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(
          children: [
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 12,
                children: [
                  for (var i = 0; i < widget.length; i++)
                    SizedBox(
                      width: 16,
                      child: Center(
                        child: i < value.length
                            ? Text(
                                value[i],
                                style: theme.textTheme.displayMedium,
                              )
                            : const _EmptySlotDot(),
                      ),
                    ),
                ],
              ),
            ),
            // Invisible but fully functional input layered over the slots.
            Positioned.fill(
              child: TextField(
                controller: widget.controller,
                focusNode: _focusNode,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                textAlign: TextAlign.center,
                showCursor: false,
                cursorColor: Colors.transparent,
                style: theme.textTheme.displayMedium!.copyWith(
                  color: Colors.transparent,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  counterText: '',
                  contentPadding: EdgeInsets.zero,
                ),
                maxLength: widget.length,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                  _UpperCaseFormatter(),
                ],
                onChanged: (text) {
                  setState(() {});
                  widget.onChanged?.call(text);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptySlotDot extends StatelessWidget {
  const _EmptySlotDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
