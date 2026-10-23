package com.amazon.biscuit.service;

interface IBiscuitService {
    boolean play(String name);
    boolean setFrame(String rgbHex72);
    boolean setVolume(int current, int max);
    boolean setMicMuted(boolean muted);
    boolean clear();
    String status();
    // Claim the volume buttons for the calling app while the token lives:
    // presses go out as VOLUME_BUTTON broadcasts to that app instead of
    // changing the volume. False with the same token gives them back.
    boolean claimVolumeButtons(IBinder token, boolean claimed);
    // System updates from the GitHub releases, as a JSON object: current,
    // latest, available, notes, url, state (idle, checking, downloading,
    // verifying, installing or failed), progress (the download, 0 to 1, only
    // while downloading), error (why the last install failed), checkError (why
    // the last check failed) and checked (when GitHub last answered, in ms).
    // A SYSTEM_UPDATE_CHANGED broadcast goes out when it changes.
    String systemUpdateStatus();
    // Ask GitHub for a newer release. False while an update runs.
    boolean checkSystemUpdate();
    // Download, verify and install the newest release, rebooting into TWRP
    // twice. Only the device owner, system and the shell may start it, others
    // get a SecurityException. False when there is no
    // newer release or an update already runs.
    boolean installSystemUpdate();
}
