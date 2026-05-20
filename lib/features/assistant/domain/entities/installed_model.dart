import 'package:equatable/equatable.dart';

class InstalledModel extends Equatable {
  const InstalledModel({
    required this.path,
    required this.name,
    required this.sizeBytes,
  });

  factory InstalledModel.fromMap(Map<String, dynamic> map) {
    return InstalledModel(
      path: map['path'] as String,
      name: map['name'] as String,
      sizeBytes: (map['size'] as num).toInt(),
    );
  }

  final String path;
  final String name;
  final int sizeBytes;

  String get humanSize {
    if (sizeBytes >= 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
  }

  Map<String, dynamic> toMap() => {
        'path': path,
        'name': name,
        'size': sizeBytes,
      };

  @override
  List<Object?> get props => [path, name, sizeBytes];
}
