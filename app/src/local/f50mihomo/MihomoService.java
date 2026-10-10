package local.f50mihomo;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.content.res.AssetManager;
import android.os.IBinder;
import android.os.PowerManager;
import java.io.File;
import java.io.FileOutputStream;
import java.io.FileWriter;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.text.SimpleDateFormat;
import java.util.Date;

/** Runs the bundled mihomo binary and restarts it when it exits. */
public class MihomoService extends Service {
    private static final String CHANNEL = "mihomo";
    private static final long MAX_LOG = 2L * 1024 * 1024;

    private Thread worker;
    private volatile boolean running;
    private volatile Process proc;
    private PowerManager.WakeLock wakeLock;

    @Override
    public void onCreate() {
        super.onCreate();
        NotificationManager nm = getSystemService(NotificationManager.class);
        nm.createNotificationChannel(new NotificationChannel(CHANNEL, "mihomo", NotificationManager.IMPORTANCE_LOW));
        Notification n = new Notification.Builder(this, CHANNEL)
                .setContentTitle("mihomo")
                .setContentText("proxy :7890  panel :19090/ui")
                .setSmallIcon(android.R.drawable.stat_sys_upload)
                .setOngoing(true)
                .build();
        startForeground(1, n);
        wakeLock = getSystemService(PowerManager.class)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "f50mihomo:run");
        wakeLock.acquire();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (worker == null) {
            running = true;
            worker = new Thread(new Runnable() {
                @Override
                public void run() {
                    loop();
                }
            }, "mihomo-supervisor");
            worker.start();
        }
        return START_STICKY;
    }

    private void loop() {
        long backoff = 2000;
        File home = getFilesDir();
        // The log lives in the panel directory under the controller secret, so only holders of the secret can fetch it
        // (http://<device>:19090/ui/<secret>/mihomo.log); there is no adb access to app files on this device.
        String key = readKey();
        File logDir = key.isEmpty() ? home : new File(home, "ui/" + key);
        File log = new File(logDir, "mihomo.log");
        while (running) {
            long started = System.currentTimeMillis();
            try {
                installAssets(home);
                logDir.mkdirs();
                if (log.length() > MAX_LOG) {
                    File old = new File(logDir, "mihomo.log.1");
                    old.delete();
                    log.renameTo(old);
                }
                note(log, "starting mihomo");
                String bin = getApplicationInfo().nativeLibraryDir + "/libmihomo.so";
                ProcessBuilder pb = new ProcessBuilder(bin, "-d", home.getAbsolutePath());
                pb.directory(home);
                pb.redirectErrorStream(true);
                pb.redirectOutput(ProcessBuilder.Redirect.appendTo(log));
                proc = pb.start();
                int code = proc.waitFor();
                note(log, "mihomo exited with " + code);
            } catch (InterruptedException e) {
                break;
            } catch (Exception e) {
                note(log, "start failed: " + e);
            }
            // A run that lasted a while resets the backoff; quick crashes back off up to a minute.
            backoff = System.currentTimeMillis() - started > 60000 ? 2000 : Math.min(backoff * 2, 60000);
            try {
                Thread.sleep(backoff);
            } catch (InterruptedException e) {
                break;
            }
        }
    }

    private String readKey() {
        try (InputStream in = getAssets().open("logkey")) {
            byte[] b = new byte[128];
            int n = in.read(b);
            return n > 0 ? new String(b, 0, n).trim() : "";
        } catch (IOException e) {
            return "";
        }
    }

    /** Copies the bundled assets into the data directory once per app version. */
    private void installAssets(File home) throws Exception {
        long version = getPackageManager().getPackageInfo(getPackageName(), 0).getLongVersionCode();
        File stamp = new File(home, ".assets-version");
        if (stamp.exists() && readAll(stamp).trim().equals(String.valueOf(version))) {
            return;
        }
        AssetManager am = getAssets();
        copyAsset(am, "config.yaml", new File(home, "config.yaml"));
        copyAsset(am, "country.mmdb", new File(home, "Country.mmdb"));
        File ui = new File(home, "ui");
        deleteTree(ui);
        copyTree(am, "ui", ui);
        try (FileWriter w = new FileWriter(stamp)) {
            w.write(String.valueOf(version));
        }
    }

    private static void copyTree(AssetManager am, String path, File dst) throws IOException {
        String[] children = am.list(path);
        if (children == null || children.length == 0) {
            copyAsset(am, path, dst);
            return;
        }
        dst.mkdirs();
        for (String c : children) {
            copyTree(am, path + "/" + c, new File(dst, c));
        }
    }

    private static void copyAsset(AssetManager am, String path, File dst) throws IOException {
        File tmp = new File(dst.getPath() + ".tmp");
        try (InputStream in = am.open(path); OutputStream out = new FileOutputStream(tmp)) {
            byte[] buf = new byte[65536];
            int n;
            while ((n = in.read(buf)) > 0) {
                out.write(buf, 0, n);
            }
        }
        if (!tmp.renameTo(dst)) {
            throw new IOException("rename " + tmp);
        }
    }

    private static void deleteTree(File f) {
        File[] children = f.listFiles();
        if (children != null) {
            for (File c : children) {
                deleteTree(c);
            }
        }
        f.delete();
    }

    private static String readAll(File f) throws IOException {
        try (InputStream in = new java.io.FileInputStream(f)) {
            java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
            byte[] buf = new byte[256];
            int n;
            while ((n = in.read(buf)) > 0) {
                out.write(buf, 0, n);
            }
            return out.toString();
        }
    }

    private static void note(File log, String msg) {
        try (FileWriter w = new FileWriter(log, true)) {
            w.write(new SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(new Date()) + " [service] " + msg + "\n");
        } catch (IOException ignored) {
        }
    }

    @Override
    public void onDestroy() {
        running = false;
        if (worker != null) {
            worker.interrupt();
        }
        Process p = proc;
        if (p != null) {
            p.destroy();
        }
        if (wakeLock != null && wakeLock.isHeld()) {
            wakeLock.release();
        }
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
