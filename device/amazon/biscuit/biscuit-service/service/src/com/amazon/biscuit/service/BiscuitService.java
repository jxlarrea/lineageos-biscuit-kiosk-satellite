package com.amazon.biscuit.service;

import android.app.Service;
import android.bluetooth.BluetoothAdapter;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.media.AudioManager;
import android.net.LocalSocket;
import android.net.wifi.WifiConfiguration;
import android.net.wifi.WifiManager;
import android.net.LocalSocketAddress;
import android.os.Binder;
import android.os.IBinder;
import android.os.RemoteException;

import java.io.BufferedReader;
import java.io.FileDescriptor;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.io.PrintWriter;
import java.util.List;

public final class BiscuitService extends Service {
    public static final class BootReceiver extends BroadcastReceiver {
        @Override
        public void onReceive(Context context, Intent intent) {
            Intent service = new Intent(context, BiscuitService.class);
            service.setAction(intent.getAction());
            service.putExtras(intent);
            context.startService(service);
        }
    }

    private static final String SOCKET = "biscuit-ledd";
    private static final String VOLUME_CHANGED = "android.media.VOLUME_CHANGED_ACTION";
    private static final String MIC_MUTE_CHANGED = "com.amazon.biscuit.service.MICROPHONE_MUTE_CHANGED";
    public static final String BLUETOOTH_PAIRING_MODE = "com.amazon.biscuit.service.BLUETOOTH_PAIRING_MODE";
    public static final String BLUETOOTH_OFF = "com.amazon.biscuit.service.BLUETOOTH_OFF";
    public static final String WIFI_ON = "com.amazon.biscuit.service.WIFI_ON";
    public static final String WIFI_OFF = "com.amazon.biscuit.service.WIFI_OFF";
    public static final String WIFI_CONNECT = "com.amazon.biscuit.service.WIFI_CONNECT";
    public static final String VOLUME_UP = "com.amazon.biscuit.service.VOLUME_UP";
    public static final String VOLUME_DOWN = "com.amazon.biscuit.service.VOLUME_DOWN";
    public static final String VOLUME_SET = "com.amazon.biscuit.service.VOLUME_SET";
    public static final String MIC_MUTE_ON = "com.amazon.biscuit.service.MICROPHONE_MUTE_ON";
    public static final String MIC_MUTE_OFF = "com.amazon.biscuit.service.MICROPHONE_MUTE_OFF";
    public static final String MIC_MUTE_TOGGLE = "com.amazon.biscuit.service.MICROPHONE_MUTE_TOGGLE";
    public static final String COUNTDOWN_PROGRESS = "com.amazon.biscuit.service.COUNTDOWN_PROGRESS";
    public static final String COUNTDOWN_CLEAR = "com.amazon.biscuit.service.COUNTDOWN_CLEAR";
    private static final String EXTRA_SSID = "ssid";
    private static final String EXTRA_PSK = "psk";
    private static final String EXTRA_VOLUME = "volume";
    private static final String EXTRA_COUNTDOWN_REMAINING_MS = "com.amazon.biscuit.service.EXTRA_COUNTDOWN_REMAINING_MS";
    private static final String EXTRA_COUNTDOWN_TOTAL_MS = "com.amazon.biscuit.service.EXTRA_COUNTDOWN_TOTAL_MS";
    private static final String EXTRA_STREAM_TYPE = "android.media.EXTRA_VOLUME_STREAM_TYPE";
    private static final String EXTRA_STREAM_VALUE = "android.media.EXTRA_VOLUME_STREAM_VALUE";
    private static final String EXTRA_MICROPHONE_MUTED = "com.amazon.biscuit.service.EXTRA_MICROPHONE_MUTED";
    private static final String EXTRA_FROM_BUTTON = "com.amazon.biscuit.service.EXTRA_FROM_BUTTON";
    private static final String VOLUME_BUTTON = "com.amazon.biscuit.service.VOLUME_BUTTON";
    private static final String EXTRA_DIRECTION = "direction";
    private static final int PAIRING_MODE_SECONDS = 300;
    private final Object mLock = new Object();
    private boolean mMicMuted;

