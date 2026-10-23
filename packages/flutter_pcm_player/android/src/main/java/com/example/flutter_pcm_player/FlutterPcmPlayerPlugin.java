package com.example.flutter_pcm_player;

import androidx.annotation.NonNull;

import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public class FlutterPcmPlayerPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
    private MethodChannel channel;
    private PcmPlayer player;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        channel = new MethodChannel(binding.getBinaryMessenger(), "flutter_pcm_player");
        channel.setMethodCallHandler(this);
        player = new PcmPlayer();
    }

    @Override
    @SuppressWarnings("unchecked")
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "initialize":
                Map<String, Object> initArgs = (Map<String, Object>) call.arguments;
                player.initialize(
                        ((Number) initArgs.get("nChannels")).intValue(),
                        ((Number) initArgs.get("sampleRate")).intValue(),
                        ((Number) initArgs.get("pcmType")).intValue());
                result.success(null);
                break;
            case "release":
                player.release();
                result.success(null);
                break;
            case "play":
                player.play();
                result.success(player.getPlayState());
                break;
            case "stop":
                player.stop();
                result.success(player.getPlayState());
                break;
            case "pause":
                player.pause();
                result.success(player.getPlayState());
                break;
            case "resume":
                player.play();
                result.success(player.getPlayState());
                break;
            case "feed":
                Map<String, Object> feedArgs = (Map<String, Object>) call.arguments;
                player.write((byte[]) feedArgs.get("data"));
                result.success(player.getPlayState());
                break;
            default:
                result.notImplemented();
        }
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (player != null) player.dispose();
        channel.setMethodCallHandler(null);
    }
}
