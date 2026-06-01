import 'package:minicrm/features/cloud/domain/entities/auth_user.dart';
import 'package:minicrm/features/cloud/domain/entities/customer_message.dart';
import 'package:minicrm/features/cloud/domain/entities/customer_session.dart';

abstract interface class CustomerSessionRepository {
  Future<void> ensureUserDoc(AuthUser user);

  Stream<List<CustomerSession>> watchSessions(String userId);

  Stream<CustomerSession?> watchSession({
    required String userId,
    required String customerId,
  });

  Stream<List<CustomerMessage>> watchMessages({
    required String userId,
    required String customerId,
  });

  Future<List<CustomerMessage>> getMessages({
    required String userId,
    required String customerId,
  });

  Future<void> appendAssistantMessage({
    required String userId,
    required String customerId,
    required CustomerMessage message,
  });

  Future<void> setSessionTakenOver({
    required String userId,
    required String customerId,
    required bool takenOver,
  });
}
