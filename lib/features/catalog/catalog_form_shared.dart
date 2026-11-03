import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/permissions.dart';
import '../../core/sync/connectivity.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/manager_override.dart';

/// Manager + online gate shared by Add Prod. / Add Vt's. sidebar tabs and Options.
Future<bool> ensureCanAddProduct(BuildContext context, WidgetRef ref) async {
  if (!await requirePermission(context, ref, Perm.createCatalogProduct) || !context.mounted) return false;
  if (!ref.read(onlineProvider)) {
    showMessage(context, 'Adding a product needs an online connection.', error: true);
    return false;
  }
  return true;
}

class CatalogSectionTitle extends StatelessWidget {
  const CatalogSectionTitle({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.2),
      ),
    );
  }
}

/// Red asterisk marker for fields that fail validation when empty.
Widget catalogRequiredStar([TextStyle? style]) => Text(
      ' *',
      style: (style ?? const TextStyle()).copyWith(color: ZaamColors.red, fontWeight: FontWeight.w700),
    );

/// Label widget for [InputDecoration.label] / list titles: `Name` + red `*`.
Widget catalogRequiredLabel(String text, {TextStyle? style}) => Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: text),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: catalogRequiredStar(style),
          ),
        ],
      ),
    );

class CatalogDefaultsStrip extends StatelessWidget {
  const CatalogDefaultsStrip({super.key, required this.chips});
  final List<CatalogDefaultChip> chips;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark ? ZaamColors.charcoal : const Color(0xFFF5EADA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ZaamColors.gold.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Using',
            style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: chips),
        ],
      ),
    );
  }
}

class CatalogDefaultChip extends StatelessWidget {
  const CatalogDefaultChip({super.key, required this.label, required this.isDefault, this.onTap});
  final String label;
  final bool isDefault;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = isDefault
        ? (theme.brightness == Brightness.dark ? ZaamColors.gold.withValues(alpha: 0.22) : Colors.white)
        : theme.colorScheme.surfaceContainerHighest;
    final border = isDefault ? ZaamColors.gold.withValues(alpha: 0.45) : theme.dividerColor;
    return Material(
      color: bg,
      shape: StadiumBorder(side: BorderSide(color: border)),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(label, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w500)),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isDefault
                      ? ZaamColors.gold.withValues(alpha: 0.18)
                      : theme.colorScheme.tertiaryContainer.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  isDefault ? 'Default' : 'Custom',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDefault ? theme.colorScheme.primary : theme.colorScheme.onTertiaryContainer,
                  ),
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 2),
                Icon(Icons.expand_more, size: 18, color: theme.colorScheme.onSurfaceVariant),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class CatalogErrorBanner extends StatelessWidget {
  const CatalogErrorBanner({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class CatalogHintBanner extends StatelessWidget {
  const CatalogHintBanner({super.key, required this.message, required this.actionLabel, this.onAction});
  final String message;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSecondaryContainer),
            ),
          ),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
