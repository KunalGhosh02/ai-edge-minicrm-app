import 'package:equatable/equatable.dart';

enum CustomerSender { customer, assistant }

class CustomerMessage extends Equatable {
  const CustomerMessage({
    required this.id,
    required this.sender,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final CustomerSender sender;
  final String text;
  final DateTime createdAt;

  @override
  List<Object?> get props => [id, sender, text, createdAt];
}
