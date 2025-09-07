import 'package:flutter/material.dart';
import 'dart:async';
import '../data_service.dart';
import '../services/review_verification_service.dart';
import '../services/localization_service.dart';
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
  String? _cooldownMessage;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _checkCooldownStatus();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _titleController.dispose();
    _messageController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkCooldownStatus() async {
    final verificationService = ReviewVerificationService();
    final result = await verificationService.canPostReview(
      widget.professionnelId,
      'temp',
      'temp message',
      'temp title',
    );

    if (!result.canPost && result.reason.contains('attendre')) {
      if (mounted) {
        setState(() {
          _cooldownMessage = result.reason;
        });

        _cooldownTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
          _checkCooldownStatus();
        });
      }
    }
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
              content: Text(verificationResult.reason),
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_localizationService.tr('review_error')}: $e'),
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

  Widget _buildStarRating() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        final starIndex = index + 1;
        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedRating = starIndex;
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
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
              // Avertissement de cooldown
              if (_cooldownMessage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        color: Colors.orange.shade600,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _localizationService.tr('temporal_limitation'),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _cooldownMessage!,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

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

              // Message de cooldown au niveau du bouton
              if (_cooldownMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.timer, color: Colors.red.shade600, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _cooldownMessage!,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.red.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Bouton de soumission
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting || _cooldownMessage != null
                      ? null
                      : _submitReview,
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
