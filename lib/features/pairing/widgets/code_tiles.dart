import 'package:flutter/material.dart';

import '../../../theme/tandem_colors.dart';

/// The user's own pairing code, one sage tile per character.
class CodeTiles extends StatelessWidget {
  const CodeTiles({super.key, required this.code, this.spacing = 9});

  final String code;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: spacing,
      children: [
        for (final char in code.characters)
          Container(
            width: 40,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.tandem.tile,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Text(
              char,
              style: theme.textTheme.displayMedium!.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
      ],
    );
  }
}
