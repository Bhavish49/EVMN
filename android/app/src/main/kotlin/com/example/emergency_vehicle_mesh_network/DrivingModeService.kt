package com.example.emergency_vehicle_mesh_network

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.media.AudioManager
import android.media.ToneGenerator
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import java.security.SecureRandom
import java.util.Locale

class DrivingModeService : Service(), TextToSpeech.OnInitListener {
    companion object {
        const val ACTION_START = "com.example.evmn.DRIVING_START"
        const val ACTION_STOP = "com.example.evmn.DRIVING_STOP"
        private const val CHANNEL_ID = "evmn_driving_mode"
        private const val NOTIFICATION_ID = 7401
        private const val MANUFACTURER_ID = 0xFFFF
        private const val LEGACY_LENGTH = 10
        private const val PACKET_LENGTH = 24
        private val COLORS = listOf(
            "Black", "White", "Silver", "Gray", "Red", "Blue", "Green", "Yellow",
            "Brown", "Beige", "Orange", "Purple", "Gold", "Maroon", "Navy", "Other"
        )
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val random = SecureRandom()
    private val seenIds = LinkedHashSet<String>()
    private var scanner: android.bluetooth.le.BluetoothLeScanner? = null
    private var scanCallback: ScanCallback? = null
    private var advertiser: android.bluetooth.le.BluetoothLeAdvertiser? = null
    private var advertiseCallback: AdvertiseCallback? = null
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var vehicleType = "Sedan"
    private var vehicleColor = "Other"
    private var plateNumber = ""
    private var temporaryEmergency = false
    private var temporaryExpiresAt = 0L

    private val periodicEmergency = object : Runnable {
        override fun run() {
            if (!isEmergencyActive()) {
                stopAdvertising()
                mainHandler.postDelayed(this, 30_000)
                return
            }
            advertise(createMessage(if (vehicleType.equals("Ambulance", true)) 1 else 2))
            mainHandler.postDelayed(this, 4 * 60_000L)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        tts = TextToSpeech(applicationContext, this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopDrivingMode()
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_START) {
            vehicleType = intent.getStringExtra("vehicleType") ?: "Sedan"
            vehicleColor = intent.getStringExtra("vehicleColor") ?: "Other"
            plateNumber = intent.getStringExtra("plateNumber") ?: ""
            temporaryEmergency = intent.getBooleanExtra("temporaryEmergency", false)
            temporaryExpiresAt = intent.getLongExtra("temporaryExpiresAt", 0L)
            getSharedPreferences("driving_mode", MODE_PRIVATE).edit()
                .putString("vehicleType", vehicleType)
                .putString("vehicleColor", vehicleColor)
                .putString("plateNumber", plateNumber)
                .putBoolean("temporaryEmergency", temporaryEmergency)
                .putLong("temporaryExpiresAt", temporaryExpiresAt)
                .apply()
        } else {
            val saved = getSharedPreferences("driving_mode", MODE_PRIVATE)
            vehicleType = saved.getString("vehicleType", "Sedan") ?: "Sedan"
            vehicleColor = saved.getString("vehicleColor", "Other") ?: "Other"
            plateNumber = saved.getString("plateNumber", "") ?: ""
            temporaryEmergency = saved.getBoolean("temporaryEmergency", false)
            temporaryExpiresAt = saved.getLong("temporaryExpiresAt", 0L)
            if (!saved.getBoolean("enabled", false)) {
                stopSelf()
                return START_NOT_STICKY
            }
        }

        try {
            startForeground(NOTIFICATION_ID, buildNotification())
            if (!startBleScan()) {
                throw IllegalStateException("Bluetooth scanning did not start. Check Bluetooth and Nearby devices permission.")
            }
            getSharedPreferences("driving_mode", MODE_PRIVATE).edit()
                .putBoolean("enabled", true)
                .apply()
            MainActivity.emitDrivingMode(true)
            mainHandler.removeCallbacks(periodicEmergency)
            if (isEmergencyActive()) {
                advertise(createMessage(if (vehicleType.equals("Ambulance", true)) 1 else 2))
                mainHandler.postDelayed(periodicEmergency, 4 * 60_000L)
            } else {
                stopAdvertising()
            }
            MainActivity.completeDrivingStart()
        } catch (exception: Exception) {
            getSharedPreferences("driving_mode", MODE_PRIVATE).edit()
                .putBoolean("enabled", false)
                .apply()
            MainActivity.failDrivingStart(exception.message ?: "Android could not start Driving Mode.")
            stopDrivingMode()
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Deliberately leave the foreground service running when the app leaves Recents.
        super.onTaskRemoved(rootIntent)
    }

    override fun onInit(status: Int) {
        val localVoice = tts?.voices?.firstOrNull {
            !it.isNetworkConnectionRequired && it.locale.language == Locale.getDefault().language
        }
        ttsReady = status == TextToSpeech.SUCCESS && localVoice != null
        if (ttsReady) tts?.voice = localVoice
    }

    private fun startBleScan(): Boolean {
        if (!hasBlePermissions()) return false
        val manager = getSystemService(BluetoothManager::class.java) ?: return false
        val bleScanner = manager.adapter?.bluetoothLeScanner ?: return false
        scanner = bleScanner
        if (scanCallback != null) return true
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val data = result.scanRecord?.getManufacturerSpecificData(MANUFACTURER_ID) ?: return
                val bytes = ByteArray(data.size) { data[it] }
                if (bytes.size != LEGACY_LENGTH && bytes.size != PACKET_LENGTH) return
                val version = bytes[0].toInt() and 0xff
                if ((bytes.size == LEGACY_LENGTH && version != 1) ||
                    (bytes.size == PACKET_LENGTH && version != 2)) return
                processIncoming(bytes)
            }

            override fun onScanFailed(errorCode: Int) {
                updateNotification("Bluetooth scan paused (error $errorCode)")
                scanCallback = null
            }
        }
        try {
            val filters = listOf(1, 2).map { version ->
                ScanFilter.Builder()
                    .setManufacturerData(MANUFACTURER_ID, byteArrayOf(version.toByte()))
                    .build()
            }
            val settings = ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_BALANCED)
                .build()
            bleScanner.startScan(filters, settings, callback)
            scanCallback = callback
            updateNotification("Listening for nearby emergency alerts")
            return true
        } catch (_: SecurityException) {
            updateNotification("Bluetooth permission required")
            return false
        } catch (_: IllegalStateException) {
            updateNotification("Bluetooth scan unavailable")
            return false
        }
    }

