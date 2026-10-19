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
}
