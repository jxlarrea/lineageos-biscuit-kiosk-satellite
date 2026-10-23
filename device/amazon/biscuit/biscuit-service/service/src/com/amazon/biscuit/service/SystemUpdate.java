package com.amazon.biscuit.service;

import android.app.admin.DevicePolicyManager;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.PowerManager;
import android.os.SystemProperties;
import android.util.Base64;
import android.util.Log;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.KeyFactory;
import java.security.MessageDigest;
import java.security.PublicKey;
import java.security.Signature;
import java.security.spec.X509EncodedKeySpec;
import java.util.ArrayList;
import java.util.List;
import java.util.Properties;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

/**
 * System updates from the GitHub releases, installed through TWRP.
 *
 * A release carries the OTA zip and a SHA256withRSA signature of it made with
 * the key whose public half ships in /system/etc/biscuit-ota. The zip is
 * downloaded to /cache/biscuit-ota and checked against GitHub's digest and that
 * signature. twrp-update.sh then installs it, run by TWRP from an
 * openrecoveryscript. The bootloader always starts boot_a, so slot A gets the
 * update first. Once Android boots from it, slot B gets it too, the same order
 * the README gives for installing by hand.
 */
final class SystemUpdate {
    private static final String TAG = "BiscuitUpdate";

    static final String CHANGED = "com.amazon.biscuit.service.SYSTEM_UPDATE_CHANGED";
    static final String CHECK = "com.amazon.biscuit.service.SYSTEM_UPDATE_CHECK";
    static final String INSTALL = "com.amazon.biscuit.service.SYSTEM_UPDATE_INSTALL";

    private static final String RELEASES =
            "https://api.github.com/repos/jxlarrea/lineageos-biscuit-kiosk-satellite/releases?per_page=30";
    private static final File KEY = new File("/system/etc/biscuit-ota/release-key.pem");
    private static final File SCRIPT = new File("/system/etc/biscuit-ota/twrp-update.sh");
    private static final File DIR = new File("/cache/biscuit-ota");
    private static final File ZIP = new File(DIR, "update.zip");
    private static final File PART = new File(DIR, "update.zip.part");
    private static final File UPDATER = new File(DIR, "update-binary");
    private static final File STEP_SCRIPT = new File(DIR, "twrp-update.sh");
    private static final File SLOT = new File(DIR, "slot");
    private static final File RESULT = new File(DIR, "result");
    private static final File PENDING = new File(DIR, "pending");
    private static final File ERROR = new File(DIR, "error");
    private static final File TWRP_LOG = new File(DIR, "twrp.log");
    private static final File ORS = new File("/cache/recovery/openrecoveryscript");
    private static final String ORS_TEXT = "cmd /sbin/sh " + STEP_SCRIPT + "\nreboot\n";
    private static final String UPDATE_BINARY = "META-INF/com/google/android/update-binary";

    // Time on slot A before installing into slot B, so a release that boots
    // and then falls over is noticed while slot B still holds the last one.
    private static final long SLOT_B_DELAY_MS = 2 * 60 * 1000;
    private static final long TWRP_LOG_MAX = 256 * 1024;
    private static final int ROOT_UID = 0;
    private static final int SYSTEM_UID = 1000;
    private static final int SHELL_UID = 2000;

    private static SystemUpdate sInstance;

    static synchronized SystemUpdate get(Context context) {
        if (sInstance == null) sInstance = new SystemUpdate(context.getApplicationContext());
        return sInstance;
    }

    /** Root (adb) can check and install with a broadcast. Holding REBOOT is the guard. */
    public static final class Receiver extends BroadcastReceiver {
        @Override
        public void onReceive(Context context, Intent intent) {
            if (CHECK.equals(intent.getAction())) {
                get(context).check();
            } else if (INSTALL.equals(intent.getAction())) {
                get(context).install();
            }
        }
    }

    private final Context mContext;
    private final Handler mWorker;
    private final String mCurrent = SystemProperties.get("ro.biscuit.release", "");