    private fun processIncoming(bytes: ByteArray) {
        if (bytes.size < LEGACY_LENGTH) return
        val id = bytes.slice(2..5).joinToString("") { "%02x".format(it.toInt() and 0xff) }
        if (!seenIds.add(id)) return
        if (seenIds.size > 200) seenIds.remove(seenIds.first())
        val messageKind = bytes[1].toInt() and 0xff
        if (messageKind !in 1..2 || isExpired(bytes)) return

        val description = if (bytes.size == PACKET_LENGTH) {
            val metadata = bytes[10].toInt() and 0xff
            val colorIndex = metadata ushr 4
            val plateLength = metadata and 0x0f
            val color = COLORS.getOrElse(colorIndex) { "" }.takeIf { it != "Other" }.orEmpty()
            val plate = if (plateLength in 1..13) String(bytes, 11, plateLength, Charsets.US_ASCII) else ""
            listOf(color, plate).filter { it.isNotBlank() }.joinToString(" ")
        } else ""
        val phrase = if (messageKind == 1) {
            "Ambulance approaching. Please give way safely."
        } else if (description.isBlank()) {
            "Emergency vehicle approaching. Please give way safely."
        } else {
            "$description is in an emergency. Please give way safely."
        }
        announce(phrase)

        val ttl = bytes[6].toInt() and 0xff
        val hops = bytes[7].toInt() and 0xff
        if (ttl > 0 && hops < 15) {
            val forwarded = bytes.copyOf().apply {
                this[6] = (ttl - 1).toByte()
                this[7] = (hops + 1).toByte()
            }
            mainHandler.postDelayed({
                if (getSharedPreferences("driving_mode", MODE_PRIVATE).getBoolean("enabled", false)) {
                    advertise(forwarded)
                    mainHandler.postDelayed({ if (!isEmergencyActive()) stopAdvertising() }, 4_000)
                }
            }, 350L + random.nextInt(1_100))
        }
    }

    private fun isExpired(bytes: ByteArray): Boolean {
        val current = (System.currentTimeMillis() / 60_000L).toInt() and 0xffff
        val encoded = ((bytes[8].toInt() and 0xff) shl 8) or (bytes[9].toInt() and 0xff)
        val delta = ((encoded - current + 0x8000) and 0xffff) - 0x8000
        return delta <= 0 || delta > 5
    }

    private fun createMessage(kind: Int): ByteArray {
        val packet = ByteArray(PACKET_LENGTH)
        packet[0] = 2
        packet[1] = kind.toByte()
        val id = ByteArray(4).also(random::nextBytes)
        id.copyInto(packet, 2)
        packet[6] = 4
        packet[7] = 0
        val expiry = ((System.currentTimeMillis() / 60_000L) + 5).toInt() and 0xffff
        packet[8] = (expiry ushr 8).toByte()
        packet[9] = expiry.toByte()
        val colorIndex = COLORS.indexOf(vehicleColor).let { if (it < 0) COLORS.lastIndex else it }
        val plate = plateNumber.uppercase(Locale.ROOT).filter { it.isLetterOrDigit() || it == '-' }.take(13)
        packet[10] = ((colorIndex shl 4) or plate.length).toByte()
        plate.toByteArray(Charsets.US_ASCII).copyInto(packet, 11)
        return packet
    }

