import 'dart:typed_data';

import 'package:digital_nurse/services/online_playback_gate.dart';
import 'package:digital_nurse/services/xiaozhi_service.dart';
import 'package:digital_nurse/services/xiaozhi_websocket_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('listeners can remove themselves without dropping other listeners', () {
    final service = XiaozhiService(
      websocketUrl: 'wss://example.invalid',
      macAddress: 'test-device',
      clientId: 'test-client',
      token: 'test-token',
    );
    var firstCalls = 0;
    var secondCalls = 0;
    late XiaozhiServiceListener first;
    first = (_) {
      firstCalls++;
      service.removeListener(first);
    };
    service.addListener(first);
    service.addListener((_) => secondCalls++);

    service.debugHandleWebSocketEvent(
      XiaozhiEvent(type: XiaozhiEventType.connected),
    );
    service.debugHandleWebSocketEvent(
      XiaozhiEvent(type: XiaozhiEventType.connected),
    );

    expect(firstCalls, 1);
    expect(secondCalls, 2);
  });
  test('inbound audio failure dispatches a service error', () async {
    final gate = OnlinePlaybackGate(
      playFrame: (_) async {
        throw StateError('synthetic inbound playback failure');
      },
      stopPlayer: () async {},
      startPlayer: () async {},
    );
    final service = XiaozhiService(
      websocketUrl: 'wss://example.invalid',
      macAddress: '02:11:22:33:44:55',
      clientId: '11111111-2222-4333-8444-555555555555',
      token: 'test-token',
      onlinePlaybackGate: gate,
    );
    final events = <XiaozhiServiceEvent>[];
    service.addListener(events.add);

    service.debugHandleWebSocketEvent(
      XiaozhiEvent(
        type: XiaozhiEventType.binaryMessage,
        data: Uint8List.fromList([1, 2, 3]),
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      events.map((event) => event.type),
      containsAll([
        XiaozhiServiceEventType.audioData,
        XiaozhiServiceEventType.error,
      ]),
    );
    expect(
      events.last.data.toString(),
      contains('synthetic inbound playback failure'),
    );
  });
}
