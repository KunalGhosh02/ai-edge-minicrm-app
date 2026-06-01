import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:minicrm/features/cloud/domain/entities/auth_user.dart';
import 'package:minicrm/features/cloud/domain/entities/customer_message.dart';
import 'package:minicrm/features/cloud/domain/entities/customer_session.dart';
import 'package:minicrm/features/cloud/domain/repositories/customer_session_repository.dart';

class FirestoreCustomerSessionRepository implements CustomerSessionRepository {
  FirestoreCustomerSessionRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _sessionsCol(String userId) =>
      _db.collection('users').doc(userId).collection('sessions');

  CollectionReference<Map<String, dynamic>> _messagesCol({
    required String userId,
    required String customerId,
  }) =>
      _sessionsCol(userId).doc(customerId).collection('messages');

  @override
  Future<void> ensureUserDoc(AuthUser user) async {
    final doc = _db.collection('users').doc(user.uid);
    await doc.set({
      'email': user.email,
      'displayName': user.displayName,
      'photoUrl': user.photoUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Stream<List<CustomerSession>> watchSessions(String userId) {
    return _sessionsCol(userId)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map(
          (snap) => [
            for (final doc in snap.docs) _sessionFromDoc(doc),
          ],
        );
  }

  @override
  Stream<CustomerSession?> watchSession({
    required String userId,
    required String customerId,
  }) {
    return _sessionsCol(userId).doc(customerId).snapshots().map((snap) {
      if (!snap.exists) return null;
      return _sessionFromDocData(customerId, snap.data() ?? const {});
    });
  }

  @override
  Stream<List<CustomerMessage>> watchMessages({
    required String userId,
    required String customerId,
  }) {
    return _messagesCol(userId: userId, customerId: customerId)
        .orderBy('createdAt')
        .snapshots()
        .map(
          (snap) => [
            for (final doc in snap.docs) _messageFromDoc(doc),
          ],
        );
  }

  @override
  Future<List<CustomerMessage>> getMessages({
    required String userId,
    required String customerId,
  }) async {
    final snap = await _messagesCol(userId: userId, customerId: customerId)
        .orderBy('createdAt')
        .get();
    return [for (final doc in snap.docs) _messageFromDoc(doc)];
  }

  @override
  Future<void> appendAssistantMessage({
    required String userId,
    required String customerId,
    required CustomerMessage message,
  }) async {
    final now = Timestamp.now();
    final batch = _db.batch();
    final msgRef = _messagesCol(
      userId: userId,
      customerId: customerId,
    ).doc(message.id);
    batch.set(msgRef, {
      'id': message.id,
      'sender': message.sender == CustomerSender.assistant
          ? 'assistant'
          : 'customer',
      'text': message.text,
      'createdAt': now,
    });
    final sessionRef = _sessionsCol(userId).doc(customerId);
    batch.set(sessionRef, {
      'lastMessageAt': now,
      'lastMessagePreview': message.text.length > 80
          ? '${message.text.substring(0, 80)}…'
          : message.text,
      'lastSender': message.sender == CustomerSender.assistant
          ? 'assistant'
          : 'customer',
    }, SetOptions(merge: true));
    await batch.commit();
  }

  @override
  Future<void> setSessionTakenOver({
    required String userId,
    required String customerId,
    required bool takenOver,
  }) async {
    await _sessionsCol(userId).doc(customerId).set(
      {'takenOver': takenOver},
      SetOptions(merge: true),
    );
  }

  CustomerSession _sessionFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) =>
      _sessionFromDocData(doc.id, doc.data());

  CustomerSession _sessionFromDocData(
    String customerId,
    Map<String, dynamic> data,
  ) {
    return CustomerSession(
      customerId: customerId,
      lastMessageAt: _asDate(data['lastMessageAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      customerName: data['customerName'] as String?,
      lastMessagePreview: data['lastMessagePreview'] as String?,
      takenOver: (data['takenOver'] as bool?) ?? false,
    );
  }

  CustomerMessage _messageFromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final senderRaw = (data['sender'] as String?) ?? 'customer';
    return CustomerMessage(
      id: (data['id'] as String?) ?? doc.id,
      sender: senderRaw == 'assistant'
          ? CustomerSender.assistant
          : CustomerSender.customer,
      text: (data['text'] as String?) ?? '',
      createdAt:
          _asDate(data['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  DateTime? _asDate(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}

final customerSessionRepositoryProvider =
    Provider<CustomerSessionRepository>((ref) {
  return FirestoreCustomerSessionRepository();
});
