import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:minicrm/features/cloud/domain/entities/auth_user.dart';
import 'package:minicrm/features/cloud/domain/repositories/auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    fa.FirebaseAuth? firebaseAuth,
    GoogleSignIn? googleSignIn,
  })  : _firebaseAuth = firebaseAuth ?? fa.FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  final fa.FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn;
  Future<void>? _initFuture;

  Future<void> _ensureInitialized() {
    return _initFuture ??= _googleSignIn.initialize();
  }

  @override
  AuthUser? get currentUser => _toDomain(_firebaseAuth.currentUser);

  @override
  Stream<AuthUser?> watchCurrentUser() =>
      _firebaseAuth.authStateChanges().map(_toDomain);

  @override
  Future<AuthUser> signInWithGoogle() async {
    await _ensureInitialized();
    final account = await _googleSignIn.authenticate();
    final auth = account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) {
      throw StateError(
        'Google sign-in returned no ID token. '
        'Check that google-services.json contains a web (type 3) OAuth client.',
      );
    }
    final credential = fa.GoogleAuthProvider.credential(idToken: idToken);
    final result = await _firebaseAuth.signInWithCredential(credential);
    final user = result.user;
    if (user == null) {
      throw StateError('Sign-in completed but Firebase returned a null user.');
    }
    return _toDomain(user)!;
  }

  @override
  Future<void> signOut() async {
    if (_initFuture != null) {
      try {
        await _googleSignIn.signOut();
      } on Object {
        // Best effort.
      }
    }
    await _firebaseAuth.signOut();
  }

  AuthUser? _toDomain(fa.User? user) {
    if (user == null) return null;
    return AuthUser(
      uid: user.uid,
      email: user.email ?? '',
      displayName: user.displayName,
      photoUrl: user.photoURL,
    );
  }
}
