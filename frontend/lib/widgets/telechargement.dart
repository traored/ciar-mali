import 'dart:typed_data';

import 'telechargement_stub.dart'
    if (dart.library.js_interop) 'telechargement_web.dart' as implementation;

/// Lance le téléchargement d'un fichier depuis le navigateur.
///
/// Sur les plateformes sans navigateur (tests sur VM), l'appel est sans effet.
void telechargerOctets(Uint8List octets, String nomFichier, String mime) {
  implementation.telechargerOctets(octets, nomFichier, mime);
}
