import 'package:flutter/material.dart';

class ImprovedRatingWidget extends StatelessWidget {
  final double rating;
  final int reviewCount;
  final double size;
  final bool showCount;
  final Color color;

  const ImprovedRatingWidget({
    super.key,
    required this.rating,
    required this.reviewCount,
    this.size = 16,
    this.showCount = true,
    this.color = Colors.amber,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Étoiles avec demi-étoiles
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (index) {
            double starRating = rating - index;
            if (starRating >= 1) {
              return Icon(Icons.star, color: color, size: size);
            } else if (starRating >= 0.5) {
              return Icon(Icons.star_half, color: color, size: size);
            } else {
              return Icon(
                Icons.star_border,
                color: color.withOpacity(0.3),
                size: size,
              );
            }
          }),
        ),

        if (showCount && reviewCount > 0) ...[
          const SizedBox(width: 4),
          Text(
            '(${reviewCount})',
            style: TextStyle(
              fontSize: size * 0.8,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

class RatingBreakdown extends StatelessWidget {
  final Map<int, int> ratingCounts;
  final int totalReviews;

  const RatingBreakdown({
    super.key,
    required this.ratingCounts,
    required this.totalReviews,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int star = 5; star >= 1; star--)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Text('$star'),
                const SizedBox(width: 8),
                Icon(Icons.star, color: Colors.amber, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: LinearProgressIndicator(
                    value: totalReviews > 0
                        ? (ratingCounts[star] ?? 0) / totalReviews
                        : 0,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.amber),
                  ),
                ),
                const SizedBox(width: 8),
                Text('${ratingCounts[star] ?? 0}'),
              ],
            ),
          ),
      ],
    );
  }
}
