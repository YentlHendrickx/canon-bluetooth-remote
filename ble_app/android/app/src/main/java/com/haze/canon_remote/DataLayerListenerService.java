package com.haze.canon_remote;

import android.content.Intent;
import android.util.Log;

import com.google.android.gms.wearable.MessageEvent;
import com.google.android.gms.wearable.WearableListenerService;

public class DataLayerListenerService extends WearableListenerService {
    private static final String TAG = "DataLayerListenerService";
    
    @Override
    public void onMessageReceived(MessageEvent messageEvent) {
        Log.d(TAG, "Message received: " + messageEvent.getPath());
        
        if (messageEvent.getPath().equals("/shutter_command")) {
            Log.i(TAG, "Shutter command received from watch");
            
            // Send message to Flutter app
            Intent intent = new Intent("SHUTTER_COMMAND_RECEIVED");
            intent.putExtra("data", new String(messageEvent.getData()));
            sendBroadcast(intent);
        }
    }
}
