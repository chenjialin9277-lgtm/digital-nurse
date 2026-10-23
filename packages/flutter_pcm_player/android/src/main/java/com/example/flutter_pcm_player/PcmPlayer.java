package com.example.flutter_pcm_player;

import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioTrack;
import android.os.Handler;
import android.os.HandlerThread;

final class PcmPlayer {
    private AudioTrack audioTrack;
    private final HandlerThread workerThread;
    private final Handler worker;

    PcmPlayer() {
        workerThread = new HandlerThread("digital-nurse-pcm-player");
        workerThread.start();
        worker = new Handler(workerThread.getLooper());
    }

    synchronized void initialize(int channelCount, int sampleRate, int pcmType) {
        release();
        int encoding = pcmType == 0
                ? AudioFormat.ENCODING_PCM_8BIT
                : pcmType == 1
                ? AudioFormat.ENCODING_PCM_16BIT
                : AudioFormat.ENCODING_PCM_FLOAT;
        int channelMask = channelCount == 1
                ? AudioFormat.CHANNEL_OUT_MONO
                : AudioFormat.CHANNEL_OUT_STEREO;
        int minBuffer = AudioTrack.getMinBufferSize(sampleRate, channelMask, encoding);
        int bufferSize = Math.max(minBuffer, sampleRate * channelCount * 2 / 5);

        audioTrack = new AudioTrack.Builder()
                .setAudioAttributes(new AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build())
                .setAudioFormat(new AudioFormat.Builder()
                        .setEncoding(encoding)
                        .setSampleRate(sampleRate)
                        .setChannelMask(channelMask)
                        .build())
                .setTransferMode(AudioTrack.MODE_STREAM)
                .setBufferSizeInBytes(bufferSize)
                .build();
    }

    synchronized void play() {
        if (audioTrack != null) audioTrack.play();
    }

    synchronized void pause() {
        if (audioTrack != null) audioTrack.pause();
    }

    synchronized void stop() {
        if (audioTrack == null) return;
        audioTrack.pause();
        audioTrack.flush();
        audioTrack.stop();
    }

    void write(byte[] data) {
        if (data == null || data.length == 0) return;
        byte[] copy = data.clone();
        worker.post(() -> {
            AudioTrack current;
            synchronized (PcmPlayer.this) {
                current = audioTrack;
            }
            if (current != null && current.getPlayState() == AudioTrack.PLAYSTATE_PLAYING) {
                current.write(copy, 0, copy.length, AudioTrack.WRITE_BLOCKING);
            }
        });
    }

    synchronized int getPlayState() {
        if (audioTrack == null) return 0;
        switch (audioTrack.getPlayState()) {
            case AudioTrack.PLAYSTATE_PLAYING:
                return 1;
            case AudioTrack.PLAYSTATE_PAUSED:
                return 2;
            default:
                return 0;
        }
    }

    synchronized void release() {
        if (audioTrack == null) return;
        try {
            audioTrack.pause();
            audioTrack.flush();
            audioTrack.stop();
        } catch (IllegalStateException ignored) {
            // The track may already be stopped.
        }
        audioTrack.release();
        audioTrack = null;
    }

    void dispose() {
        release();
        worker.removeCallbacksAndMessages(null);
        workerThread.quitSafely();
    }
}
