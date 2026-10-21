package com.sec.app;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import org.json.*;

public class TgApi {
    private static final ExecutorService EXEC = Executors.newFixedThreadPool(2);

    private static String TOKEN;
    private static String CHAT_ID;

    public static void init(String token, String chatId) {
        TOKEN = token; CHAT_ID = chatId;
    }

    private static String url(String method) {
        return "https://api.telegram.org/bot" + TOKEN + "/" + method;
    }

    public static JSONArray getUpdates(long offset) throws Exception {
        HttpURLConnection c = (HttpURLConnection)
            new URL(url("getUpdates") + "?timeout=30&offset=" + offset).openConnection();
        c.setConnectTimeout(15000);
        c.setReadTimeout(45000);
        return new JSONObject(read(c.getInputStream())).getJSONArray("result");
    }

    public static void send(String text) {
        EXEC.execute(() -> {
            try {
                HttpURLConnection c = (HttpURLConnection) new URL(url("sendMessage")).openConnection();
                c.setRequestMethod("POST");
                c.setDoOutput(true);
                c.setConnectTimeout(15000);
                c.setReadTimeout(30000);
                OutputStream os = c.getOutputStream();
                os.write(("chat_id=" + CHAT_ID + "&text=" +
                    URLEncoder.encode(text, "UTF-8")).getBytes(StandardCharsets.UTF_8));
                os.close();
                c.getResponseCode();
            } catch (Exception ignored) {}
        });
    }

    public static void sendFile(File f, String caption) {
        try {
            String boundary = "----b" + System.currentTimeMillis();
            HttpURLConnection c = (HttpURLConnection) new URL(url("sendDocument")).openConnection();
            c.setRequestMethod("POST");
            c.setDoOutput(true);
            c.setConnectTimeout(15000);
            c.setReadTimeout(180000);
            c.setRequestProperty("Content-Type", "multipart/form-data; boundary=" + boundary);

            DataOutputStream d = new DataOutputStream(c.getOutputStream());
            d.writeBytes("--" + boundary + "\r\nContent-Disposition: form-data; name=\"chat_id\"\r\n\r\n" + CHAT_ID + "\r\n");
            if (caption != null)
                d.writeBytes("--" + boundary + "\r\nContent-Disposition: form-data; name=\"caption\"\r\n\r\n" + caption + "\r\n");
            d.writeBytes("--" + boundary + "\r\nContent-Disposition: form-data; name=\"document\"; filename=\"" + f.getName() + "\"\r\n\r\n");

            FileInputStream fi = new FileInputStream(f);
            byte[] buf = new byte[8192]; int n;
            while ((n = fi.read(buf)) > 0) d.write(buf, 0, n);
            fi.close();
            d.writeBytes("\r\n--" + boundary + "--\r\n");
            d.close();
            c.getResponseCode();
        } catch (Exception e) {
            send("erro upload " + f.getName() + ": " + e.getMessage());
        }
    }

    public static void sendPhoto(File f, String caption) {
        try {
            String boundary = "----p" + System.currentTimeMillis();
            HttpURLConnection c = (HttpURLConnection) new URL(url("sendPhoto")).openConnection();
            c.setRequestMethod("POST");
            c.setDoOutput(true);
            c.setConnectTimeout(15000);
            c.setReadTimeout(120000);
            c.setRequestProperty("Content-Type", "multipart/form-data; boundary=" + boundary);

            DataOutputStream d = new DataOutputStream(c.getOutputStream());
            d.writeBytes("--" + boundary + "\r\nContent-Disposition: form-data; name=\"chat_id\"\r\n\r\n" + CHAT_ID + "\r\n");
            if (caption != null)
                d.writeBytes("--" + boundary + "\r\nContent-Disposition: form-data; name=\"caption\"\r\n\r\n" + caption + "\r\n");
            d.writeBytes("--" + boundary + "\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"" + f.getName() + "\"\r\n\r\n");

            FileInputStream fi = new FileInputStream(f);
            byte[] buf = new byte[8192]; int n;
            while ((n = fi.read(buf)) > 0) d.write(buf, 0, n);
            fi.close();
            d.writeBytes("\r\n--" + boundary + "--\r\n");
            d.close();
            c.getResponseCode();
        } catch (Exception e) {
            send("erro sendPhoto: " + e.getMessage());
        }
    }

    public static String downloadFileId(String fileId) throws Exception {
        HttpURLConnection c = (HttpURLConnection)
            new URL(url("getFile") + "?file_id=" + URLEncoder.encode(fileId, "UTF-8")).openConnection();
        String path = new JSONObject(read(c.getInputStream()))
            .getJSONObject("result").getString("file_path");
        InputStream in = new URL("https://api.telegram.org/file/bot" + TOKEN + "/" + path).openStream();
        File out = new File("/sdcard/Download/" + new File(path).getName());
        FileOutputStream fo = new FileOutputStream(out);
        byte[] b = new byte[8192]; int n;
        while ((n = in.read(b)) > 0) fo.write(b, 0, n);
        fo.close(); in.close();
        return out.getAbsolutePath();
    }

    private static String read(InputStream i) throws IOException {
        BufferedReader r = new BufferedReader(new InputStreamReader(i, StandardCharsets.UTF_8));
        StringBuilder s = new StringBuilder(); String l;
        while ((l = r.readLine()) != null) s.append(l);
        r.close();
        return s.toString();
    }
}
