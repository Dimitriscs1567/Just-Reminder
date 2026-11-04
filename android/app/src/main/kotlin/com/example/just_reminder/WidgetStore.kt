package com.example.just_reminder

import android.content.SharedPreferences
import org.json.JSONException
import org.json.JSONObject

/**
 * Reads what the Flutter app stores for the widgets (home_widget storage).
 *
 * Mirrors lib/src/services/widget_storage_keys.dart and
 * lib/src/services/widget/widget_snapshot.dart — change them together.
 */
object WidgetStore {
    fun widgetReminderKey(appWidgetId: Int) = "jr.widget.$appWidgetId"

    fun snapshotKey(reminderId: String) = "jr.reminder.$reminderId"

    enum class Kind { WAITING, CLEAR, ARCHIVED, DELETED, UNCONFIGURED }

    data class State(
        val kind: Kind,
        val reminderId: String?,
        val displayName: String,
        /** Missed activations before the waiting one. */
        val missed: Int = 0,
    )

    /** What widget [appWidgetId] shows at [now] (epoch ms). */
    fun stateFor(data: SharedPreferences, appWidgetId: Int, now: Long): State {
        val reminderId = data.getString(widgetReminderKey(appWidgetId), null)
            ?: return State(Kind.UNCONFIGURED, null, "")
        val raw = data.getString(snapshotKey(reminderId), null)
            ?: return State(Kind.DELETED, reminderId, "")
        val snapshot = try {
            JSONObject(raw)
        } catch (e: JSONException) {
            return State(Kind.DELETED, reminderId, "")
        }
        val displayName = snapshot.optString("displayName", "")
        when (snapshot.optString("state", "live")) {
            "deleted" -> return State(Kind.DELETED, reminderId, displayName)
            "archived" -> return State(Kind.ARCHIVED, reminderId, displayName)
        }

        // waiting = (pendingAt != null ? 1 + missedCount : 0)
        //         + activations in (asOf, now]
        val asOf = snapshot.optLong("asOf", 0L)
        val base = if (snapshot.isNull("pendingAt")) 0 else 1 + snapshot.optInt("missedCount", 0)
        var due = 0
        snapshot.optJSONArray("upcoming")?.let { upcoming ->
            for (i in 0 until upcoming.length()) {
                val time = upcoming.optLong(i)
                if (time > asOf && time <= now) due++
            }
        }
        val total = base + due
        return if (total > 0) {
            State(Kind.WAITING, reminderId, displayName, missed = total - 1)
        } else {
            State(Kind.CLEAR, reminderId, displayName)
        }
    }
}
