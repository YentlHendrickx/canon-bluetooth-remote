package com.haze.canon_remote_wear

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.haze.canon_remote/wear_communication"
    private val TAG = "MainActivity"
    
    private var wearDataLayerService: WearDataLayerService? = null
    private var methodChannel: MethodChannel? = null
    private var messageReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        wearDataLayerService = WearDataLayerService(this)
        wearDataLayerService?.connect()
        
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isConnected" -> {
                    val service = wearDataLayerService
                    if (service == null) {
                        result.success(false)
                    } else {
                        service.checkConnected { connected ->
                            runOnUiThread { result.success(connected) }
                        }
                    }
                }
                "sendMessage" -> {
                    val path = call.argument<String>("path")
                    val message = call.argument<String>("message")
                    wearDataLayerService?.sendMessage(path ?: "", message ?: "")
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Set up broadcast receiver for Wear OS messages
        setupMessageReceiver()
        
        // Set up message listener for Wear OS Data Layer
        setupWearMessageListener()
    }
    
    private fun setupMessageReceiver() {
        messageReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                when (intent?.action) {
                    "SHUTTER_RESPONSE_RECEIVED" -> {
                        val data = intent.getStringExtra("data")
                        Log.d(TAG, "Received shutter response from phone: $data")
                        
                        // Forward to Flutter app
                        methodChannel?.invokeMethod("onShutterResponse", mapOf("data" to data))
                    }
                }
            }
        }
        
        val filter = IntentFilter("SHUTTER_RESPONSE_RECEIVED")
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(messageReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(messageReceiver, filter)
        }
    }
    
    private fun setupWearMessageListener() {
        wearDataLayerService?.setMessageListener { messageEvent ->
            Log.d(TAG, "Wear OS message received: ${messageEvent.path}")
            
            if (messageEvent.path == "/shutter_response") {
                val data = String(messageEvent.data)
                Log.d(TAG, "Shutter response received via Wear OS: $data")
                
                // Forward to Flutter app
                methodChannel?.invokeMethod("onShutterResponse", mapOf("data" to data))
            }
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        wearDataLayerService?.disconnect()
        messageReceiver?.let { unregisterReceiver(it) }
    }
}