    // Guarded by this.
    private String mState = "idle";
    private float mProgress = -1;
    private String mError = "";
    private String mCheckError = "";
    private String mLatest = "";
    private String mNotes = "";
    private String mReleaseUrl = "";
    private String mZipUrl = "";
    private String mSigUrl = "";
    private String mDigest = "";
    private long mZipSize;
    private long mChecked;

    private SystemUpdate(Context context) {
        mContext = context;
        HandlerThread thread = new HandlerThread("BiscuitUpdate");
        thread.start();
        mWorker = new Handler(thread.getLooper());
        mError = readText(ERROR).trim();
    }

    synchronized String status() {
        JSONObject json = new JSONObject();
        try {
            json.put("current", mCurrent);
            json.put("latest", mLatest.isEmpty() ? mCurrent : mLatest);
            json.put("available", !mLatest.isEmpty());
            json.put("notes", mNotes);
            json.put("url", mReleaseUrl);
            json.put("state", mState);
            if (mProgress >= 0) json.put("progress", mProgress);
            json.put("error", mError);
            json.put("checkError", mCheckError);
            json.put("checked", mChecked);
        } catch (JSONException e) {
            throw new RuntimeException(e);
        }
        return json.toString();
    }

    /** The device owner, system, the shell and root may install. */
    boolean mayInstall(int uid) {
        if (uid == ROOT_UID || uid == SYSTEM_UID || uid == SHELL_UID) return true;
        DevicePolicyManager dpm =
                (DevicePolicyManager) mContext.getSystemService(Context.DEVICE_POLICY_SERVICE);
        String[] packages = mContext.getPackageManager().getPackagesForUid(uid);
        if (dpm == null || packages == null) return false;
        for (String pkg : packages) {
            if (dpm.isDeviceOwnerApp(pkg)) return true;
        }
        return false;
    }

    // A check keeps a failed install's state and error, so the next look at
    // the status still says why it failed.
    boolean check() {
        final String previous;
        synchronized (this) {
            if (!isIdle()) return false;
            previous = mState;
            setState("checking", -1);
        }
        mWorker.post(new Runnable() {
            public void run() {
                String error = "";
                try {
                    fetchReleases();
                } catch (IOException | JSONException e) {
                    Log.w(TAG, "check failed", e);
                    error = "Could not check for updates: " + e.getMessage();
                }
                synchronized (SystemUpdate.this) {
                    mCheckError = error;
                }
                setState(previous, -1);
            }
        });
        return true;
    }

