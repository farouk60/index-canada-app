import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import '../services/localization_service.dart';

class CouponWidget extends StatelessWidget {
  final Professionnel professionnel;
  final bool isCompact;

  const CouponWidget({
    super.key,
    required this.professionnel,
    this.isCompact = false,
  });

  // Vérifier si le coupon est valide
  bool get isValidCoupon {
    // Un coupon est valide s'il a un code et un titre
    bool hasCodeAndTitle =
        professionnel.couponCode.isNotEmpty &&
        (professionnel.couponTitle.isNotEmpty ||
            professionnel.couponTitleEN.isNotEmpty);

    if (!hasCodeAndTitle) return false;

    // Si une date d'expiration est définie, elle doit être dans le futur
    if (professionnel.couponExpirationDate != null) {
      return professionnel.couponExpirationDate!.isAfter(DateTime.now());
    }

    // Si pas de date d'expiration définie, le coupon est considéré comme valide
    return true;
  }

  // Vérifier si le coupon expire bientôt (dans les 7 prochains jours)
  bool get isExpiringSoon {
    if (professionnel.couponExpirationDate == null) return false;
    final daysUntilExpiration = professionnel.couponExpirationDate!
        .difference(DateTime.now())
        .inDays;
    return daysUntilExpiration <= 7 && daysUntilExpiration > 0;
  }

  // Obtenir le nombre de jours restants
  int get daysUntilExpiration {
    if (professionnel.couponExpirationDate == null) return 0;
    return professionnel.couponExpirationDate!
        .difference(DateTime.now())
        .inDays;
  }

  @override
  Widget build(BuildContext context) {
    final localizationService = LocalizationService();

    if (!isValidCoupon) {
      return const SizedBox.shrink();
    }

    if (isCompact) {
      return _buildCompactCoupon(context, localizationService);
    } else {
      return _buildFullCoupon(context, localizationService);
    }
  }

  Widget _buildCompactCoupon(
    BuildContext context,
    LocalizationService localizationService,
  ) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade400, Colors.orange.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_offer, color: Colors.white, size: 16),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              professionnel.getCouponTitleInLanguage(
                localizationService.currentLanguage,
              ),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFullCoupon(
    BuildContext context,
    LocalizationService localizationService,
  ) {
    return Card(
      elevation: 8,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              Colors.orange.shade400,
              Colors.orange.shade600,
              Colors.deepOrange.shade500,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            // Motif décoratif
            Positioned(
              right: -20,
              top: -20,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // En-tête avec icône et titre
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.local_offer,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              localizationService.tr('exclusive_offer'),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              professionnel.getCouponTitleInLanguage(
                                localizationService.currentLanguage,
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Badge d'urgence si expire bientôt
                      if (isExpiringSoon)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.shade600,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            localizationService.tr('expires_soon'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Description du coupon
                  if (professionnel
                      .getCouponDescriptionInLanguage(
                        localizationService.currentLanguage,
                      )
                      .isNotEmpty) ...[
                    Text(
                      professionnel.getCouponDescriptionInLanguage(
                        localizationService.currentLanguage,
                      ),
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Code et expiration
                  Row(
                    children: [
                      // Code du coupon
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.grey.shade300,
                              style: BorderStyle.solid,
                              width: 2,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                localizationService.tr('coupon_code'),
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      professionnel.couponCode,
                                      style: TextStyle(
                                        color: Colors.grey.shade800,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => _copyCouponCode(
                                      context,
                                      localizationService,
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Icon(
                                        Icons.copy,
                                        color: Colors.blue.shade600,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Date d'expiration (seulement si elle existe)
                  if (professionnel.couponExpirationDate != null)
                    Row(
                      children: [
                        Icon(Icons.schedule, color: Colors.white70, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          '${localizationService.tr('expires_on')}: ${_formatDate(professionnel.couponExpirationDate!)}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '$daysUntilExpiration ${localizationService.tr('days_remaining')}',
                          style: TextStyle(
                            color: isExpiringSoon
                                ? Colors.red.shade100
                                : Colors.white70,
                            fontSize: 12,
                            fontWeight: isExpiringSoon
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _copyCouponCode(
    BuildContext context,
    LocalizationService localizationService,
  ) {
    Clipboard.setData(ClipboardData(text: professionnel.couponCode));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(localizationService.tr('coupon_code_copied')),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
