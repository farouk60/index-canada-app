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
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.language, color: Colors.white, size: 20),
          const SizedBox(width: 4),
          Text(
            _localizationService.currentLanguage.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      onSelected: (String languageCode) async {
        await _localizationService.setLanguage(languageCode);
        if (widget.onLanguageChanged != null) {
          widget.onLanguageChanged!(languageCode);
        }
        if (mounted) {
          setState(() {});
        }
      },
      itemBuilder: (BuildContext context) {
        return _localizationService.getAvailableLanguages().map((language) {
          final isSelected =
              _localizationService.currentLanguage == language['code'];
          return PopupMenuItem<String>(
            value: language['code'],
            child: Row(
              children: [
                Text(language['flag']!, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                Text(
                  language['name']!,
                  style: TextStyle(
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: isSelected ? Colors.blue : Colors.black,
                  ),
                ),
                if (isSelected) ...[
                  const Spacer(),
                  const Icon(Icons.check, color: Colors.blue, size: 16),
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

  void _showLanguageDialog() {
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
                  style: const TextStyle(fontSize: 24),
                ),
                title: Text(language['name']!),
                trailing: isSelected
                    ? const Icon(Icons.check, color: Colors.blue)
                    : null,
                onTap: () async {
                  await _localizationService.setLanguage(language['code']!);
                  if (widget.onLanguageChanged != null) {
                    widget.onLanguageChanged!(language['code']!);
                  }
                  if (mounted) {
                    setState(() {});
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
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
