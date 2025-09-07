// lib/pages/admin_email_management_page.dart
// Page d'administration pour gérer les emails de confirmation

import 'package:flutter/material.dart';
import '../services/confirmation_email_service.dart';

class AdminEmailManagementPage extends StatefulWidget {
  const AdminEmailManagementPage({super.key});

  @override
  State<AdminEmailManagementPage> createState() =>
      _AdminEmailManagementPageState();
}

class _AdminEmailManagementPageState extends State<AdminEmailManagementPage> {
  List<Map<String, dynamic>> _professionalsWithoutEmail = [];
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadProfessionalsWithoutEmail();
  }

  Future<void> _loadProfessionalsWithoutEmail() async {
    setState(() => _isLoading = true);

    try {
      final professionals =
          await ConfirmationEmailService.getProfessionalsWithoutEmail();
      setState(() {
        _professionalsWithoutEmail = professionals;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackBar('Erreur lors du chargement: $e');
    }
  }

  Future<void> _sendManualEmail(
    String professionalId,
    String email,
    String businessName,
  ) async {
    try {
      final success = await ConfirmationEmailService.sendManualConfirmation(
        professionalId: professionalId,
        email: email,
      );

      if (success) {
        _showSuccessSnackBar('Email envoyé à $businessName');
        _loadProfessionalsWithoutEmail(); // Recharger la liste
      } else {
        _showErrorSnackBar('Échec de l\'envoi pour $businessName');
      }
    } catch (e) {
      _showErrorSnackBar('Erreur: $e');
    }
  }

  Future<void> _sendBatchEmails() async {
    if (_professionalsWithoutEmail.isEmpty) return;

    setState(() => _isSending = true);

    try {
      final professionalIds = _professionalsWithoutEmail
          .map((p) => p['id'] as String)
          .toList();

      final results =
          await ConfirmationEmailService.sendBatchConfirmationEmails(
            professionalIds,
          );

      setState(() => _isSending = false);

      if (results != null) {
        _showSuccessSnackBar(
          'Envoi terminé: ${results['sent']} réussis, ${results['failed']} échecs',
        );
        _loadProfessionalsWithoutEmail(); // Recharger la liste
      } else {
        _showErrorSnackBar('Erreur lors de l\'envoi en lot');
      }
    } catch (e) {
      setState(() => _isSending = false);
      _showErrorSnackBar('Erreur: $e');
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestion Emails de Confirmation'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        actions: [
          if (_professionalsWithoutEmail.isNotEmpty)
            IconButton(
              onPressed: _isSending ? null : _sendBatchEmails,
              icon: _isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.send),
              tooltip: 'Envoyer tous les emails',
            ),
          IconButton(
            onPressed: _loadProfessionalsWithoutEmail,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _professionalsWithoutEmail.isEmpty
          ? _buildEmptyState()
          : _buildProfessionalsList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, size: 80, color: Colors.green[400]),
          const SizedBox(height: 16),
          const Text(
            'Tous les professionnels ont reçu leur email de confirmation !',
            style: TextStyle(fontSize: 18),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _loadProfessionalsWithoutEmail,
            child: const Text('Actualiser'),
          ),
        ],
      ),
    );
  }

  Widget _buildProfessionalsList() {
    return Column(
      children: [
        // Statistiques
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Colors.orange[50],
          child: Text(
            '${_professionalsWithoutEmail.length} professionnel(s) sans email de confirmation',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.orange[800],
            ),
            textAlign: TextAlign.center,
          ),
        ),

        // Liste des professionnels
        Expanded(
          child: ListView.builder(
            itemCount: _professionalsWithoutEmail.length,
            itemBuilder: (context, index) {
              final professional = _professionalsWithoutEmail[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.orange[100],
                    child: Icon(Icons.business, color: Colors.orange[700]),
                  ),
                  title: Text(
                    professional['businessName'] ?? 'Nom inconnu',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Email: ${professional['email'] ?? 'N/A'}'),
                      Text(
                        'Plan: ${professional['plan']?.toUpperCase() ?? 'N/A'}',
                      ),
                      if (professional['createdAt'] != null)
                        Text(
                          'Inscrit: ${DateTime.tryParse(professional['createdAt'])?.toLocal().toString().split(' ')[0] ?? 'N/A'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                    ],
                  ),
                  trailing: IconButton(
                    onPressed: () => _sendManualEmail(
                      professional['id'],
                      professional['email'],
                      professional['businessName'],
                    ),
                    icon: Icon(Icons.send, color: Colors.blue[700]),
                    tooltip: 'Envoyer email',
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
