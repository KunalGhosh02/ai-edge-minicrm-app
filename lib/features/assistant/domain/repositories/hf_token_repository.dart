abstract interface class HfTokenRepository {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}
