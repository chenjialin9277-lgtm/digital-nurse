import 'package:flutter/foundation.dart';

/// Development diagnostics only. Callers must omit credentials, device IDs and
/// conversation content; release and profile builds emit no diagnostic output.
void logDiagnostic(Object? message) {
  if (kDebugMode) debugPrint(message?.toString());
}
