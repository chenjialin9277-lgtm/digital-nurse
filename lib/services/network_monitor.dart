import 'dart:async';

import 'package:flutter/services.dart';

/// Lightweight Android network signal. It intentionally checks whether a
/// usable transport exists, rather than relying on an external HTTP probe that
/// can incorrectly report "network unavailable" inside a hospital network.
class NetworkMonitor {
  const NetworkMonitor();

  static const EventChannel _events = EventChannel(
    'digital_nurse/network_status',
  );

  Stream<bool> get changes =>
      _events.receiveBroadcastStream().map((event) => event == true).distinct();
}
