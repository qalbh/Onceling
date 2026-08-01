import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/pairing_code.dart';

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
                // NOT TextCapitalization.characters. That pins iOS to the
                // letters plane, which is why digits felt impossible to enter
                // even though the filter has always allowed them — and codes
                // are mostly alphanumeric, so it made most of them unusable.
                // The formatter below uppercases anyway, so forcing the
                // keyboard bought nothing and cost the digits.
                keyboardType: TextInputType.visiblePassword,
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
                // Order matters: uppercase first, then filter. That way a
                // typed 'w' becomes 'W' and survives, while a typed 'l'
                // becomes 'L' and is correctly rejected — L is not in the
                // alphabet and can never appear in a real code.
                inputFormatters: [
                  _UpperCaseFormatter(),
                  FilteringTextInputFormatter.allow(
                    RegExp('[$pairingCodeAlphabet]'),
                  ),
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
