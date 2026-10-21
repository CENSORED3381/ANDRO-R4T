package com.sec.app;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;

public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context ctx, Intent i) {
        Intent s = new Intent(ctx, TelegramService.class);
        if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(s);
        else ctx.startService(s);
    }
}
