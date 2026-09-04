package com.willl.stocktw

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray

/** 桌面小工具：顯示自選股前幾檔的即時報價（由 Flutter 端寫入 watchlist_json）。 */
class StockWidgetProvider : HomeWidgetProvider() {

    private val rowIds = intArrayOf(R.id.row1, R.id.row2, R.id.row3, R.id.row4, R.id.row5)
    private val nameIds = intArrayOf(R.id.name1, R.id.name2, R.id.name3, R.id.name4, R.id.name5)
    private val priceIds = intArrayOf(R.id.price1, R.id.price2, R.id.price3, R.id.price4, R.id.price5)
    private val changeIds =
        intArrayOf(R.id.change1, R.id.change2, R.id.change3, R.id.change4, R.id.change5)

    private val colorUp = Color.parseColor("#FF4D4F") // 漲：紅
    private val colorDown = Color.parseColor("#16C784") // 跌：綠
    private val colorFlat = Color.parseColor("#9AA6B6")

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.stock_widget_layout)

            val pendingIntent = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
            views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)

            val updatedAt = widgetData.getString("updatedAt", null)
            views.setTextViewText(
                R.id.widget_header,
                if (updatedAt != null) "自選股 · $updatedAt" else "自選股",
            )

            val json = widgetData.getString("watchlist_json", null)
            val items = try {
                if (json != null) JSONArray(json) else JSONArray()
            } catch (e: Exception) {
                JSONArray()
            }

            for (i in rowIds.indices) {
                if (i < items.length()) {
                    val o = items.getJSONObject(i)
                    views.setViewVisibility(rowIds[i], View.VISIBLE)
                    views.setTextViewText(nameIds[i], o.optString("name", "--"))
                    views.setTextViewText(priceIds[i], o.optString("price", "--"))
                    val change = o.optDouble("change", 0.0)
                    val color = if (change > 0) colorUp else if (change < 0) colorDown else colorFlat
                    views.setTextViewText(changeIds[i], o.optString("changeText", ""))
                    views.setTextColor(priceIds[i], color)
                    views.setTextColor(changeIds[i], color)
                } else {
                    views.setViewVisibility(rowIds[i], View.GONE)
                }
            }

            if (items.length() == 0) {
                views.setTextViewText(R.id.widget_header, "自選股（開 App 更新）")
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
