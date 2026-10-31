package com.ryanheise.audioservice;

import android.app.Service;

/**
 * Lives in audio_service's package to reach {@link AudioService#instance},
 * which is package-private.
 */
public final class AudioServiceForeground {
    private AudioServiceForeground() {
    }

    /**
     * Takes the media card's service out of the foreground, and its
     * notification with it. With androidStopForegroundOnPause off, the service
     * stays in the foreground as the card goes idle, and audio_service then
     * only cancels the notification, which Android refuses for a foreground
     * service, and stops the service, which the app's own media browser keeps
     * bound: the notification stayed after the player had gone.
     */
    public static void stop() {
        // As an Object: the app does not compile against androidx.media, which
        // AudioService extends.
        Object service = AudioService.instance;
        if (service != null) {
            ((Service) service).stopForeground(Service.STOP_FOREGROUND_REMOVE);
        }
    }
}
