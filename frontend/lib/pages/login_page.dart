import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _identifiant = TextEditingController();
  final _motDePasse = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscur = true;
  bool _chargement = false;
  String? _erreur;

  @override
  void dispose() {
    _identifiant.dispose();
    _motDePasse.dispose();
    super.dispose();
  }

  Future<void> _connecter() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      await context.read<AppState>().connexion(_identifiant.text.trim(), _motDePasse.text);
    } catch (e) {
      if (mounted) setState(() => _erreur = e.toString());
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, contraintes) {
          final large = contraintes.maxWidth >= 980;
          return Row(
            children: [
              if (large) Expanded(flex: 11, child: _branding()),
              Expanded(
                flex: large ? 9 : 1,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFF8FAFF), Color(0xFFEEF3FB)],
                    ),
                  ),
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 430),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!large) ...[
                              _logoCompact(),
                              const SizedBox(height: 28),
                            ],
                            _carteConnexion(large),
                            const SizedBox(height: 20),
                            Text(
                              'CIAR-Mali · Gestion des emplois du temps universitaires',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppCouleurs.texteDoux.withValues(alpha: 0.9),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _branding() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B1730), Color(0xFF142D5E), Color(0xFF1E3A8A)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            right: -120,
            child: _cercle(340, Colors.white.withValues(alpha: 0.04)),
          ),
          Positioned(
            bottom: -160,
            left: -80,
            child: _cercle(420, Colors.white.withValues(alpha: 0.03)),
          ),
          Padding(
            padding: const EdgeInsets.all(56),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _logoCarre(52),
                    const SizedBox(width: 14),
                    const Text(
                      'CIAR-Mali',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                const SizedBox(height: 22),
                const Text(
                  'Planifiez,\nsuivez, valorisez.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 44,
                    height: 1.08,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.2,
                  ),
                ),
                const SizedBox(height: 18),
                const SizedBox(
                  width: 430,
                  child: Text(
                    "Une plateforme unique pour construire les emplois du temps, "
                    "éviter les conflits et mesurer précisément les heures effectuées "
                    "par chaque enseignant.",
                    style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 15, height: 1.65),
                  ),
                ),
                const SizedBox(height: 34),
                Wrap(
                  spacing: 26,
                  runSpacing: 18,
                  children: const [
                    _Avantage(Icons.auto_awesome_outlined, 'Génération automatique'),
                    _Avantage(Icons.event_available_outlined, 'Zéro conflit'),
                    _Avantage(Icons.timer_outlined, 'Heures enseignants'),
                    _Avantage(Icons.picture_as_pdf_outlined, 'Exports PDF'),
                  ],
                ),
                const Spacer(),
                Row(
                  children: [
                    const Icon(Icons.lock_outline, size: 15, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 8),
                    Text(
                      'Accès sécurisé · Rôles et permissions',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _logoCompact() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _logoCarre(44),
        const SizedBox(width: 12),
        const Text(
          'CIAR-Mali',
          style: TextStyle(
            color: AppCouleurs.bleuNuit,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }

  Widget _logoCarre(double taille) {
    return Container(
      width: taille,
      height: taille,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF0D9488)]),
        borderRadius: BorderRadius.circular(taille * 0.26),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B82F6).withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(Icons.calendar_month_rounded, color: Colors.white, size: taille * 0.55),
    );
  }

  Widget _cercle(double taille, Color couleur) {
    return Container(
      width: taille,
      height: taille,
      decoration: BoxDecoration(color: couleur, shape: BoxShape.circle),
    );
  }

  Widget _carteConnexion(bool large) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppCouleurs.bordure),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.06),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Bon retour parmi nous',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -0.4),
            ),
            const SizedBox(height: 6),
            const Text(
              'Connectez-vous à votre espace de gestion.',
              style: TextStyle(fontSize: 13, color: AppCouleurs.texteDoux),
            ),
            const SizedBox(height: 26),
            TextFormField(
              controller: _identifiant,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Identifiant',
                hintText: 'Ex. admin',
                prefixIcon: Icon(Icons.person_outline, size: 20),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Saisissez votre identifiant' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _motDePasse,
              obscureText: _obscur,
              onFieldSubmitted: (_) => _connecter(),
              decoration: InputDecoration(
                labelText: 'Mot de passe',
                prefixIcon: const Icon(Icons.lock_outline, size: 20),
                suffixIcon: IconButton(
                  icon: Icon(_obscur ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                  onPressed: () => setState(() => _obscur = !_obscur),
                ),
              ),
              validator: (v) => (v == null || v.isEmpty) ? 'Saisissez votre mot de passe' : null,
            ),
            if (_erreur != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppCouleurs.rouge.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppCouleurs.rouge.withValues(alpha: 0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline, color: AppCouleurs.rouge, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _erreur!,
                        style: const TextStyle(color: AppCouleurs.rouge, fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _chargement ? null : _connecter,
                child: _chargement
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Se connecter'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avantage extends StatelessWidget {
  final IconData icone;
  final String texte;

  const _Avantage(this.icone, this.texte);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icone, color: const Color(0xFF5EEAD4), size: 18),
        const SizedBox(width: 8),
        Text(texte, style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 12.5)),
      ],
    );
  }
}
