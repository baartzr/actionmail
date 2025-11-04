import 'dart:async';

/// Simple singleton to coordinate Firebase initialization without blocking UI.
/// Code that needs Firebase can await [FirebaseInit.instance.whenReady].
class FirebaseInit {
  FirebaseInit._internal();
  static final FirebaseInit instance = FirebaseInit._internal();

  final Completer<void> _ready = Completer<void>();

  /// Future that completes when Firebase initialization attempt finishes
  /// (success or fail). Consumers can still verify Firebase.apps afterwards.
  Future<void> get whenReady => _ready.future;

  /// Mark initialization finished (idempotent)
  void complete() {
    if (!_ready.isCompleted) {
      _ready.complete();
    }
  }
}


