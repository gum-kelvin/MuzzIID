// ignore_for_file: avoid_relative_lib_imports, avoid_print
// Dependency-free domain regression check: dart test/queue_check.dart
import '../lib/domain/scan_queue.dart';

class MemoryQueue implements ScanQueueRepository {
  List<PendingScan> items = [];
  @override
  Future<List<PendingScan>> read() async => [...items];
  @override
  Future<void> save(List<PendingScan> scans) async {
    items = [...scans];
  }
}

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> main() async {
  final repo = MemoryQueue();
  repo.items = [
    PendingScan(
      receiptId: 'receipt',
      animalId: 'animal',
      modelVersion: 'mock-v1',
      createdAt: DateTime.utc(2026),
    ),
  ];
  var calls = 0;
  final drain = DrainScanQueue(repo, (receipt) async {
    calls++;
    if (calls == 1) throw StateError('offline');
    return 'demo:$receipt';
  });
  await drain();
  check(repo.items.single.state == ScanState.failed, 'Failure must persist');
  await drain();
  check(
    repo.items.single.state == ScanState.acknowledged,
    'Retry must acknowledge',
  );
  check(repo.items.single.attempts == 2, 'Retry count must persist');
  await drain();
  check(calls == 2, 'Acknowledged work must not repeat');
  repo.items = [repo.items.single.copyWith(state: ScanState.processing)];
  await drain();
  check(calls == 3, 'Interrupted work must recover with same receipt');
  final restored = PendingScan.fromJson(repo.items.single.toJson());
  check(restored.receiptId == 'receipt', 'Receipt must survive persistence');
  print(
    'PASS: failure, retry, acknowledgement, idempotency, crash recovery, persistence',
  );
}
