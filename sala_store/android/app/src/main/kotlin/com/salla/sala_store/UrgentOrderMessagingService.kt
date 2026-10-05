package com.selafood.store

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

class UrgentOrderMessagingService : FlutterFirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        val data = message.data
        if (data["channelId"] != LOGICAL_URGENT_CHANNEL_ID) return
        if (data["type"] == "store_urgent_alert_resolved") {
            cancelUrgentOrderNotification(this, data["orderId"].orEmpty())
            return
        }
        if (data["type"] == "new_order") {
            // New-order push is intentionally deferred. Order state remains
            // available in realtime without a sound or system notification.
            cancelUrgentOrderNotification(this, data["orderId"].orEmpty())
        }
    }

    companion object {
        const val LOGICAL_URGENT_CHANNEL_ID = "salla_urgent_orders"
        const val FLUX_URGENT_CHANNEL_ID = "salla_urgent_orders_flux_v2"
        private const val URGENT_NOTIFICATION_GROUP = "salla_store_urgent_orders"
        private val activeUrgentNotifications = mutableMapOf<Int, Notification>()
        private val activeUrgentNotificationsLock = Any()
        private var activeUrgentNotificationsHydrated = false

        private fun fluxSoundUri(context: Context): Uri = Uri.parse(
            "android.resource://${context.packageName}/${R.raw.modern_flux_store_order}"
        )

        fun ensureUrgentOrdersChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val channel = NotificationChannel(
                FLUX_URGENT_CHANNEL_ID,
                "طلبات سلة العاجلة - فلو",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "تنبيهات الطلبات الجديدة والمهمة"
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 450, 180, 450, 180, 650)
                val attributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                setSound(fluxSoundUri(context), attributes)
                lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            }
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }

        fun showUrgentOrderNotification(
            context: Context,
            title: String,
            body: String,
            payloadData: Map<String, String>
        ) {
            ensureUrgentOrdersChannel(context)
            val idSeed = payloadData["orderId"].orEmpty().trim().ifEmpty {
                payloadData["orderNumber"].orEmpty().trim().ifEmpty {
                    System.currentTimeMillis().toString()
                }
            }
            val notificationId = notificationId(idSeed)
            val intent = Intent(context, MainActivity::class.java).apply {
                action = "FLUTTER_NOTIFICATION_CLICK"
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
                payloadData.forEach { (key, value) -> putExtra(key, value) }
            }
            val pendingIntentFlags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.FLAG_IMMUTABLE
                } else {
                    0
                }
            val pendingIntent = PendingIntent.getActivity(
                context,
                notificationId,
                intent,
                pendingIntentFlags
            )
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, FLUX_URGENT_CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(context)
            }
            val notification = builder
                .setSmallIcon(context.applicationInfo.icon)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(Notification.BigTextStyle().bigText(body))
                .setPriority(Notification.PRIORITY_HIGH)
                .setVisibility(Notification.VISIBILITY_PRIVATE)
                .setGroup(URGENT_NOTIFICATION_GROUP)
                .setContentIntent(pendingIntent)
                .setSound(fluxSoundUri(context))
                .setVibrate(longArrayOf(0, 450, 180, 450, 180, 650))
                .setOngoing(true)
                .setAutoCancel(false)
                .build()
                .apply {
                    flags = flags or Notification.FLAG_INSISTENT
                }

            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            synchronized(activeUrgentNotificationsLock) {
                hydrateActiveUrgentNotifications(manager)
                manager.notify(notificationId, notification)
                activeUrgentNotifications[notificationId] = notification
            }
        }

        fun cancelUrgentOrderNotification(context: Context, orderId: String) {
            val normalizedOrderId = orderId.trim()
            if (normalizedOrderId.isEmpty()) return
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val resolvedNotificationId = notificationId(normalizedOrderId)
            synchronized(activeUrgentNotificationsLock) {
                hydrateActiveUrgentNotifications(manager)
                activeUrgentNotifications.remove(resolvedNotificationId)
                manager.cancel(resolvedNotificationId)
                val remainingNotification = activeUrgentNotifications.entries.firstOrNull()?.let {
                    it.key to it.value
                }
                resumeRemainingUrgentAlert(manager, remainingNotification)
            }
        }

        fun cancelAllUrgentOrderNotifications(context: Context) {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            synchronized(activeUrgentNotificationsLock) {
                hydrateActiveUrgentNotifications(manager)
                activeUrgentNotifications.keys.toList().forEach(manager::cancel)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    manager.activeNotifications
                        .filter { it.notification.group == URGENT_NOTIFICATION_GROUP }
                        .forEach { manager.cancel(it.id) }
                }
                activeUrgentNotifications.clear()
            }
        }

        fun hasActiveUrgentAlerts(context: Context): Boolean {
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            return synchronized(activeUrgentNotificationsLock) {
                hydrateActiveUrgentNotifications(manager)
                activeUrgentNotifications.isNotEmpty()
            }
        }

        private fun hydrateActiveUrgentNotifications(manager: NotificationManager) {
            if (activeUrgentNotificationsHydrated) return
            activeUrgentNotificationsHydrated = true
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
            manager.activeNotifications
                .filter { it.notification.group == URGENT_NOTIFICATION_GROUP }
                .forEach { activeUrgentNotifications[it.id] = it.notification }
        }

        private fun resumeRemainingUrgentAlert(
            manager: NotificationManager,
            remainingNotification: Pair<Int, Notification>?
        ) {
            if (remainingNotification == null) return
            remainingNotification.second.flags =
                remainingNotification.second.flags or Notification.FLAG_INSISTENT
            manager.notify(remainingNotification.first, remainingNotification.second)
        }

        private fun notificationId(idSeed: String): Int = idSeed.hashCode() and Int.MAX_VALUE
    }
}
