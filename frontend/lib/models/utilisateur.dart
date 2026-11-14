class Utilisateur {
  final int id;
  final String identifiant;
  final String nomComplet;
  final String role;
  final bool actif;
  final int? enseignantId;

  Utilisateur({
    required this.id,
    required this.identifiant,
    required this.nomComplet,
    required this.role,
    required this.actif,
    this.enseignantId,
  });

  factory Utilisateur.depuisJson(Map<String, dynamic> json) => Utilisateur(
        id: json['id'] as int,
        identifiant: json['identifiant'] as String? ?? '',
        nomComplet: json['nom_complet'] as String? ?? '',
        role: json['role'] as String? ?? 'lecteur',
        actif: json['actif'] as bool? ?? true,
        enseignantId: json['enseignant_id'] as int?,
      );

  Map<String, dynamic> versJson() => {
        'id': id,
        'identifiant': identifiant,
        'nom_complet': nomComplet,
        'role': role,
        'actif': actif,
        'enseignant_id': enseignantId,
      };

  String get roleLibelle => switch (role) {
        'admin' => 'Administrateur',
        'gestionnaire' => 'Gestionnaire',
        'enseignant' => 'Enseignant',
        _ => 'Lecteur',
      };
}
