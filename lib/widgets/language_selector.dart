import 'package:flutter/material.dart';

import '../services/localization_service.dart';

class LanguageSelector extends StatefulWidget {
  final Function(String)? onLanguageChanged;

  const LanguageSelector({super.key, this.onLanguageChanged});

  @override
  State<LanguageSelector> createState() => _LanguageSelectorState();
}

class _LanguageSelectorState extends State<LanguageSelector> {
  final LocalizationService _localizationService = LocalizationService();

  @override
  void initState() {
    super.initState();
    _localizationService.addListener(_handleLanguageChanged);
  }

  @override
  void dispose() {
    _localizationService.removeListener(_handleLanguageChanged);
    super.dispose();
  }

  void _handleLanguageChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.language, color: colorScheme.onSurface, size: 20),
          const SizedBox(width: 4),
          Text(
            _localizationService.currentLanguage.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      onSelected: (String languageCode) async {
        await _localizationService.setLanguage(languageCode);
        if (!mounted) return;
        widget.onLanguageChanged?.call(languageCode);
      },
      itemBuilder: (BuildContext context) {
        return _localizationService.getAvailableLanguages().map((language) {
          final isSelected =
              _localizationService.currentLanguage == language['code'];
          return PopupMenuItem<String>(
            value: language['code'],
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: isSelected
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainerHighest,
                  child: Text(
                    language['flag']!,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: isSelected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  language['name']!,
                  style: TextStyle(
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurface,
                  ),
                ),
                if (isSelected) ...[
                  const Spacer(),
                  Icon(Icons.check, color: colorScheme.primary, size: 18),
                ],
              ],
            ),
          );
        }).toList();
      },
      tooltip: _localizationService.tr('change_language'),
    );
  }
}

/// Widget pour afficher le sélecteur de langue dans une liste
class LanguageListTile extends StatefulWidget {
  final Function(String)? onLanguageChanged;

  const LanguageListTile({super.key, this.onLanguageChanged});

  @override
  State<LanguageListTile> createState() => _LanguageListTileState();
}

class _LanguageListTileState extends State<LanguageListTile> {
  final LocalizationService _localizationService = LocalizationService();

  @override
  void initState() {
    super.initState();
    _localizationService.addListener(_handleLanguageChanged);
  }

  @override
  void dispose() {
    _localizationService.removeListener(_handleLanguageChanged);
    super.dispose();
  }

  void _handleLanguageChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _showLanguageDialog() {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(_localizationService.tr('change_language')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: _localizationService.getAvailableLanguages().map((
              language,
            ) {
              final isSelected =
                  _localizationService.currentLanguage == language['code'];
              return ListTile(
                leading: Text(
                  language['flag']!,
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                title: Text(language['name']!),
                trailing: isSelected
                    ? Icon(Icons.check, color: colorScheme.primary)
                    : null,
                onTap: () async {
                  await _localizationService.setLanguage(language['code']!);
                  if (!mounted) return;
                  widget.onLanguageChanged?.call(language['code']!);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(_localizationService.tr('cancel')),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentLanguage = _localizationService
        .getAvailableLanguages()
        .firstWhere(
          (lang) => lang['code'] == _localizationService.currentLanguage,
        );

    return ListTile(
      leading: const Icon(Icons.language),
      title: Text(_localizationService.tr('language')),
      subtitle: Text(currentLanguage['name']!),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(currentLanguage['flag']!, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          const Icon(Icons.arrow_forward_ios, size: 16),
        ],
      ),
      onTap: _showLanguageDialog,
    );
  }
}
