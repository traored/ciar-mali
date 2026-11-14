import 'dart:convert';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

void telechargerOctets(Uint8List octets, String nomFichier, String mime) {
  final donnees = base64Encode(octets);
  final lien = web.HTMLAnchorElement()
    ..href = 'data:$mime;base64,$donnees'
    ..download = nomFichier
    ..style.display = 'none';
  web.document.body?.append(lien);
  lien.click();
  lien.remove();
}
