// build.gradle：請使用 Compose Material3（標準設定即可）

@file:OptIn(ExperimentalMaterial3Api::class)

package com.jeffrey.clock

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import kotlinx.coroutines.delay
import java.time.LocalTime
import java.time.format.DateTimeFormatter


class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 隱藏狀態列和導航列
        WindowCompat.setDecorFitsSystemWindows(window, false)
        val controller = WindowInsetsControllerCompat(window, window.decorView)
        controller.hide(WindowInsetsCompat.Type.systemBars())
        controller.systemBarsBehavior =
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        // 避開瀏海
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                android.view.WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
        // 螢幕常亮，不因閒置而熄滅或變暗
        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                ClockScreen()
            }
        }
    }
}

@Composable
fun ClockScreen() {
    val battery by rememberBatteryState()

    // 時間每秒更新；採用對齊整點的 delay，避免逐秒飄移
    val time by rememberTickingTime()

    val hh = time.format(DateTimeFormatter.ofPattern("HH"))
    val mm = time.format(DateTimeFormatter.ofPattern("mm"))
    val ss = time.format(DateTimeFormatter.ofPattern("ss"))

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF000000))
            .padding(horizontal = 48.dp)
    ) {
        // 右上角：電量
        BatteryBadge(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(top = 8.dp),
            percent = battery.percent,
            charging = battery.charging
        )

        // 中間：兩塊大面板
        Row(
            modifier = Modifier
                .fillMaxSize()
                .padding(top = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(48.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            DigitTile(
                modifier = Modifier
                    .weight(2f)
                    .fillMaxHeight(0.8f),
                text = hh
            )
            DigitTile(
                modifier = Modifier
                    .weight(2f)
                    .fillMaxHeight(0.8f),
                text = mm,
                bottomRight = ss // 右下角放秒數
            )
        }
    }
}

/**
 * 單塊數字面板：
 * - 圓角黑灰卡片
 * - 文字大小依面板高度自動換算為 sp，確保比例穩定
 */
@Composable
fun DigitTile(
    modifier: Modifier = Modifier,
    text: String,
    bottomRight: String? = null
) {
    Surface(
        modifier = modifier,
        color = Color(0xFF111111),
        shape = RoundedCornerShape(36.dp),
        tonalElevation = 0.dp,
        shadowElevation = 8.dp
    ) {
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center
        ) {
            // 依高度算字體大小（大數字約 75% 高；秒數約 18% 高）
            val costomFont = FontFamily(
                Font(R.font.storyscript_regular)
            )

            Row {
                Box(
                    modifier = Modifier
                        .width(125.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = text[0].toString(),
                        color = Color(0xFFBDBDBD),
                        fontFamily = costomFont,
                        fontSize = 250.sp
                    )
                }
                Box(
                    modifier = Modifier
                        .width(125.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = text[1].toString(),
                        color = Color(0xFFBDBDBD),
                        fontFamily = costomFont,
                        fontSize = 250.sp
                    )
                }
            }

            if (bottomRight != null) {
                Row(
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .padding(horizontal = 24.dp, vertical = 8.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .width(20.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = bottomRight[0].toString(),
                            color = Color(0xFFBDBDBD),
                            fontFamily = costomFont,
                            fontSize = 40.sp
                        )
                    }
                    Box(
                        modifier = Modifier
                            .width(20.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = bottomRight[1].toString(),
                            color = Color(0xFFBDBDBD),
                            fontFamily = costomFont,
                            fontSize = 40.sp
                        )
                    }
                }
            }
        }
    }
}

/** Dp 轉對應比例的 sp（用高度推 sp），避免系統縮放導致比例跑掉 */
@Composable
private fun Dp.toScaledSp(ratio: Float): TextUnit {
    val density = LocalDensity.current
    val sp = with(density) { (this@toScaledSp * ratio).toSp() }
    return sp
}

/** 取得當前時間並每秒對齊 tick */
@Composable
fun rememberTickingTime(): State<LocalTime> {
    return produceState(initialValue = LocalTime.now()) {
        while (true) {
            val now = System.currentTimeMillis()
            val remainder = now % 1000
            val wait = if (remainder < 500) 500 - remainder else 1000 - remainder
            delay(wait)
            value = LocalTime.now()
        }
    }
}

/* ------------------------ 電池狀態 ------------------------ */

data class BatteryState(val percent: Int, val charging: Boolean)

@Composable
fun rememberBatteryState(): State<BatteryState> {
    val context = LocalContext.current
    val state = remember { mutableStateOf(BatteryState(percent = 100, charging = false)) }

    DisposableEffect(Unit) {
        val filter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context?, intent: Intent?) {
                if (intent == null) return
                val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
                val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
                val pct =
                    if (level >= 0 && scale > 0) (level * 100f / scale).toInt() else state.value.percent
                val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
                val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                        status == BatteryManager.BATTERY_STATUS_FULL
                state.value = BatteryState(pct, charging)
            }
        }
        // 註冊一次立刻能拿到 ACTION_BATTERY_CHANGED 的 sticky broadcast
        context.registerReceiver(receiver, filter)

        onDispose { context.unregisterReceiver(receiver) }
    }

    return state
}

@Composable
fun BatteryBadge(modifier: Modifier = Modifier, percent: Int, charging: Boolean) {
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            contentAlignment = Alignment.Center
        ) {
            val costomFont = FontFamily(
                Font(R.font.storyscript_regular)
            )

            Image(
                modifier = Modifier,
                painter = painterResource(id = R.drawable.battery),
                contentDescription = "電池圖示",
            )
            Box(
                modifier = Modifier
                    .width(40.dp)
            ) {
                Box(
                    modifier = Modifier
                        .width(36.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        text = "$percent",
                        color = if (percent <= 30) Color.Red else Color(0xFFBDBDBD),
                        fontFamily = costomFont,
                        fontSize = 18.sp
                    )
                }
            }
        }
        Image(
            modifier = Modifier,
            painter = painterResource(id = R.drawable.bolt),
            contentDescription = "充電",
            alpha = if (charging) 1f else 0f // 1f 完全不透明，0f 完全透明
        )
    }
}
