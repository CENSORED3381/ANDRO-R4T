package com.sec.app;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.media.projection.MediaProjection;
import android.media.projection.MediaProjectionManager;
import android.os.IBinder;
import androidx.core.app.NotificationCompat;

public class ShotService extends Service {
    public static MediaProjection projection;
    public static int resultCode;
    public static Intent resultData;

    @Override
    public int onStartCommand(Intent i, int f, int id) {
        NotificationManager m = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        m.createNotificationChannel(new NotificationChannel("shot", "cap",
            NotificationManager.IMPORTANCE_LOW));

        Notification n = new NotificationCompat.Builder(this, "shot")
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(getString(R.string.shot_notif))
            .build();
        startForeground(2, n);

        // cria a projection com os resultados da consent activity
        try {
            MediaProjectionManager pm = (MediaProjectionManager)
                getSystemService(MEDIA_PROJECTION_SERVICE);
            projection = pm.getMediaProjection(resultCode, resultData);
            synchronized (ShotActivity.class) { ShotActivity.class.notifyAll(); }
        } catch (Exception e) {
            TgApi.send("shot service erro: " + e);
        }

        stopForeground(STOP_FOREGROUND_REMOVE);
        stopSelf();
        return START_NOT_STICKY;
    }

    @Override
    public IBinder onBind(Intent i) { return null; }
}