    boolean install() {
        synchronized (this) {
            if (!isIdle() || mLatest.isEmpty()) return false;
            mError = "";
            setState("downloading", 0);
        }
        ERROR.delete();
        mWorker.post(new Runnable() {
            public void run() {
                PowerManager.WakeLock lock = ((PowerManager) mContext.getSystemService(Context.POWER_SERVICE))
                        .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, TAG);
                lock.acquire();
                try {
                    download();
                    setState("verifying", -1);
                    prepare();
                    startSlot("a");
                } catch (IOException | UpdateFailure e) {
                    Log.w(TAG, "install failed", e);
                    cleanUp();
                    finish("failed", e.getMessage());
                } finally {
                    lock.release();
                }
            }
        });
        return true;
    }

    /** Called at boot: carries on with an update TWRP has just installed. */
    void resume() {
        mWorker.post(new Runnable() {
            public void run() {
                Properties pending = readProperties(PENDING);
                String step = pending.getProperty("step", "");
                String version = pending.getProperty("version", "");
                String result = readText(RESULT).trim();
                if (step.isEmpty()) {
                    cleanUp();
                    checkAfterBoot();
                    return;
                }
                Log.i(TAG, "slot " + step + " of " + version + ": " + result);
                if ("a".equals(step) && "ok a".equals(result)) {
                    synchronized (SystemUpdate.this) {
                        mLatest = "";
                        setState("installing", -1);
                    }
                    mWorker.postDelayed(new Runnable() {
                        public void run() {
                            try {
                                startSlot("b");
                            } catch (IOException e) {
                                Log.w(TAG, "slot b failed", e);
                                cleanUp();
                                finish("failed", "slot B: " + e.getMessage());
                            }
                        }
                    }, SLOT_B_DELAY_MS);
                    return;
                }
                cleanUp();
                if ("b".equals(step) && "ok b".equals(result)) {
                    finish("idle", "");
                } else if (result.isEmpty()) {
                    finish("failed", "slot " + step.toUpperCase() + ": TWRP did not run the update");
                } else {
                    // twrp-update.sh writes "failed <slot> <reason>".
                    finish("failed", "slot " + step.toUpperCase() + ": "
                            + result.replaceFirst("^failed \\S* *", ""));
                }
                checkAfterBoot();
            }
        });
    }

    // Wi-Fi may still be joining right after boot.
    private void checkAfterBoot() {
        mWorker.postDelayed(new Runnable() {
            public void run() {
                check();
            }
        }, 60 * 1000);
    }

    private static final class UpdateFailure extends Exception {
        UpdateFailure(String message) {
            super(message);
        }
    }

    // Callers hold this.
    private boolean isIdle() {
        return "idle".equals(mState) || "failed".equals(mState);
    }

    private void setState(String state, float progress) {
        synchronized (this) {
            mState = state;
            mProgress = progress;
        }
        changed();
    }

    private void finish(String state, String error) {
        synchronized (this) {
            mState = state;
            mProgress = -1;
            mError = error;
        }
        if (error.isEmpty()) {
            ERROR.delete();
        } else {
            try {
                writeText(ERROR, error + "\n");
            } catch (IOException ignored) { }
        }
        changed();
    }

    private void changed() {
        Intent intent = new Intent(CHANGED);
        intent.addFlags(Intent.FLAG_RECEIVER_REGISTERED_ONLY);
        mContext.sendBroadcast(intent);
    }

    private void fetchReleases() throws IOException, JSONException {
        int[] current = parseVersion(mCurrent);
        JSONArray releases = new JSONArray(new String(get(RELEASES, 4 * 1024 * 1024), "UTF-8"));
        int[] newest = null;
        String latest = "", url = "", zipUrl = "", sigUrl = "", digest = "";
        long size = 0;
        StringBuilder notes = new StringBuilder();
        for (int i = 0; i < releases.length() && current != null; i++) {
            JSONObject release = releases.getJSONObject(i);
            if (release.optBoolean("draft") || release.optBoolean("prerelease")) continue;
            String tag = release.optString("tag_name");
            int[] version = parseVersion(tag);
            if (version == null || compare(version, current) <= 0) continue;
            JSONObject zip = null, sig = null;
            JSONArray assets = release.optJSONArray("assets");
            for (int j = 0; assets != null && j < assets.length(); j++) {
                JSONObject asset = assets.getJSONObject(j);
                String name = asset.optString("name");
                if (name.endsWith(".zip")) zip = asset;
                if (name.endsWith(".zip.sig")) sig = asset;
            }
            // A release without a signed zip can only be installed by hand.
            if (zip == null || sig == null) continue;
            String body = release.optString("body").trim();
            if (notes.length() > 0) notes.append("\n\n");
            notes.append("# Version ").append(tag).append("\n\n").append(body);
            if (newest == null || compare(version, newest) > 0) {
                newest = version;
                latest = tag;
                url = release.optString("html_url");
                zipUrl = zip.optString("browser_download_url");
                sigUrl = sig.optString("browser_download_url");
                digest = zip.optString("digest");
                size = zip.optLong("size");
            }
        }
        synchronized (this) {
            mLatest = latest;
            mNotes = notes.toString();
            mReleaseUrl = url;
            mZipUrl = zipUrl;
            mSigUrl = sigUrl;
            mDigest = digest;
            mZipSize = size;
            mChecked = System.currentTimeMillis();
        }
    }

    private void download() throws IOException, UpdateFailure {
        String zipUrl, sigUrl, digest;
        long size;
        synchronized (this) {
            zipUrl = mZipUrl;
            sigUrl = mSigUrl;
            digest = mDigest;
            size = mZipSize;
        }
        cleanUp();
        if (!DIR.isDirectory() && !DIR.mkdirs()) throw new IOException("cannot create " + DIR);
        // The zip plus the space TWRP's updater wants in /cache.
        if (DIR.getUsableSpace() < size + 64L * 1024 * 1024) {
            throw new UpdateFailure("not enough space in /cache for " + size + " bytes");
        }

        byte[] sig = get(sigUrl, 64 * 1024);
        Signature verifier;
        MessageDigest sha256;
        try {
            verifier = Signature.getInstance("SHA256withRSA");
            verifier.initVerify(releaseKey());
            sha256 = MessageDigest.getInstance("SHA-256");
        } catch (Exception e) {
            throw new UpdateFailure("cannot load the release key: " + e);
        }

        HttpURLConnection connection = open(zipUrl);
        long done = 0;
        int lastPercent = -1;
        try (InputStream in = connection.getInputStream();
             OutputStream out = new FileOutputStream(PART)) {
            byte[] buffer = new byte[64 * 1024];
            int n;
            while ((n = in.read(buffer)) > 0) {
                out.write(buffer, 0, n);
                sha256.update(buffer, 0, n);
                verifier.update(buffer, 0, n);
                done += n;
                int percent = size > 0 ? (int) (done * 100 / size) : 0;
                if (percent != lastPercent) {
                    lastPercent = percent;
                    setState("downloading", Math.min(percent, 100) / 100f);
                }
            }
        } catch (java.security.SignatureException e) {
            throw new UpdateFailure("cannot verify the signature: " + e);
        } finally {
            connection.disconnect();
        }
        if (size > 0 && done != size) throw new UpdateFailure("downloaded " + done + " of " + size + " bytes");
        String hex = toHex(sha256.digest());
        if (!digest.isEmpty() && !digest.equalsIgnoreCase("sha256:" + hex)) {
            throw new UpdateFailure("the download does not match GitHub's checksum");
        }
        try {
            if (!verifier.verify(sig)) throw new UpdateFailure("the release signature does not match");
        } catch (java.security.SignatureException e) {
            throw new UpdateFailure("the release signature is not valid: " + e.getMessage());
        }
        if (!PART.renameTo(ZIP)) throw new IOException("cannot rename " + PART);
    }

    private void prepare() throws IOException, UpdateFailure {
        String latest;
        synchronized (this) {
            latest = mLatest;
        }
        try (ZipFile zip = new ZipFile(ZIP)) {
            Properties props = new Properties();
            ZipEntry buildProp = zip.getEntry("system/build.prop");
            if (buildProp == null) throw new UpdateFailure("the zip has no system/build.prop");
            try (InputStream in = zip.getInputStream(buildProp)) {
                props.load(in);
            }
            if (!"biscuit".equals(props.getProperty("ro.product.device"))) {
                throw new UpdateFailure("the zip is not for the Echo Dot");
            }
            String version = props.getProperty("ro.biscuit.release", "");
            if (!latest.equals(version)) {
                throw new UpdateFailure("the zip says it is " + version + ", not " + latest);
            }
            ZipEntry updater = zip.getEntry(UPDATE_BINARY);
            if (updater == null) throw new UpdateFailure("the zip has no update-binary");
            try (InputStream in = zip.getInputStream(updater)) {
                copy(in, UPDATER);
            }
        }
        try (InputStream in = new FileInputStream(SCRIPT)) {
            copy(in, STEP_SCRIPT);
        }
        writeText(PENDING, "version=" + latest + "\nstep=a\n");
    }

    // Reboots into TWRP to install /cache/biscuit-ota/update.zip into the slot.
    private void startSlot(String slot) throws IOException {
        Properties pending = readProperties(PENDING);
        writeText(PENDING, "version=" + pending.getProperty("version", "") + "\nstep=" + slot + "\n");
        RESULT.delete();
        trimTwrpLog();
        writeText(SLOT, slot + "\n");
        writeText(ORS, ORS_TEXT);
        setState("installing", -1);
        Log.i(TAG, "rebooting into TWRP to install into slot " + slot);
        ((PowerManager) mContext.getSystemService(Context.POWER_SERVICE)).reboot("recovery");
    }

    // Everything but the error and TWRP's log.
    private static void cleanUp() {
        for (File file : new File[] { ZIP, PART, UPDATER, STEP_SCRIPT, SLOT, RESULT, PENDING }) {
            file.delete();
        }
        trimTwrpLog();
    }

    private static void trimTwrpLog() {
        if (TWRP_LOG.length() > TWRP_LOG_MAX) TWRP_LOG.delete();
    }

    private static PublicKey releaseKey() throws Exception {
        StringBuilder base64 = new StringBuilder();
        for (String line : readText(KEY).split("\n")) {
            if (!line.startsWith("-----")) base64.append(line.trim());
        }
        byte[] der = Base64.decode(base64.toString(), Base64.DEFAULT);
        return KeyFactory.getInstance("RSA").generatePublic(new X509EncodedKeySpec(der));
    }

    private static HttpURLConnection open(String url) throws IOException {
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        connection.setConnectTimeout(20000);
        connection.setReadTimeout(60000);
        connection.setRequestProperty("User-Agent", "biscuit-system-update");
        int code = connection.getResponseCode();
        if (code != HttpURLConnection.HTTP_OK) {
            connection.disconnect();
            throw new IOException("HTTP " + code + " from " + url);
        }
        return connection;
    }

    private static byte[] get(String url, int limit) throws IOException {
        HttpURLConnection connection = open(url);
        try (InputStream in = connection.getInputStream()) {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buffer = new byte[16 * 1024];
            int n;
            while ((n = in.read(buffer)) > 0) {
                out.write(buffer, 0, n);
                if (out.size() > limit) throw new IOException("too large: " + url);
            }
            return out.toByteArray();
        } finally {
            connection.disconnect();
        }
    }

    /** 2026.10.3 as {2026, 10, 3}. A -dev build counts as the release it follows. */
    static int[] parseVersion(String version) {
        if (version == null) return null;
        int dash = version.indexOf('-');
        if (dash >= 0) version = version.substring(0, dash);
        String[] parts = version.split("\\.");
        if (parts.length != 3) return null;
        int[] result = new int[3];
        try {
            for (int i = 0; i < 3; i++) result[i] = Integer.parseInt(parts[i]);
        } catch (NumberFormatException e) {
            return null;
        }
        return result;
    }

    static int compare(int[] a, int[] b) {
        for (int i = 0; i < 3; i++) {
            if (a[i] != b[i]) return a[i] < b[i] ? -1 : 1;
        }
        return 0;
    }

    private static String toHex(byte[] bytes) {
        StringBuilder hex = new StringBuilder();
        for (byte b : bytes) hex.append(String.format("%02x", b & 0xff));
        return hex.toString();
    }

    private static void copy(InputStream in, File file) throws IOException {
        try (OutputStream out = new FileOutputStream(file)) {
            byte[] buffer = new byte[64 * 1024];
            int n;
            while ((n = in.read(buffer)) > 0) out.write(buffer, 0, n);
        }
    }

    private static void writeText(File file, String text) throws IOException {
        try (FileOutputStream out = new FileOutputStream(file)) {
            out.write(text.getBytes("UTF-8"));
            out.getFD().sync();
        }
    }

    private static String readText(File file) {
        try (InputStream in = new FileInputStream(file)) {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buffer = new byte[4096];
            int n;
            while ((n = in.read(buffer)) > 0) out.write(buffer, 0, n);
            return out.toString("UTF-8");
        } catch (IOException e) {
            return "";
        }
    }

    private static Properties readProperties(File file) {
        Properties props = new Properties();
        try (InputStream in = new FileInputStream(file)) {
            props.load(in);
        } catch (IOException ignored) { }
        return props;
    }
}
