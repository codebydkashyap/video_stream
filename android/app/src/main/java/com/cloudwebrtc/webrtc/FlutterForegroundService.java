package com.cloudwebrtc.webrtc;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;

import androidx.annotation.Nullable;
import androidx.core.app.NotificationCompat;

public class FlutterForegroundService extends Service {

    private static final String CHANNEL_ID = "screen_share_channel";
    private static final int NOTIFICATION_ID = 1;

    @Override
    public void onCreate() {
        super.onCreate();
        createNotificationChannel();
    }

    @SuppressWarnings("deprecation")
    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String title = "Screen Sharing";
        String body = "You are sharing your screen...";

        boolean isActive = false;
        if (intent != null) {
            if (intent.hasExtra("title")) {
                title = intent.getStringExtra("title");
            }
            if (intent.hasExtra("body")) {
                body = intent.getStringExtra("body");
            }
            isActive = "active".equals(intent.getStringExtra("mode"));
        }

        Notification notification = new NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle(title)
                .setContentText(body)
                .setSmallIcon(android.R.drawable.ic_menu_camera)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .build();

        // Android 10+ requires specifying the type.
        // Android 14+ will CRASH if MEDIA_PROJECTION is started before permission is granted.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            int type = 0; // Default or None
            if (isActive) {
                type = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION;
            } else if (Build.VERSION.SDK_INT >= 34) {
               // On Android 14+, type 0 falls back to manifest types, which would crash if it's mediaProjection.
               // We use shortService (2048) temporarily until we get the token.
               type = 2048; // ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE
            } else {
               // Pre-Android 14, we can set it early
               type = ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION;
            }
            // If type is 2048 on Android 14 (API 34)+ it starts as shortService.
            // We then "upgrade" it to MEDIA_PROJECTION later when isActive is true.
            startForeground(NOTIFICATION_ID, notification, type);
        } else {
            startForeground(NOTIFICATION_ID, notification);
        }

        return START_NOT_STICKY;
    }

    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                    CHANNEL_ID,
                    "Screen Sharing",
                    NotificationManager.IMPORTANCE_LOW
            );
            channel.setDescription("Notification channel for screen sharing foreground service");
            NotificationManager manager = getSystemService(NotificationManager.class);
            if (manager != null) {
                manager.createNotificationChannel(channel);
            }
        }
    }

    @SuppressWarnings("deprecation")
    @Override
    public void onDestroy() {
        // stopForeground(boolean) is deprecated in API 33. Use stopForeground(int) for API 24+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(Service.STOP_FOREGROUND_REMOVE);
        } else {
            stopForeground(true);
        }
        super.onDestroy();
    }
}