    // The app holding the volume buttons, if any, and the token whose death
    // gives them back, so a crashed app never leaves the buttons dead.
    // Its own lock: mLock is held across slow daemon calls.
    private final Object mClaimLock = new Object();
    private IBinder mVolumeClaim;
    private String mVolumeClaimPackage;
    private final IBinder.DeathRecipient mVolumeClaimDeath = new IBinder.DeathRecipient() {
        public void binderDied() {
            synchronized (mClaimLock) {
                mVolumeClaim = null;
                mVolumeClaimPackage = null;
            }
        }
    };

    private final IBiscuitService.Stub mBinder = new IBiscuitService.Stub() {
        public boolean play(String name) throws RemoteException {
            checkName(name);
            return sendOk("PLAY " + name);
        }

        public boolean setFrame(String rgbHex72) throws RemoteException {
            checkFrame(rgbHex72);
            return sendOk("FRAME " + rgbHex72);
        }

        public boolean setVolume(int current, int max) throws RemoteException {
            if (current < 0 || max <= 0 || current > max) throw new RemoteException("bad volume");
            return sendOk("VOLUME " + current + " " + max);
        }

        public boolean setMicMuted(boolean muted) throws RemoteException {
            setRealMicMuted(muted);
            return true;
        }

        public boolean clear() throws RemoteException {
            return sendOk("OFF");
        }

        public String status() throws RemoteException {
            return send("STATUS");
        }

        public boolean claimVolumeButtons(IBinder token, boolean claimed) throws RemoteException {
            if (token == null) throw new RemoteException("missing token");
            String[] packages = getPackageManager().getPackagesForUid(Binder.getCallingUid());
            if (packages == null || packages.length == 0) return false;
            synchronized (mClaimLock) {
                if (!claimed) {
                    if (token != mVolumeClaim) return false;
                    releaseVolumeClaim();
                    return true;
                }
                if (token == mVolumeClaim) return true;
                releaseVolumeClaim();
                token.linkToDeath(mVolumeClaimDeath, 0);
                mVolumeClaim = token;
                mVolumeClaimPackage = packages[0];
                return true;
            }
        }

        public String systemUpdateStatus() throws RemoteException {
            return SystemUpdate.get(BiscuitService.this).status();
        }

        public boolean checkSystemUpdate() throws RemoteException {
            return SystemUpdate.get(BiscuitService.this).check();
        }

        public boolean installSystemUpdate() throws RemoteException {
            SystemUpdate update = SystemUpdate.get(BiscuitService.this);
            if (!update.mayInstall(Binder.getCallingUid())) throw new SecurityException("not the device owner");
            return update.install();
        }
    };

    // Callers hold mClaimLock.
    private void releaseVolumeClaim() {
        if (mVolumeClaim != null) {
            try {
                mVolumeClaim.unlinkToDeath(mVolumeClaimDeath, 0);
            } catch (RuntimeException ignored) { }
        }
        mVolumeClaim = null;
        mVolumeClaimPackage = null;
    }

