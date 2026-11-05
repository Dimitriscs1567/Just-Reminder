package com.example.just_reminder

import android.content.Context
import com.example.just_reminder.WidgetStore.Kind

/**
 * How the widgets show a reminder's state (Product decisions → Look): teal
 * tile and ring with a thumbs-up while due, gray dashed ring with a slashed
 * thumb when missed, a check on a translucent tile when nothing is due. The
 * missed count is a neutral bubble, never red.
 */
object WidgetLook {
    /** The one-reminder widget's tile. */
    fun background(kind: Kind): Int = when (kind) {
        Kind.FIRING -> R.drawable.widget_background_firing
        Kind.DONE -> R.drawable.widget_background_done
        else -> R.drawable.widget_background_neutral
    }

    /** Text on [background]. */
    fun onBackground(kind: Kind): Int = when (kind) {
        Kind.FIRING -> R.color.widget_on_firing
        Kind.DONE -> R.color.widget_on_done
        else -> R.color.widget_on_neutral
    }

    /** The state icon; [inList] for a row of the list widget (neutral background). */
    fun icon(kind: Kind, inList: Boolean = false): Int? = when (kind) {
        Kind.FIRING -> R.drawable.widget_state_firing
        Kind.MISSED -> R.drawable.widget_state_missed
        Kind.DONE -> if (inList) R.drawable.widget_row_done else R.drawable.widget_state_done
        Kind.PAUSED -> R.drawable.widget_state_paused
        else -> null
    }

    /** What the state icon says to screen readers. */
    fun iconDescription(kind: Kind): Int = when (kind) {
        Kind.FIRING -> R.string.widget_state_firing
        Kind.MISSED -> R.string.widget_state_missed
        Kind.PAUSED -> R.string.widget_state_paused
        else -> R.string.widget_state_done
    }

    /** A list row's status: "Due · 1 missed", "Missed · 2", "Done", … */
    fun status(context: Context, state: WidgetStore.State): String {
        val missed = state.missed
        fun text(plain: Int, withCount: Int) =
            if (missed > 0) context.getString(withCount, missed) else context.getString(plain)
        return when (state.kind) {
            Kind.FIRING -> text(R.string.widget_status_due, R.string.widget_status_due_missed)
            Kind.MISSED -> text(R.string.widget_status_missed, R.string.widget_status_missed_count)
            Kind.DONE -> text(R.string.widget_status_done, R.string.widget_status_done_missed)
            Kind.PAUSED -> text(R.string.widget_status_paused, R.string.widget_status_paused_missed)
            Kind.ARCHIVED -> context.getString(R.string.widget_archived_short)
            Kind.DELETED -> context.getString(R.string.widget_deleted_short)
            Kind.UNCONFIGURED -> ""
        }
    }

    /** The compact widget's bubble only has room for the number. */
    fun countLabel(missed: Int): String = if (missed > 99) "99+" else missed.toString()
}
