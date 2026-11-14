import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final String message;
  final int? code;

  ApiException(this.message, [this.code]);

  @override
  String toString() => message;
}

class ApiClient {
  static const String _basePersonnalisee = String.fromEnvironment('API_BASE');

  /// Délai par défaut des appels courants. Render (offre gratuite) met
  /// 30 à 60 secondes à sortir de veille : 45 s provoquaient des échecs au
  /// premier appel après une période d'inactivité.
  static const Duration delaiParDefaut = Duration(seconds: 120);

  /// Délai des opérations lourdes (calcul des passages, génération de PDF,
  /// imports Excel) qui peuvent dépasser deux minutes sur une base distante.
  static const Duration delaiLong = Duration(seconds: 300);

  /// En web, l'API est servie par le même hôte que l'interface (`/api`).
  /// Hors web (tests), on retombe sur le serveur local de développement.
  static String get baseUrl {
    if (_basePersonnalisee.isNotEmpty) return _basePersonnalisee;
    if (kIsWeb) return '${Uri.base.origin}/api';
    return 'http://localhost:8000/api';
  }

  String? token;

  Map<String, String> get _entetes => {
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Uri _uri(String chemin, [Map<String, dynamic>? parametres]) {
    final uri = Uri.parse('$baseUrl$chemin');
    if (parametres == null) return uri;
    final propres = <String, String>{};
    parametres.forEach((cle, valeur) {
      if (valeur != null) propres[cle] = valeur.toString();
    });
    return uri.replace(queryParameters: propres);
  }

  Future<dynamic> get(
    String chemin, [
    Map<String, dynamic>? parametres,
    Duration? delai,
  ]) async {
    final reponse = await _executer(
      () => http.get(_uri(chemin, parametres), headers: _entetes),
      delai: delai,
    );
    return _decoder(reponse);
  }

  Future<List<Map<String, dynamic>>> liste(
    String chemin, [
    Map<String, dynamic>? parametres,
    Duration? delai,
  ]) async {
    final donnees = await get(chemin, parametres, delai);
    if (donnees is! List) return [];
    return donnees.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> post(String chemin, Map<String, dynamic> corps) async {
    final reponse = await _executer(
      () => http.post(_uri(chemin), headers: _entetes, body: jsonEncode(corps)),
    );
    return Map<String, dynamic>.from(_decoder(reponse) as Map);
  }

  Future<Map<String, dynamic>> put(String chemin, Map<String, dynamic> corps) async {
    final reponse = await _executer(
      () => http.put(_uri(chemin), headers: _entetes, body: jsonEncode(corps)),
    );
    return Map<String, dynamic>.from(_decoder(reponse) as Map);
  }

  Future<void> delete(String chemin) async {
    await _executer(() => http.delete(_uri(chemin), headers: _entetes));
  }

  Future<Uint8List> octets(
    String chemin, [
    Map<String, dynamic>? parametres,
    Duration? delai,
  ]) async {
    final reponse = await _executer(
      () => http.get(_uri(chemin, parametres), headers: {
        'Accept': 'application/pdf',
        if (token != null) 'Authorization': 'Bearer $token',
      }),
      delai: delai ?? delaiLong,
    );
    return reponse.bodyBytes;
  }

  Future<Map<String, dynamic>> envoyerFichier(
    String chemin,
    String nomFichier,
    Uint8List contenu,
  ) async {
    final requete = http.MultipartRequest('POST', _uri(chemin));
    if (token != null) requete.headers['Authorization'] = 'Bearer $token';
    requete.files.add(http.MultipartFile.fromBytes('fichier', contenu, filename: nomFichier));
    final flux = await requete.send().timeout(delaiLong);
    final reponse = await http.Response.fromStream(flux).timeout(delaiLong);
    if (reponse.statusCode >= 400) {
      throw ApiException(_messageErreur(reponse), reponse.statusCode);
    }
    final corps = _decoder(reponse);
    if (corps is! Map) {
      throw ApiException(
        'Réponse inattendue du serveur lors de l’import.',
        reponse.statusCode,
      );
    }
    return Map<String, dynamic>.from(corps);
  }

  Future<http.Response> _executer(
    Future<http.Response> Function() action, {
    Duration? delai,
  }) async {
    try {
      final reponse = await action().timeout(delai ?? delaiParDefaut);
      if (reponse.statusCode >= 400) {
        throw ApiException(_messageErreur(reponse), reponse.statusCode);
      }
      return reponse;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(
        'Impossible de joindre le serveur. Vérifiez que FastAPI est démarré.\n$e',
      );
    }
  }

  dynamic _decoder(http.Response reponse) {
    if (reponse.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(reponse.bodyBytes));
    } catch (_) {
      return reponse.body;
    }
  }

  String _messageErreur(http.Response reponse) {
    try {
      final corps = jsonDecode(utf8.decode(reponse.bodyBytes));
      if (corps is Map && corps['detail'] != null) {
        final detail = corps['detail'];
        if (detail is String) return detail;
        if (detail is List) {
          return detail
              .map((e) => e is Map ? (e['msg'] ?? e.toString()) : e.toString())
              .join('\n');
        }
      }
    } catch (_) {}
    if (reponse.statusCode == 401) return 'Session expirée. Reconnectez-vous.';
    if (reponse.statusCode == 403) return "Vous n'avez pas les droits pour cette action.";
    return 'Erreur serveur (${reponse.statusCode}).';
  }
}
