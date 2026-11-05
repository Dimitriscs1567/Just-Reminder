package com.example.just_reminder

import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.util.Calendar
import java.util.Locale

/**
 * Reads what the Flutter app stores for the widgets (home_widget storage)
 * and works out what a reminder shows at a given moment.
 *
 * Mirrors lib/src/services/widget_storage_keys.dart and
 * lib/src/services/widget/widget_snapshot.dart (`widgetStatusAt`) — change
 * them together.
 */
object WidgetStore {
    fun widgetReminderKey(appWidgetId: Int) = "jr.widget.$appWidgetId"

    fun listWidgetKey(appWidgetId: Int) = "jr.listwidget.$appWidgetId"

    fun snapshotKey(reminderId: String) = "jr.reminder.$reminderId"

    enum class Kind { FIRING, MISSED, DONE, PAUSED, ARCHIVED, DELETED, UNCONFIGURED }

    data class State(
        val kind: Kind,
        val reminderId: String?,
        val displayName: String,
        /** Missed times of the day (while firing: of the due time's day). */
        val missed: Int = 0,
    )

    /** What one-reminder widget [appWidgetId] shows at [now] (epoch ms). */
    fun stateFor(data: SharedPreferences, appWidgetId: Int, now: Long): State {
        val reminderId = data.getString(widgetReminderKey(appWidgetId), null)
            ?: return State(Kind.UNCONFIGURED, null, "")
        return reminderState(data, reminderId, now)
    }

    /** The reminders list widget [appWidgetId] shows, in order; null when not set up. */
    fun listFor(data: SharedPreferences, appWidgetId: Int): List<String>? {
        val raw = data.getString(listWidgetKey(appWidgetId), null) ?: return null
        return try {
            val ids = JSONArray(raw)
            (0 until ids.length()).mapNotNull { ids.optString(it).ifEmpty { null } }.distinct()
        } catch (e: JSONException) {
            null
        }
    }

    /** What [reminderId] shows at [now]. */
    fun reminderState(data: SharedPreferences, reminderId: String, now: Long): State {
        val raw = data.getString(snapshotKey(reminderId), null)
            ?: return State(Kind.DELETED, reminderId, "")
        val snapshot = try {
            JSONObject(raw)
        } catch (e: JSONException) {
            return State(Kind.DELETED, reminderId, "")
        }
        val displayName = snapshot.optString("displayName", "")
        val state = snapshot.optString("state", "live")
        when (state) {
            "deleted" -> return State(Kind.DELETED, reminderId, displayName)
            "archived" -> return State(Kind.ARCHIVED, reminderId, displayName)
        }

        val replay = Replay(snapshot, now)
        replay.pending?.let {
            return State(Kind.FIRING, reminderId, displayName, replay.missedOn(it.date))
        }
        // A new day starts clean: only today's times count.
        val today = localDate(now)
        val missed = replay.missedOn(today)
        if (state == "paused") return State(Kind.PAUSED, reminderId, displayName, missed)
        val kind = if (replay.lastDate == today && replay.lastMissed) Kind.MISSED else Kind.DONE
        return State(kind, reminderId, displayName, missed)
    }

    /** One time of a reminder in a snapshot (epoch ms; date `YYYY-MM-DD`). */
    private class Time(val date: String, val start: Long, val due: Long, val missesAt: Long?)

    private fun time(json: JSONObject?): Time? {
        if (json == null || !json.has("start") || !json.has("due")) return null
        val start = json.optLong("start")
        return Time(
            // Version 1 snapshots have no dates: a time belongs to the day it
            // starts on.
            date = json.optString("date", "").ifEmpty { localDate(start) },
            start = start,
            due = json.optLong("due"),
            missesAt = if (json.isNull("missesAt")) null else json.optLong("missesAt"),
        )
    }

    private fun times(json: JSONArray?): List<Time> =
        if (json == null) emptyList() else (0 until json.length()).mapNotNull { time(json.optJSONObject(it)) }

    /**
     * The snapshot's runtime brought forward to [until]: times becoming due,
     * misses at their `missesAt`, in time order (a miss first at the same
     * instant); a due time replacing a still pending one misses that one.
     * Each miss counts for the day its time belongs to.
     */
    private class Replay(snapshot: JSONObject, until: Long) {
        var pending: Time? = time(snapshot.optJSONObject("pending"))
        var missedDate: String? = null
        var missedCount = 0
        var lastDate: String? = null
        var lastMissed = false

        init {
            snapshot.optJSONObject("missed")?.let {
                missedDate = it.optString("date", "").ifEmpty { null }
                missedCount = it.optInt("count", 0)
            }
            snapshot.optJSONObject("last")?.let {
                lastDate = it.optString("date", "").ifEmpty { null }
                lastMissed = it.optString("status") == "missed"
            }

            val asOf = snapshot.optLong("asOf", 0L)
            // (instant, 0 = missed / 1 = due, time)
            val events = mutableListOf<Triple<Long, Int, Time>>()
            pending?.let { due ->
                due.missesAt?.let { if (it <= until) events += Triple(it, 0, due) }
            }
            for (time in times(snapshot.optJSONArray("occurrences"))) {
                if (time.due <= asOf || time.due > until) continue
                events += Triple(time.due, 1, time)
                time.missesAt?.let { if (it <= until) events += Triple(it, 0, time) }
            }
            events.sortWith(compareBy<Triple<Long, Int, Time>>({ it.first }, { it.second }))
            for ((_, kind, time) in events) {
                if (kind == 0) {
                    if (pending?.start == time.start) miss()
                } else {
                    if (pending != null) miss()
                    pending = time
                }
            }
        }

        fun missedOn(date: String) = if (missedDate == date) missedCount else 0

        private fun miss() {
            val missed = pending ?: return
            val counted = missedDate
            if (counted == missed.date) {
                missedCount++
            } else if (counted == null || missed.date > counted) {
                missedDate = missed.date
                missedCount = 1
            }
            lastDate = missed.date
            lastMissed = true
            pending = null
        }
    }

    /** The local date of [millis] as `YYYY-MM-DD` (like Dart's `LocalDate.toIso`). */
    private fun localDate(millis: Long): String {
        val calendar = Calendar.getInstance().apply { timeInMillis = millis }
        return String.format(
            Locale.ROOT,
            "%04d-%02d-%02d",
            calendar.get(Calendar.YEAR),
            calendar.get(Calendar.MONTH) + 1,
            calendar.get(Calendar.DAY_OF_MONTH),
        )
    }
}
