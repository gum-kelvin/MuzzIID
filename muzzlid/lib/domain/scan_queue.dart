/// Queue state is persisted before work starts. A demo receipt never establishes
/// biometric identity or authorizes trade.
enum ScanState { pending, processing, acknowledged, failed, conflict }

class PendingScan {
  final String receiptId, animalId, modelVersion;
  final DateTime createdAt;
  final ScanState state;
  final int attempts;
  final String? acknowledgement;
  const PendingScan({
    required this.receiptId,
    required this.animalId,
    required this.modelVersion,
    required this.createdAt,
    this.state = ScanState.pending,
    this.attempts = 0,
    this.acknowledgement,
  });

  PendingScan copyWith({
    ScanState? state,
    int? attempts,
    String? acknowledgement,
  }) =>
      PendingScan(
        receiptId: receiptId,
        animalId: animalId,
        modelVersion: modelVersion,
        createdAt: createdAt,
        state: state ?? this.state,
        attempts: attempts ?? this.attempts,
        acknowledgement: acknowledgement ?? this.acknowledgement,
      );

  Map<String, dynamic> toJson() => {
        'receiptId': receiptId,
        'animalId': animalId,
        'modelVersion': modelVersion,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'state': state.name,
        'attempts': attempts,
        'acknowledgement': acknowledgement,
      };
  factory PendingScan.fromJson(Map<String, dynamic> j) => PendingScan(
        receiptId: j['receiptId'] as String,
        animalId: j['animalId'] as String,
        modelVersion: j['modelVersion'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        state: ScanState.values.byName(j['state'] as String),
        attempts: j['attempts'] as int,
        acknowledgement: j['acknowledgement'] as String?,
      );
}

abstract interface class ScanQueueRepository {
  Future<List<PendingScan>> read();
  Future<void> save(List<PendingScan> scans);
}

class DrainScanQueue {
  final ScanQueueRepository repository;
  final Future<String> Function(String receipt) acknowledge;
  bool _running = false;
  DrainScanQueue(this.repository, this.acknowledge);

  Future<void> call() async {
    if (_running) return;
    _running = true;
    try {
      final scans = await repository.read();
      for (var i = 0; i < scans.length; i++) {
        final scan = scans[i];
        if (scan.state == ScanState.acknowledged ||
            scan.state == ScanState.conflict) {
          continue;
        }
        scans[i] = scan.copyWith(
          state: ScanState.processing,
          attempts: scan.attempts + 1,
        );
        await repository.save(scans);
        try {
          final receipt = await acknowledge(scan.receiptId);
          if (receipt.isEmpty) throw StateError('Missing acknowledgement');
          scans[i] = scans[i].copyWith(
            state: ScanState.acknowledged,
            acknowledgement: receipt,
          );
        } catch (_) {
          scans[i] = scans[i].copyWith(state: ScanState.failed);
        }
        await repository.save(scans);
      }
    } finally {
      _running = false;
    }
  }
}
