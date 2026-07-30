import 'package:flutter/material.dart';

import '../../../theme/theme_colors.dart';

/// White rounded group holding a set of rows, hairlines between them.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, required this.children, this.padding});

  final List<Widget> children;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: padding,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: 20,
                endIndent: 20,
                color: theme.colorScheme.outlineVariant,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Label on the left, current value on the right.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.label,
    this.value,
    this.onTap,
    this.destructive = false,
  });

  final String label;
  final String? value;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 19),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.headlineLarge!.copyWith(
                  color: destructive
                      ? context.palette.dangerInk
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
            if (value != null)
              Text(
                value!,
                style: theme.textTheme.headlineLarge!.copyWith(
                  color: context.palette.inkFaint,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Small uppercase caption above a card.
class SettingsSectionLabel extends StatelessWidget {
  const SettingsSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 0, 10),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall!.copyWith(
          letterSpacing: 1.5,
          color: context.palette.inkFaint,
        ),
      ),
    );
  }
}
