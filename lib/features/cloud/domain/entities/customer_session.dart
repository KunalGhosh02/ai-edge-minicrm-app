import 'package:equatable/equatable.dart';

class CustomerSession extends Equatable {
  const CustomerSession({
    required this.customerId,
    required this.lastMessageAt,
    this.customerName,
    this.lastMessagePreview,
    this.takenOver = false,
  });

  final String customerId;
  final DateTime lastMessageAt;
  final String? customerName;
  final String? lastMessagePreview;
  final bool takenOver;

  @override
  List<Object?> get props => [
        customerId,
        lastMessageAt,
        customerName,
        lastMessagePreview,
        takenOver,
      ];
}
