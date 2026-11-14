import 'register.dart';
import 'field_records.dart';

enum VerificationStatus { verified, uncertain, unregistered, pending }

class VerificationResult {
  final VerificationStatus status;
  final Animal? animal;
  final double? confidence;
  final bool research;
  const VerificationResult(this.status,
      {this.animal, this.confidence, this.research = false});
}

abstract interface class VerificationService {
  Future<VerificationResult> verify(String jpeg, GeoFix gps);
}

class UnconnectedVerificationService implements VerificationService {
  @override
  Future<VerificationResult> verify(String jpeg, GeoFix gps) async =>
      const VerificationResult(VerificationStatus.pending);
}
