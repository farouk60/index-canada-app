import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class PhotoDiagnosticPage extends StatefulWidget {
  @override
  _PhotoDiagnosticPageState createState() => _PhotoDiagnosticPageState();
}

class _PhotoDiagnosticPageState extends State<PhotoDiagnosticPage> {
  List<Map<String, dynamic>> _professionnels = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfessionnels();
  }

  Future<void> _loadProfessionnels() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final response = await http.get(
        Uri.parse('https://www.immigrantindex.com/_functions/data'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['items'] != null && data['items'] is List) {
          setState(() {
            _professionnels = List<Map<String, dynamic>>.from(data['items']);
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _error = 'Erreur API: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Erreur: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('🔍 Diagnostic Photos'),
        backgroundColor: Colors.blue,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('❌ $_error'),
                      ElevatedButton(
                        onPressed: _loadProfessionnels,
                        child: Text('Réessayer'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.all(16),
                  itemCount: _professionnels.take(5).length,
                  itemBuilder: (context, index) {
                    final prof = _professionnels[index];
                    return _buildProfessionnelCard(prof);
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadProfessionnels,
        child: Icon(Icons.refresh),
        tooltip: 'Actualiser',
      ),
    );
  }

  Widget _buildProfessionnelCard(Map<String, dynamic> prof) {
    final hasImage = prof['image'] != null && prof['image'].toString().isNotEmpty;
    final imageData = hasImage ? prof['image'].toString() : '';
    
    return Card(
      margin: EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // En-tête avec nom et statut image
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        prof['title'] ?? 'Nom inconnu',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        prof['email'] ?? 'Email inconnu',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: hasImage ? Colors.green : Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    hasImage ? '✅ Image' : '❌ Pas d\'image',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            
            SizedBox(height: 12),
            
            // Informations détaillées
            Text(
              '📅 Créé: ${prof['_createdDate'] ?? 'Date inconnue'}',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
            
            if (hasImage) ...[
              SizedBox(height: 8),
              _buildImageDiagnostic(imageData),
            ],
            
            // Galerie
            SizedBox(height: 8),
            _buildGalleryInfo(prof),
          ],
        ),
      ),
    );
  }

  Widget _buildImageDiagnostic(String imageData) {
    String type = 'Inconnu';
    String details = '';
    Color color = Colors.grey;
    
    if (imageData.startsWith('data:image/')) {
      type = 'Base64';
      color = Colors.green;
      final parts = imageData.split(',');
      if (parts.length >= 2) {
        try {
          final bytes = base64Decode(parts[1]);
          details = '${(bytes.length / 1024).toStringAsFixed(1)} KB';
        } catch (e) {
          details = 'Erreur décodage';
          color = Colors.orange;
        }
      }
    } else if (imageData.startsWith('http')) {
      type = 'URL HTTP';
      color = Colors.blue;
      details = imageData.substring(0, 30) + '...';
    } else if (imageData.startsWith('wix:image://')) {
      type = 'URL Wix';
      color = Colors.purple;
      details = 'ID Wix';
    }
    
    return Container(
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.image, color: color, size: 16),
              SizedBox(width: 4),
              Text(
                'Type: $type',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          if (details.isNotEmpty) ...[
            SizedBox(height: 4),
            Text(
              details,
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGalleryInfo(Map<String, dynamic> prof) {
    int galleryCount = 0;
    for (int i = 1; i <= 5; i++) {
      if (prof['galerieImage$i'] != null && prof['galerieImage$i'].toString().isNotEmpty) {
        galleryCount++;
      }
    }
    
    return Row(
      children: [
        Icon(Icons.photo_library, size: 16, color: Colors.grey[600]),
        SizedBox(width: 4),
        Text(
          'Galerie: $galleryCount/5 images',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }
}
