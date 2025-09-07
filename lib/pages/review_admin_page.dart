import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class ReviewAdminPage extends StatefulWidget {
  const ReviewAdminPage({super.key});

  @override
  State<ReviewAdminPage> createState() => _ReviewAdminPageState();
}

class _ReviewAdminPageState extends State<ReviewAdminPage> {
  List<Map<String, dynamic>> _reviewLogs = [];
  bool _isLoading = true;
  int _totalReviews = 0;
  int _blockedAttempts = 0;
  Map<String, int> _blockReasons = {};

  @override
  void initState() {
    super.initState();
    _loadReviewLogs();
  }

  Future<void> _loadReviewLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final allKeys = prefs.getKeys();

    final reviewLogs = <Map<String, dynamic>>[];
    final blockReasons = <String, int>{};

    for (String key in allKeys) {
      if (key.startsWith('review_')) {
        final reviewData = prefs.getString(key);
        if (reviewData != null) {
          try {
            final data = jsonDecode(reviewData);
            data['key'] = key;
            reviewLogs.add(data);
          } catch (e) {
            // Ignorer les entrées corrompues
          }
        }
      } else if (key.startsWith('blocked_review_')) {
        final blockedData = prefs.getString(key);
        if (blockedData != null) {
          try {
            final data = jsonDecode(blockedData);
            final reason = data['reason'] as String;
            blockReasons[reason] = (blockReasons[reason] ?? 0) + 1;
          } catch (e) {
            // Ignorer les entrées corrompues
          }
        }
      }
    }

    // Trier par timestamp (plus récent en premier)
    reviewLogs.sort(
      (a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int),
    );

    if (mounted) {
      setState(() {
        _reviewLogs = reviewLogs;
        _totalReviews = reviewLogs.length;
        _blockedAttempts = blockReasons.values.fold(
          0,
          (sum, count) => sum + count,
        );
        _blockReasons = blockReasons;
        _isLoading = false;
      });
    }
  }

  Future<void> _clearAllLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmer la suppression'),
        content: const Text(
          'Voulez-vous vraiment supprimer tous les logs d\'avis ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys();

      for (String key in allKeys) {
        if (key.startsWith('review_') || key.startsWith('blocked_review_')) {
          await prefs.remove(key);
        }
      }

      _loadReviewLogs();
    }
  }

  String _formatTimestamp(int timestamp) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String _getTimeAgo(int timestamp) {
    final now = DateTime.now();
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays} jour${difference.inDays > 1 ? 's' : ''}';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} heure${difference.inHours > 1 ? 's' : ''}';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''}';
    } else {
      return 'À l\'instant';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administration des avis'),
        backgroundColor: Colors.red.shade600,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReviewLogs,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: _clearAllLogs,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Statistiques
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          'Avis postés',
                          _totalReviews.toString(),
                          Icons.rate_review,
                          Colors.green,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildStatCard(
                          'Tentatives bloquées',
                          _blockedAttempts.toString(),
                          Icons.block,
                          Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Raisons de blocage
                  if (_blockReasons.isNotEmpty) ...[
                    const Text(
                      'Raisons de blocage',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: _blockReasons.entries.map((entry) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      entry.key,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      entry.value.toString(),
                                      style: TextStyle(
                                        color: Colors.red.shade700,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Logs des avis
                  const Text(
                    'Historique des avis',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),

                  if (_reviewLogs.isEmpty)
                    const Center(
                      child: Text(
                        'Aucun avis enregistré',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _reviewLogs.length,
                      itemBuilder: (context, index) {
                        final log = _reviewLogs[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue.shade100,
                              child: Text(
                                log['authorName'][0].toUpperCase(),
                                style: TextStyle(
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              log['authorName'],
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Professionnel: ${log['professionalId']}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                Text(
                                  _formatTimestamp(log['timestamp']),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                            trailing: Text(
                              'Il y a ${_getTimeAgo(log['timestamp'])}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
