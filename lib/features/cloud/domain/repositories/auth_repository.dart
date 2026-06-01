import 'package:minicrm/features/cloud/domain/entities/auth_user.dart';

abstract interface class AuthRepository {
  Stream<AuthUser?> watchCurrentUser();

  AuthUser? get currentUser;

  Future<AuthUser> signInWithGoogle();

  Future<void> signOut();
}
