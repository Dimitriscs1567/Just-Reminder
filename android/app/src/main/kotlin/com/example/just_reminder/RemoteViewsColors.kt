package com.example.just_reminder

import android.content.Context
import android.os.Build
import android.widget.RemoteViews

/**
 * Sets a TextView's color from a color resource. Android 12+ hands the
 * launcher the resource, which resolves it in its own configuration, so
 * the widget follows light / dark mode at once (like backgrounds and icons,
 * which are resource references too). Before that the color is resolved
 * here and the widget catches up at its next update.
 */
fun RemoteViews.setTextColorResource(context: Context, viewId: Int, colorResource: Int) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        setColorStateList(viewId, "setTextColor", colorResource)
    } else {
        setTextColor(viewId, context.getColor(colorResource))
    }
}