    // A volume button press goes to the app that claimed the buttons.
    // False when nothing holds them, so the press changes the volume.
    private boolean forwardVolumeButton(Intent intent, String direction) {
        if (!intent.getBooleanExtra(EXTRA_FROM_BUTTON, false)) return false;
        String target;
        synchronized (mClaimLock) {
            target = mVolumeClaimPackage;
        }
        if (target == null) return false;
        Intent press = new Intent(VOLUME_BUTTON);
        press.setPackage(target);
        press.addFlags(Intent.FLAG_RECEIVER_FOREGROUND | Intent.FLAG_RECEIVER_REGISTERED_ONLY);
        press.putExtra(EXTRA_DIRECTION, direction);
        sendBroadcast(press);
        return true;
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())) {
            SystemUpdate.get(this).resume();
        } else if (intent != null && VOLUME_CHANGED.equals(intent.getAction())) {
            AudioManager audio = (AudioManager) getSystemService(AUDIO_SERVICE);
            int stream = intent.getIntExtra(EXTRA_STREAM_TYPE, AudioManager.STREAM_MUSIC);
            int current = intent.getIntExtra(EXTRA_STREAM_VALUE, audio.getStreamVolume(stream));
            try {
                sendOk("VOLUME " + current + " " + audio.getStreamMaxVolume(stream));
            } catch (RemoteException ignored) { }
        } else if (intent != null && MIC_MUTE_CHANGED.equals(intent.getAction())) {
            boolean muted = intent.getBooleanExtra(EXTRA_MICROPHONE_MUTED,
                    ((AudioManager) getSystemService(AUDIO_SERVICE)).isMicrophoneMute());
            mMicMuted = muted;
        } else if (intent != null && MIC_MUTE_TOGGLE.equals(intent.getAction())) {
            setRealMicMuted(!mMicMuted);
        } else if (intent != null && BLUETOOTH_PAIRING_MODE.equals(intent.getAction())) {
            startBluetoothPairingMode();
        } else if (intent != null && BLUETOOTH_OFF.equals(intent.getAction())) {
            stopBluetooth();
        } else if (intent != null && WIFI_ON.equals(intent.getAction())) {
            setWifiEnabled(true);
        } else if (intent != null && WIFI_OFF.equals(intent.getAction())) {
            setWifiEnabled(false);
        } else if (intent != null && WIFI_CONNECT.equals(intent.getAction())) {
            connectWifi(intent.getStringExtra(EXTRA_SSID), intent.getStringExtra(EXTRA_PSK));
        } else if (intent != null && VOLUME_UP.equals(intent.getAction())) {
            if (!forwardVolumeButton(intent, "up")) adjustVolume(AudioManager.ADJUST_RAISE);
        } else if (intent != null && VOLUME_DOWN.equals(intent.getAction())) {
            if (!forwardVolumeButton(intent, "down")) adjustVolume(AudioManager.ADJUST_LOWER);
        } else if (intent != null && VOLUME_SET.equals(intent.getAction())) {
            setVolume(intent.getIntExtra(EXTRA_VOLUME, -1));
        } else if (intent != null && COUNTDOWN_PROGRESS.equals(intent.getAction())) {
            setCountdown(intent.getLongExtra(EXTRA_COUNTDOWN_REMAINING_MS, -1),
                    intent.getLongExtra(EXTRA_COUNTDOWN_TOTAL_MS, -1));
        } else if (intent != null && COUNTDOWN_CLEAR.equals(intent.getAction())) {
            clearCountdown();
        } else if (intent != null && MIC_MUTE_ON.equals(intent.getAction())) {
            setRealMicMuted(true);
        } else if (intent != null && MIC_MUTE_OFF.equals(intent.getAction())) {
            setRealMicMuted(false);
        }
        return START_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) {
        return mBinder;
    }

    // dumpsys activity service com.amazon.biscuit.service/.BiscuitService,
    // which biscuit_service update status runs.
    @Override
    protected void dump(FileDescriptor fd, PrintWriter writer, String[] args) {
        writer.println("System update: " + SystemUpdate.get(this).status());
    }

    private static void checkName(String name) throws RemoteException {
        if (name == null || name.length() < 1 || name.length() > 64) throw new RemoteException("bad name");
        for (int i = 0; i < name.length(); i++) {
            char c = name.charAt(i);
            boolean ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
                    || (c >= '0' && c <= '9') || c == '_' || c == '-' || c == '.';
            if (!ok) throw new RemoteException("bad name");
        }
        if (name.indexOf("..") >= 0) throw new RemoteException("bad name");
    }

    private static void checkFrame(String frame) throws RemoteException {
        if (frame == null || frame.length() != 72) throw new RemoteException("bad frame");
        for (int i = 0; i < frame.length(); i++) {
            char c = frame.charAt(i);
            boolean ok = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
            if (!ok) throw new RemoteException("bad frame");
        }
    }

    private void setRealMicMuted(boolean muted) {
        ((AudioManager) getSystemService(AUDIO_SERVICE)).setMicrophoneMute(muted);
        mMicMuted = muted;
    }

    private void updateVolumeLed(AudioManager audio) {
        try {
            sendOk("VOLUME " + audio.getStreamVolume(AudioManager.STREAM_MUSIC)
                    + " " + audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC));
        } catch (RemoteException ignored) { }
    }

    private void adjustVolume(int direction) {
        AudioManager audio = (AudioManager) getSystemService(AUDIO_SERVICE);
        audio.adjustStreamVolume(AudioManager.STREAM_MUSIC, direction, 0);
        updateVolumeLed(audio);
    }

    private void setVolume(int volume) {
        AudioManager audio = (AudioManager) getSystemService(AUDIO_SERVICE);
        int max = audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC);
        if (volume < 0) volume = 0;
        if (volume > max) volume = max;
        audio.setStreamVolume(AudioManager.STREAM_MUSIC, volume, 0);
        updateVolumeLed(audio);
    }

    private void setCountdown(long remainingMs, long totalMs) {
        if (totalMs <= 0 || remainingMs < 0 || remainingMs > totalMs) return;
        if (remainingMs == 0) {
            clearCountdown();
            return;
        }
        try {
            sendOk("COUNTDOWN " + remainingMs + " " + totalMs);
        } catch (RemoteException ignored) { }
    }

    private void clearCountdown() {
        try {
            sendOk("CLEAR");
        } catch (RemoteException ignored) { }
    }

    private void startBluetoothPairingMode() {
        final BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
        if (adapter == null) return;
        if (!adapter.isEnabled()) adapter.enable();
        new Thread(new Runnable() {
            public void run() {
                for (int i = 0; i < 20 && !adapter.isEnabled(); i++) {
                    try { Thread.sleep(500); } catch (InterruptedException ignored) { return; }
                }
                if (adapter.isEnabled()) {
                    adapter.setScanMode(BluetoothAdapter.SCAN_MODE_CONNECTABLE_DISCOVERABLE,
                            PAIRING_MODE_SECONDS);
                }
            }
        }, "BiscuitBtPairingMode").start();
    }

    private void stopBluetooth() {
        BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
        if (adapter != null && adapter.isEnabled()) adapter.disable();
    }

    private void setWifiEnabled(boolean enabled) {
        WifiManager wifi = (WifiManager) getSystemService(WIFI_SERVICE);
        if (wifi == null) return;
        wifi.setWifiEnabled(enabled);
        if (enabled) wifi.reconnect();
    }

    private int findNetwork(WifiManager wifi, String ssid) {
        List<WifiConfiguration> configs = wifi.getConfiguredNetworks();
        if (configs == null) return -1;
        for (WifiConfiguration config : configs) {
            if (config != null && ssid.equals(config.SSID)) return config.networkId;
        }
        return -1;
    }

    private void connectWifi(String ssid, String psk) {
        if (ssid == null || ssid.length() == 0) return;
        WifiManager wifi = (WifiManager) getSystemService(WIFI_SERVICE);
        if (wifi == null) return;
        WifiConfiguration config = new WifiConfiguration();
        config.SSID = quote(ssid);
        if (psk == null || psk.length() == 0) {
            config.allowedKeyManagement.set(WifiConfiguration.KeyMgmt.NONE);
        } else {
            config.preSharedKey = isHexPsk(psk) ? psk : quote(psk);
            config.allowedKeyManagement.set(WifiConfiguration.KeyMgmt.WPA_PSK);
        }
        wifi.setWifiEnabled(true);
        int id = findNetwork(wifi, config.SSID);
        if (id >= 0) {
            config.networkId = id;
            id = wifi.updateNetwork(config);
        } else {
            id = wifi.addNetwork(config);
        }
        if (id >= 0) {
            wifi.enableNetwork(id, true);
            wifi.saveConfiguration();
            wifi.reconnect();
        }
    }

    private static String quote(String s) {
        return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\"";
    }

    private static boolean isHexPsk(String s) {
        if (s.length() != 64) return false;
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) return false;
        }
        return true;
    }

    private boolean sendOk(String command) throws RemoteException {
        return "OK".equals(send(command));
    }

    private String send(String command) throws RemoteException {
        synchronized (mLock) {
            LocalSocket socket = new LocalSocket();
            try {
                socket.connect(new LocalSocketAddress(SOCKET, LocalSocketAddress.Namespace.RESERVED));
                OutputStream out = socket.getOutputStream();
                out.write((command + "\n").getBytes("US-ASCII"));
                out.flush();
                BufferedReader in = new BufferedReader(new InputStreamReader(socket.getInputStream(), "US-ASCII"));
                String reply = in.readLine();
                if (reply == null) throw new RemoteException("no daemon reply");
                return reply;
            } catch (IOException e) {
                throw new RemoteException(e.toString());
            } finally {
                try { socket.close(); } catch (IOException ignored) { }
            }
        }
    }
}