    private fun isEmergencyActive(): Boolean =
        vehicleType.equals("Ambulance", true) ||
            (temporaryEmergency && temporaryExpiresAt > System.currentTimeMillis())

    private fun advertise(packet: ByteArray) {
        if (!hasBlePermissions()) return
        val bleAdvertiser = getSystemService(BluetoothManager::class.java)?.adapter?.bluetoothLeAdvertiser ?: return
        advertiser = bleAdvertiser
        stopAdvertising()
        val callback = object : AdvertiseCallback() {
            override fun onStartFailure(errorCode: Int) {
                advertiseCallback = null
                updateNotification("Emergency broadcast failed ($errorCode)")
            }
        }
        try {
            val settings = AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_LOW)
                .setConnectable(false)
                .build()
            val data = AdvertiseData.Builder()
                .setIncludeDeviceName(false)
                .addManufacturerData(MANUFACTURER_ID, packet)
                .build()
            bleAdvertiser.startAdvertising(settings, data, callback)
            advertiseCallback = callback
            updateNotification(if (isEmergencyActive()) "Emergency alert active · listening nearby" else "Relaying a nearby emergency alert")
        } catch (_: SecurityException) {
            updateNotification("Bluetooth permission required")
        } catch (_: IllegalStateException) {
            updateNotification("Emergency broadcast unavailable")
        }
    }

    private fun announce(message: String) {
        val tone = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 55)
        tone.startTone(ToneGenerator.TONE_PROP_BEEP2, 180)
        mainHandler.postDelayed({
            tone.startTone(ToneGenerator.TONE_PROP_BEEP2, 300)
            mainHandler.postDelayed({
                tone.release()
                mainHandler.postDelayed({
                    if (ttsReady) tts?.speak(message, TextToSpeech.QUEUE_FLUSH, null, "evmn-background-alert")
                }, 1_000)
            }, 340)
        }, 220)
    }

    private fun stopAdvertising() {
        try {
            advertiseCallback?.let { advertiser?.stopAdvertising(it) }
        } catch (_: SecurityException) { }
        advertiseCallback = null
    }

    private fun stopDrivingMode() {
        getSharedPreferences("driving_mode", MODE_PRIVATE).edit()
            .putBoolean("enabled", false)
            .putBoolean("temporaryEmergency", false)
            .putLong("temporaryExpiresAt", 0L)
            .apply()
        mainHandler.removeCallbacksAndMessages(null)
        try { scanCallback?.let { scanner?.stopScan(it) } } catch (_: SecurityException) { }
        scanCallback = null
        stopAdvertising()
        stopForeground(STOP_FOREGROUND_REMOVE)
        MainActivity.emitDrivingMode(false)
        stopSelf()
    }

    private fun hasBlePermissions(): Boolean {
        val required = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            listOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_ADVERTISE, Manifest.permission.BLUETOOTH_CONNECT)
        } else listOf(Manifest.permission.ACCESS_FINE_LOCATION)
        return required.all { ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "Driving Mode", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Ongoing Bluetooth alerts while Driving Mode is enabled"
                setShowBadge(false)
            }
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
    }

    private fun buildNotification(text: String = "Listening for nearby emergency alerts"): Notification {
        val stopIntent = Intent(this, DrivingModeService::class.java).apply { action = ACTION_STOP }
        val stopPendingIntent = PendingIntent.getService(
            this, 7402, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val openIntent = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = openIntent?.let {
            PendingIntent.getActivity(this, 7403, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_evmn)
            .setContentTitle("You are in Driving Mode")
            .setContentText(if (text.isBlank()) "Tap to open EVMN and manage Driving Mode" else text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setContentIntent(contentIntent)
            .addAction(android.R.drawable.ic_media_pause, "Stop Driving Mode", stopPendingIntent)
            .build()
    }

    private fun updateNotification(text: String) {
        val manager = getSystemService(NotificationManager::class.java) ?: return
        manager.notify(NOTIFICATION_ID, buildNotification(text))
    }

    override fun onDestroy() {
        mainHandler.removeCallbacksAndMessages(null)
        try { scanCallback?.let { scanner?.stopScan(it) } } catch (_: SecurityException) { }
        scanCallback = null
        stopAdvertising()
        tts?.stop()
        tts?.shutdown()
        tts = null
        super.onDestroy()
    }
}
