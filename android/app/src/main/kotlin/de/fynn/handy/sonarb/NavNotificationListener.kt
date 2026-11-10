package de.fynn.handy.sonarb

import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.provider.Settings
import io.flutter.plugin.common.EventChannel

/**
 * Liest die laufende Navigationsmitteilung von Google Maps mit. Mitteilungen anderer Apps werden
 * am Paketnamen verworfen, bevor ihr Inhalt angefasst wird. Nichts wird gespeichert oder
 * gesendet: Titel und Text liegen nur hier im Speicher und gehen an Dart, wenn sie sich ändern.
 *
 * Die Komponente ist im Manifest ausgeschaltet. Erst der Schalter in den Einstellungen schaltet
 * sie ein ([setEnabled]); vorher bindet Android sie nicht und weckt die App nicht.
 */
class NavNotificationListener : NotificationListenerService() {

    override fun onListenerConnected() {
        // Navigiert Maps schon, kommt die Mitteilung nicht noch einmal: einmal nachsehen.
        val active = try {
            activeNotifications
        } catch (e: SecurityException) {
            null
        }
        active?.firstOrNull { isNavigation(it) }?.let { read(it) }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (sbn.packageName != MAPS_PACKAGE) return
        if (!isNavigation(sbn)) return
        read(sbn)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        if (sbn.packageName != MAPS_PACKAGE) return
        if (sbn.key != activeKey) return
        activeKey = null
        val last = latest ?: return
        publish(last.copy(active = false))
    }

    private fun read(sbn: StatusBarNotification) {
        val n = sbn.notification
        val extras = n.extras
        fun text(key: String) = extras?.getCharSequence(key)?.toString()?.trim()?.takeIf { it.isNotEmpty() }
        val reading = Reading(
            title = text(Notification.EXTRA_TITLE),
            text = text(Notification.EXTRA_TEXT),
            subText = text(Notification.EXTRA_SUB_TEXT),
            bigText = text(Notification.EXTRA_BIG_TEXT),
            ongoing = sbn.isOngoing,
            category = n.category,
            active = true,
        )
        activeKey = sbn.key
        if (reading == latest) return
        publish(reading)
    }

    data class Reading(
        val title: String?,
        val text: String?,
        val subText: String?,
        val bigText: String?,
        val ongoing: Boolean,
        val category: String?,
        val active: Boolean,
    ) {
        /** Zeitpunkt des Lesens; nicht Teil des Vergleichs, sonst wäre jede Mitteilung neu. */
        val at: Long = System.currentTimeMillis()

        fun toMap(): Map<String, Any?> = mapOf(
            "title" to title,
            "text" to text,
            "subText" to subText,
            "bigText" to bigText,
            "ongoing" to ongoing,
            "category" to category,
            "active" to active,
            "at" to at,
        )
    }

    companion object {
        const val MAPS_PACKAGE = "com.google.android.apps.maps"

        /** Zuletzt gelesene Mitteilung, nur im Speicher. */
        @Volatile
        var latest: Reading? = null
            private set

        @Volatile
        private var activeKey: String? = null

        /** Ziel der Ereignisse, solange Dart zuhört. */
        @Volatile
        var sink: EventChannel.EventSink? = null

        private val main = Handler(Looper.getMainLooper())

        private fun isNavigation(sbn: StatusBarNotification) =
            sbn.isOngoing || sbn.notification.category == Notification.CATEGORY_NAVIGATION

        private fun publish(reading: Reading) {
            latest = reading
            val map = reading.toMap()
            main.post { sink?.success(map) }
        }

        private fun component(context: Context) =
            ComponentName(context, NavNotificationListener::class.java)

        /** Hat der Nutzer Sonarb den Zugriff auf Mitteilungen erlaubt? */
        fun granted(context: Context): Boolean {
            val flat = Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners",
            ) ?: return false
            return flat.split(':').any {
                ComponentName.unflattenFromString(it)?.packageName == context.packageName
            }
        }

        /** Systemseite, auf der der Nutzer den Zugriff erlaubt (ab Android 11 direkt für Sonarb). */
        fun settingsIntent(context: Context): android.content.Intent =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                android.content.Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS)
                    .putExtra(
                        Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME,
                        component(context).flattenToString(),
                    )
            } else {
                android.content.Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            }

        /** Schaltet die Komponente ein oder aus. Aus: Android bindet sie nicht mehr. */
        fun setEnabled(context: Context, enabled: Boolean) {
            val state = if (enabled) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            } else {
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            }
            val pm = context.packageManager
            // Nur bei einer Änderung: applyTo ruft das bei jeder Einstellung auf.
            if (pm.getComponentEnabledSetting(component(context)) == state) return
            pm.setComponentEnabledSetting(
                component(context),
                state,
                PackageManager.DONT_KILL_APP,
            )
            if (!enabled) {
                latest = null
                activeKey = null
            } else if (granted(context)) {
                // Nach dem Wiedereinschalten bindet Android den Dienst nicht von selbst neu.
                requestRebind(component(context))
            }
        }
    }
}
