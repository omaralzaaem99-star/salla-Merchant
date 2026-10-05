package com.selafood.store

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val notificationsChannel = "com.selafood.store/notifications"
    private val sharedLocationChannelName = "com.selafood.store/shared_location"
    private val sharedLocationPreferences = "salla_store_shared_locations_v1"
    private val sharedLocationQueueKey = "pending"
    private var sharedLocationChannel: MethodChannel? = null
    private var notificationPlayer: MediaPlayer? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureSharedLocationIntent(intent)
        UrgentOrderMessagingService.ensureUrgentOrdersChannel(this)
        createStoreUpdatesChannel()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (captureSharedLocationIntent(intent)) {
            sharedLocationChannel?.invokeMethod("sharedLocationAvailable", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        sharedLocationChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            sharedLocationChannelName
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "peekPending" -> result.success(peekSharedLocation())
                    "ackPending" -> {
                        val id = call.argument<String>("id").orEmpty()
                        result.success(ackSharedLocation(id))
                    }
                    else -> result.notImplemented()
                }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, notificationsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "showUrgentAlert" -> {
                        val orderId = call.argument<String>("orderId").orEmpty()
                        val orderNumber = call.argument<String>("orderNumber").orEmpty()
                        notificationPlayer?.release()
                        notificationPlayer = null
                        UrgentOrderMessagingService.showUrgentOrderNotification(
                            this,
                            "طلب جديد ${orderNumber}".trim(),
                            "وصل طلب جديد ويحتاج موافقة المتجر.",
                            mapOf(
                                "type" to "new_order",
                                "channelId" to UrgentOrderMessagingService.LOGICAL_URGENT_CHANNEL_ID,
                                "orderId" to orderId,
                                "orderNumber" to orderNumber
                            )
                        )
                        result.success(true)
                    }
                    "cancelUrgentAlert" -> {
                        UrgentOrderMessagingService.cancelUrgentOrderNotification(
                            this,
                            call.argument<String>("orderId").orEmpty()
                        )
                        result.success(true)
                    }
                    "cancelAllUrgentAlerts" -> {
                        UrgentOrderMessagingService.cancelAllUrgentOrderNotifications(this)
                        result.success(true)
                    }
                    "playFluxNotification" -> {
                        playFluxNotification()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun sharedLocationQueue(): JSONArray {
        val raw = getSharedPreferences(sharedLocationPreferences, Context.MODE_PRIVATE)
            .getString(sharedLocationQueueKey, "[]")
            .orEmpty()
        return try {
            JSONArray(raw)
        } catch (_: Exception) {
            JSONArray()
        }
    }

    private fun saveSharedLocationQueue(queue: JSONArray) {
        getSharedPreferences(sharedLocationPreferences, Context.MODE_PRIVATE)
            .edit()
            .putString(sharedLocationQueueKey, queue.toString())
            .apply()
    }

    private fun captureSharedLocationIntent(incoming: Intent?): Boolean {
        val sourceIntent = incoming ?: return false
        val text = when (sourceIntent.action) {
            Intent.ACTION_VIEW -> sourceIntent.dataString.orEmpty()
            Intent.ACTION_SEND -> if (sourceIntent.type == "text/plain") {
                sourceIntent.getStringExtra(Intent.EXTRA_TEXT).orEmpty()
            } else {
                ""
            }
            else -> ""
        }.trim()
        if (text.isEmpty()) return false

        val queue = sharedLocationQueue()
        for (index in 0 until queue.length()) {
            if (queue.optJSONObject(index)?.optString("text") == text) return false
        }
        while (queue.length() >= 8) queue.remove(0)
        val id = "location_${System.currentTimeMillis()}_${text.hashCode()}"
        queue.put(JSONObject().put("id", id).put("text", text))
        saveSharedLocationQueue(queue)
        sourceIntent.action = null
        sourceIntent.data = null
        sourceIntent.removeExtra(Intent.EXTRA_TEXT)
        return true
    }

    private fun peekSharedLocation(): Map<String, String>? {
        val first = sharedLocationQueue().optJSONObject(0) ?: return null
        val id = first.optString("id").trim()
        val text = first.optString("text").trim()
        if (id.isEmpty() || text.isEmpty()) return null
        return mapOf("id" to id, "text" to text)
    }

    private fun ackSharedLocation(id: String): Boolean {
        if (id.isBlank()) return false
        val queue = sharedLocationQueue()
        var removed = false
        val kept = JSONArray()
        for (index in 0 until queue.length()) {
            val item = queue.optJSONObject(index) ?: continue
            if (!removed && item.optString("id") == id) {
                removed = true
            } else {
                kept.put(item)
            }
        }
        if (removed) saveSharedLocationQueue(kept)
        return removed
    }

    private fun fluxSoundUri(): Uri = Uri.parse(
        "android.resource://$packageName/${R.raw.modern_flux_store_order}"
    )

    private fun createStoreUpdatesChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            "salla_store_updates_flux_v1",
            "تحديثات طلبات سلة - فلو",
            NotificationManager.IMPORTANCE_DEFAULT
        ).apply {
            description = "تنبيهات تغيرات الطلبات والإلغاءات"
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 220, 120, 220)
            val attributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            setSound(fluxSoundUri(), attributes)
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(channel)
    }

    private fun playFluxNotification() {
        if (UrgentOrderMessagingService.hasActiveUrgentAlerts(this)) return
        notificationPlayer?.release()
        notificationPlayer = MediaPlayer.create(
            this,
            R.raw.modern_flux_store_order
        )?.apply {
            setOnCompletionListener { completed ->
                completed.release()
                if (notificationPlayer === completed) notificationPlayer = null
            }
            start()
        }
    }

    override fun onDestroy() {
        sharedLocationChannel?.setMethodCallHandler(null)
        sharedLocationChannel = null
        notificationPlayer?.release()
        notificationPlayer = null
        super.onDestroy()
    }
}
