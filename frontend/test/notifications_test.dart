import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_edt/state/app_state.dart';

void main() {
  test('le compteur de notifications ignore les messages déjà lus', () {
    final app = AppState();
    app.notifications = [
      {'id': 1, 'lu': false},
      {'id': 2, 'lu': true},
      {'id': 3},
    ];

    expect(app.notificationsNonLues, 2);
  });
}
