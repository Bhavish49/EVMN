package com.example.emergency_vehicle_mesh_network

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Handler
import android.os.Looper
import android.os.Build
import android.speech.tts.TextToSpeech
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity(), TextToSpeech.OnInitListener {
    companion object {
        private const val METHOD_CHANNEL = "evmn/ble"
        private const val EVENT_CHANNEL = "evmn/ble_events"
        private const val REQUEST_BLE_PERMISSIONS = 9174
        // 0xFFFF is reserved by the Bluetooth SIG for internal testing only.
        private const val TEST_MANUFACTURER_ID = 0xFFFF
        @Volatile private var drivingModeEventSink: EventChannel.EventSink? = null
        @Volatile private var pendingDrivingStartResult: MethodChannel.Result? = null

        fun emitDrivingMode(enabled: Boolean) {
            drivingModeEventSink?.success(mapOf("type" to "drivingMode", "enabled" to enabled))
        }

        fun completeDrivingStart() {
            pendingDrivingStartResult?.success(null)
            pendingDrivingStartResult = null
        }

        fun failDrivingStart(message: String) {
            pendingDrivingStartResult?.error("DRIVING_SERVICE_FAILED", message, null)
            pendingDrivingStartResult = null
        }
    }

    private var eventSink: EventChannel.EventSink? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var scanner: BluetoothLeScanner? = null
    private var advertiser: BluetoothLeAdvertiser? = null
    private var scanCallback: ScanCallback? = null
    private var advertiseCallback: AdvertiseCallback? = null
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private val seenDeviceAddresses = mutableSetOf<String>()

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        tts = TextToSpeech(this, this)
    }

    override fun onInit(status: Int) {
        val localVoice = tts?.voices?.firstOrNull {
            !it.isNetworkConnectionRequired && it.locale.language == Locale.getDefault().language
        }
        ttsReady = status == TextToSpeech.SUCCESS && localVoice != null
        if (ttsReady) tts?.voice = localVoice
        eventSink?.success(mapOf("type" to "tts", "ready" to ttsReady))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val bluetoothManager = getSystemService(BluetoothManager::class.java)
        val adapter = bluetoothManager?.adapter

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(adapter != null && packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH_LE))
                "hasBlePermissions" -> result.success(hasBlePermissions())
                "isBluetoothEnabled" -> result.success(isBluetoothEnabled())
                "requestPermissions" -> requestBlePermissions(result)
                "isBackgroundDriving" -> {
                    val savedEnabled = getSharedPreferences("driving_mode", MODE_PRIVATE)
                        .getBoolean("enabled", false)
                    val running = (getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager)
                        .getRunningServices(Int.MAX_VALUE)
                        .any { it.service.className == DrivingModeService::class.java.name }
                    if (!running && savedEnabled) {
                        getSharedPreferences("driving_mode", MODE_PRIVATE).edit()
                            .putBoolean("enabled", false).apply()
                    }
                    result.success(savedEnabled && running)
                }
                "startBackgroundDriving" -> {
                    if (!hasBlePermissions()) {
                        result.error("PERMISSION_DENIED", "Grant nearby-device permissions first.", null)
                    } else {
                        try {
                            val intent = android.content.Intent(this, DrivingModeService::class.java).apply {
                                action = DrivingModeService.ACTION_START
                                putExtra("vehicleType", call.argument<String>("vehicleType") ?: "Sedan")
                                putExtra("vehicleColor", call.argument<String>("vehicleColor") ?: "Other")
                                putExtra("plateNumber", call.argument<String>("plateNumber") ?: "")
                                putExtra("temporaryEmergency", call.argument<Boolean>("temporaryEmergency") ?: false)
                                putExtra("temporaryExpiresAt", call.argument<Number>("temporaryExpiresAt")?.toLong() ?: 0L)
                            }
                            pendingDrivingStartResult = result
                            ContextCompat.startForegroundService(this, intent)
                        } catch (exception: Exception) {
                            pendingDrivingStartResult = null
                            result.error("DRIVING_SERVICE_FAILED", exception.message, null)
                        }
                    }
                }
                "stopBackgroundDriving" -> {
                    val intent = android.content.Intent(this, DrivingModeService::class.java).apply {
                        action = DrivingModeService.ACTION_STOP
                    }
                    startService(intent)
                    getSharedPreferences("driving_mode", MODE_PRIVATE).edit()
                        .putBoolean("enabled", false).apply()
                    result.success(null)
                }
                "readVehicleProfile" -> {
                    val profile = getSharedPreferences("vehicle_profile", MODE_PRIVATE)
                    result.success(mapOf(
                        "type" to (profile.getString("type", "Sedan") ?: "Sedan"),
                        "color" to (profile.getString("color", "") ?: ""),
                        "plate" to (profile.getString("plate", "") ?: "")
                    ))
                }
                "saveVehicleProfile" -> {
                    val type = call.argument<String>("type")
                    val color = call.argument<String>("color")
                    val plate = call.argument<String>("plate")
                    if (type == null || color == null || plate == null) {
                        result.error("BAD_PROFILE", "Vehicle profile fields are required.", null)
                    } else {
                        getSharedPreferences("vehicle_profile", MODE_PRIVATE).edit()
                            .putString("type", type)
                            .putString("color", color)
                            .putString("plate", plate)
                            .apply()
                        result.success(null)
                    }
                }
                "startScan" -> startScan(result)
                "stopScan" -> stopScan(result)
                "startAdvertising" -> {
                    val packet = call.argument<List<Int>>("packet")?.map { it.toByte() }?.toByteArray()
                    if (packet == null || (packet.size != 10 && packet.size != 24)) {
                        result.error("BAD_PACKET", "Expected a 10-byte legacy or 24-byte EVMN beacon.", null)
                    } else startAdvertising(packet, result)
                }
                "stopAdvertising" -> stopAdvertising(result)
                "isTtsReady" -> result.success(ttsReady)
                "playAlertTone" -> {
                    val tone = ToneGenerator(AudioManager.STREAM_NOTIFICATION, 55)
                    tone.startTone(ToneGenerator.TONE_PROP_BEEP2, 180)
                    Handler(Looper.getMainLooper()).postDelayed({
                        tone.startTone(ToneGenerator.TONE_PROP_BEEP2, 300)
                        Handler(Looper.getMainLooper()).postDelayed({ tone.release() }, 340)
                    }, 220)
                    result.success(null)
                }
                "speak" -> {
                    val message = call.argument<String>("message")
                    if (!ttsReady || message.isNullOrBlank()) result.error("TTS_UNAVAILABLE", "Local text-to-speech is unavailable.", null)
                    else {
                        tts?.speak(message, TextToSpeech.QUEUE_FLUSH, null, "evmn-alert")
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
                drivingModeEventSink = events
                events?.success(mapOf("type" to "tts", "ready" to ttsReady))
            }
            override fun onCancel(arguments: Any?) {
                eventSink = null
                drivingModeEventSink = null
            }
        })
    }

    private fun requestBlePermissions(result: MethodChannel.Result) {
        val requested = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_ADVERTISE, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        val permissionsToAsk = requested.toMutableList().apply {
            if (Build.VERSION.SDK_INT >= 33) add(Manifest.permission.POST_NOTIFICATIONS)
        }
        val missing = permissionsToAsk.filter { ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isEmpty()) result.success(true)
        else {
            pendingPermissionResult = result
            ActivityCompat.requestPermissions(this, missing.toTypedArray(), REQUEST_BLE_PERMISSIONS)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_BLE_PERMISSIONS) {
            val granted = hasBlePermissions()
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    private fun hasBlePermissions(): Boolean {
        val needed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            listOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_ADVERTISE, Manifest.permission.BLUETOOTH_CONNECT)
        } else listOf(Manifest.permission.ACCESS_FINE_LOCATION)
        return needed.all { ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED }
    }

    @Suppress("MissingPermission")
    private fun isBluetoothEnabled(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED
        ) return false
        return getSystemService(BluetoothManager::class.java)?.adapter?.isEnabled == true
    }

    @Suppress("MissingPermission")
    private fun startScan(result: MethodChannel.Result) {
        if (!hasBlePermissions()) return result.error("PERMISSION_DENIED", "Grant nearby-device permissions first.", null)
        val bleScanner = try {
            getSystemService(BluetoothManager::class.java)?.adapter?.bluetoothLeScanner
        } catch (exception: SecurityException) {
            return result.error("PERMISSION_DENIED", exception.message, null)
        } ?: return result.error("BLE_UNAVAILABLE", "BLE scanning is unavailable or Bluetooth is off.", null)
        scanner = bleScanner
        if (scanCallback != null) return result.success(null)
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val bytes = result.scanRecord?.getManufacturerSpecificData(TEST_MANUFACTURER_ID) ?: return
                if (bytes.size != 10 && bytes.size != 24) return
                eventSink?.success(mapOf("type" to "packet", "packet" to bytes.map { it.toInt() and 0xff }, "rssi" to result.rssi))
                if (seenDeviceAddresses.add(result.device.address)) {
                    eventSink?.success(mapOf("type" to "peer", "count" to seenDeviceAddresses.size))
                }
            }

            override fun onScanFailed(errorCode: Int) {
                eventSink?.error("SCAN_FAILED", "Android BLE scan failed with code $errorCode.", errorCode)
                scanCallback = null
            }
        }
        try {
            val legacyFilter = ScanFilter.Builder().setManufacturerData(TEST_MANUFACTURER_ID, byteArrayOf(1)).build()
            val currentFilter = ScanFilter.Builder().setManufacturerData(TEST_MANUFACTURER_ID, byteArrayOf(2)).build()
            // Balanced mode trades a little discovery speed for lower power use.
            val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_BALANCED).build()
            bleScanner.startScan(listOf(legacyFilter, currentFilter), settings, callback)
            scanCallback = callback
            result.success(null)
        } catch (exception: SecurityException) {
            result.error("PERMISSION_DENIED", exception.message, null)
        } catch (exception: IllegalStateException) {
            result.error("SCAN_FAILED", exception.message, null)
        }
    }

    @Suppress("MissingPermission")
    private fun stopScan(result: MethodChannel.Result) {
        try {
            scanCallback?.let { scanner?.stopScan(it) }
            scanCallback = null
            result.success(null)
        } catch (exception: SecurityException) {
            result.error("PERMISSION_DENIED", exception.message, null)
        }
    }

    @Suppress("MissingPermission")
    private fun startAdvertising(packet: ByteArray, result: MethodChannel.Result) {
        if (!hasBlePermissions()) return result.error("PERMISSION_DENIED", "Grant nearby-device permissions first.", null)
        val bleAdvertiser = try {
            getSystemService(BluetoothManager::class.java)?.adapter?.bluetoothLeAdvertiser
        } catch (exception: SecurityException) {
            return result.error("PERMISSION_DENIED", exception.message, null)
        } ?: return result.error("BLE_UNAVAILABLE", "BLE advertising is unavailable or Bluetooth is off.", null)
        advertiser = bleAdvertiser
        stopCurrentAdvertisement()
        val callback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                runOnUiThread { result.success(null) }
            }

            override fun onStartFailure(errorCode: Int) {
                advertiseCallback = null
                runOnUiThread { result.error("ADVERTISE_FAILED", "Android BLE advertising failed with code $errorCode.", errorCode) }
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
                .addManufacturerData(TEST_MANUFACTURER_ID, packet)
                .build()
            bleAdvertiser.startAdvertising(settings, data, callback)
            advertiseCallback = callback
        } catch (exception: SecurityException) {
            result.error("PERMISSION_DENIED", exception.message, null)
        } catch (exception: IllegalStateException) {
            result.error("ADVERTISE_FAILED", exception.message, null)
        }
    }

    @Suppress("MissingPermission")
    private fun stopCurrentAdvertisement() {
        advertiseCallback?.let { callback ->
            try { advertiser?.stopAdvertising(callback) } catch (_: SecurityException) { }
        }
        advertiseCallback = null
    }

    private fun stopAdvertising(result: MethodChannel.Result) {
        stopCurrentAdvertisement()
        result.success(null)
    }

    override fun onDestroy() {
        try { scanCallback?.let { scanner?.stopScan(it) } } catch (_: SecurityException) { }
        stopCurrentAdvertisement()
        tts?.stop()
        tts?.shutdown()
        tts = null
        super.onDestroy()
    }
}
