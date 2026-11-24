package com.jeffrey.clock

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import java.net.InetSocketAddress
import java.net.Socket

class MicService : Service() {
    companion object {
        const val STATUS_OFF = "off"
        const val STATUS_CONNECTING = "connecting"
        const val STATUS_STREAMING = "streaming"

        private const val ACTION_START = "com.jeffrey.clock.mic.START"
        private const val ACTION_STOP = "com.jeffrey.clock.mic.STOP"
        private const val EXTRA_HOST = "host"
        private const val EXTRA_PORT = "port"
        private const val CHANNEL_ID = "mic_stream"
        private const val NOTIFICATION_ID = 1
        private const val SAMPLE_RATE = 48000
        private const val CHUNK_BYTES = 1920
        private const val RETRY_MILLIS = 2000L
        private const val CONNECT_TIMEOUT = 3000

        private val mainHandler = Handler(Looper.getMainLooper())

        @Volatile
        var status: String = STATUS_OFF
            private set

        var listener: ((String) -> Unit)? = null

        private fun publish(value: String) {
            if (status == value) return
            status = value
            mainHandler.post { listener?.invoke(value) }
        }

        fun start(context: Context, host: String, port: Int) {
            val intent = Intent(context, MicService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_HOST, host)
                .putExtra(EXTRA_PORT, port)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, MicService::class.java))
            publish(STATUS_OFF)
        }
    }

    @Volatile
    private var session = 0

    @Volatile
    private var socket: Socket? = null

    private var worker: Thread? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            publish(STATUS_OFF)
            return START_NOT_STICKY
        }
        val host = intent?.getStringExtra(EXTRA_HOST)
        val port = intent?.getIntExtra(EXTRA_PORT, 0) ?: 0
        if (host.isNullOrEmpty() || port <= 0) {
            stopSelf()
            return START_NOT_STICKY
        }
        startInForeground(host, port)
        stopWorker()
        val id = session
        publish(STATUS_CONNECTING)
        worker = Thread { streamLoop(id, host, port) }.also { it.start() }
        return START_NOT_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        stopSelf()
        publish(STATUS_OFF)
    }

    override fun onDestroy() {
        stopWorker()
        publish(STATUS_OFF)
        super.onDestroy()
    }

    private fun stopWorker() {
        session++
        try {
            socket?.close()
        } catch (_: Exception) {
        }
        worker?.interrupt()
        worker = null
    }

    private fun startInForeground(host: String, port: Int) {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Microphone streaming",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        val stopIntent = PendingIntent.getService(
            this,
            0,
            Intent(this, MicService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val openIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("Streaming microphone")
            .setContentText("$host:$port")
            .setOngoing(true)
            .setContentIntent(openIntent)
            .addAction(
                Notification.Action.Builder(null, "Stop", stopIntent).build(),
            )
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun publishIf(id: Int, value: String) {
        if (id == session) publish(value)
    }

    @SuppressLint("MissingPermission")
    private fun streamLoop(id: Int, host: String, port: Int) {
        val minBuffer = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        val buffer = ByteArray(CHUNK_BYTES)
        while (id == session) {
            var record: AudioRecord? = null
            val s = Socket()
            socket = s
            try {
                publishIf(id, STATUS_CONNECTING)
                s.tcpNoDelay = true
                s.connect(InetSocketAddress(host, port), CONNECT_TIMEOUT)
                val output = s.getOutputStream()
                record = AudioRecord(
                    MediaRecorder.AudioSource.MIC,
                    SAMPLE_RATE,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    maxOf(minBuffer, CHUNK_BYTES * 4),
                )
                record.startRecording()
                publishIf(id, STATUS_STREAMING)
                while (id == session) {
                    val read = record.read(buffer, 0, buffer.size)
                    if (read > 0) output.write(buffer, 0, read)
                }
            } catch (_: Exception) {
            } finally {
                try {
                    record?.stop()
                } catch (_: Exception) {
                }
                record?.release()
                try {
                    s.close()
                } catch (_: Exception) {
                }
                if (socket === s) socket = null
            }
            if (id != session) break
            try {
                Thread.sleep(RETRY_MILLIS)
            } catch (_: InterruptedException) {
            }
        }
    }
}
