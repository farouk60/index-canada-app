import 'package:flutter/material.dart';

import '../data_service.dart';
import '../services/localization_service.dart';
import '../services/review_verification_service.dart';
import '../widgets/language_selector.dart';

class AddReviewPage extends StatefulWidget {
  final String professionnelId;

  const AddReviewPage({super.key, required this.professionnelId});

  @override
  State<AddReviewPage> createState() => _AddReviewPageState();
}

class _AddReviewPageState extends State<AddReviewPage> {
  final LocalizationService _localizationService = LocalizationService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  int _selectedRating = 0;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submitReview() async {
    if (!_formKey.currentState!.validate() || _selectedRating == 0) {
      if (_selectedRating == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_localizationService.tr('select_rating')),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final verificationService = ReviewVerificationService();
      final verificationResult = await verificationService.canPostReview(
        widget.professionnelId,
        _nameController.text,
        _messageController.text,
        _titleController.text,
      );

      if (!verificationResult.canPost) {
        if (mounted) {
          Color backgroundColor;
          switch (verificationResult.severity) {
            case VerificationSeverity.error:
              backgroundColor = Colors.red;
              break;
            case VerificationSeverity.warning:
              backgroundColor = Colors.orange;
              break;
            default:
              backgroundColor = Colors.blue;
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_verificationMessage(verificationResult)),
              backgroundColor: backgroundColor,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      final dataService = DataService();
      await dataService.postReview(
        widget.professionnelId,
        _nameController.text,
        _selectedRating,
        _messageController.text,
        _titleController.text,
      );

      await verificationService.recordReviewPost(
        widget.professionnelId,
        _nameController.text,
        _messageController.text,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_localizationService.tr('review_success')),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_localizationService.tr('review_error')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  String _verificationMessage(ReviewVerificationResult result) {
    final key = switch (result.code) {
      ReviewVerificationCode.cooldown => 'review_cooldown',
      ReviewVerificationCode.suspiciousContent => 'review_suspicious_content',
      ReviewVerificationCode.excessiveRepetition =>
        'review_excessive_repetition',
      ReviewVerificationCode.allCaps => 'review_all_caps',
      ReviewVerificationCode.tooShort => 'review_minimum',
      ReviewVerificationCode.tooFewWords => 'review_too_few_words',
      ReviewVerificationCode.lowQuality => 'review_low_quality',
      ReviewVerificationCode.duplicateProfessional =>
        'review_duplicate_professional',
      ReviewVerificationCode.duplicateContent => 'review_duplicate_content',
      ReviewVerificationCode.allowed => 'review_success',
    };
    return _localizationService
        .tr(key)
        .replaceAll('{minutes}', '${result.remainingMinutes ?? 0}');
  }

  Widget _buildStarRating() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        final starIndex = index + 1;
        final selected = starIndex <= _selectedRating;
        final label = _localizationService.currentLanguage == 'en'
            ? '$starIndex out of 5 stars'
            : '$starIndex étoile${starIndex > 1 ? 's' : ''} sur 5';
        return Semantics(
          selected: selected,
          child: IconButton(
            onPressed: () => setState(() => _selectedRating = starIndex),
            tooltip: label,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: Icon(
              starIndex <= _selectedRating ? Icons.star : Icons.star_outline,
              color: starIndex <= _selectedRating ? Colors.amber : Colors.grey,
              size: 32,
            ),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_localizationService.tr('add_review')),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        actions: [
          LanguageSelector(
            onLanguageChanged: (String languageCode) {
              setState(() {});
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Introduction
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(
                        Icons.rate_review,
                        size: 48,
                        color: Colors.blue.shade600,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _localizationService.tr('share_experience'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _localizationService.tr('help_others'),
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Note par étoiles
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        _localizationService.tr('review_rating'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildStarRating(),
                      const SizedBox(height: 8),
                      if (_selectedRating > 0)
                        Text(
                          '$_selectedRating/5 ${_localizationService.tr('stars')}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Nom
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: '${_localizationService.tr('review_name')} *',
                  prefixIcon: const Icon(Icons.person),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return _localizationService.tr('enter_name');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Titre de l'avis
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: _localizationService.tr('review_title'),
                  prefixIcon: const Icon(Icons.title),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  hintText: _localizationService.tr('review_title_placeholder'),
                ),
                maxLength: 100,
              ),
              const SizedBox(height: 16),

              // Message
              TextFormField(
                controller: _messageController,
                decoration: InputDecoration(
                  labelText: '${_localizationService.tr('review_comment')} *',
                  prefixIcon: const Icon(Icons.message),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  hintText: _localizationService.tr('review_placeholder'),
                ),
                maxLines: 5,
                maxLength: 500,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return _localizationService.tr('enter_comment');
                  }
                  if (value.trim().length < 10) {
                    return _localizationService.tr('review_minimum');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Bouton de soumission
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitReview,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isSubmitting
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(_localizationService.tr('sending')),
                          ],
                        )
                      : Text(
                          _localizationService.tr('publish_review'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),

              // Note d'information
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.blue.shade600,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _localizationService.tr('important_info'),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _localizationService.tr('review_info_text'),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
