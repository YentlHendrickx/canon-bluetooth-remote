package com.haze.canon_remote;

import android.content.Context;
import android.util.Log;

import com.google.android.gms.tasks.Tasks;
import com.google.android.gms.wearable.CapabilityClient;
import com.google.android.gms.wearable.CapabilityInfo;
import com.google.android.gms.wearable.MessageClient;
import com.google.android.gms.wearable.MessageEvent;
import com.google.android.gms.wearable.Node;
import com.google.android.gms.wearable.Wearable;

import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

public class WearDataLayerService {
    private static final String TAG = "WearDataLayerService";

    private final Context appContext;
    private final ExecutorService executor;
    private volatile boolean lastConnected = false;
    private volatile String preferredNodeId = null;
    private MessageClient.OnMessageReceivedListener internalListener;

    public WearDataLayerService(Context context) {
        this.appContext = context.getApplicationContext();
        this.executor = Executors.newSingleThreadExecutor();
    }

    public void connect() {
        refreshConnectedNodesAsync();
        subscribeToCapabilityChanges();
    }

    public void disconnect() {
        try {
            if (internalListener != null) {
                Wearable.getMessageClient(appContext).removeListener(internalListener);
                internalListener = null;
            }
        } catch (Exception ignored) {}
        executor.shutdownNow();
    }

    public boolean isConnected() {
        return lastConnected;
    }

    public interface ResultCallback {
        void onResult(boolean connected);
    }

    public void checkConnected(ResultCallback callback) {
        executor.execute(() -> {
            boolean connected = false;
            try {
                List<Node> nodes = Tasks.await(
                        Wearable.getNodeClient(appContext).getConnectedNodes(),
                        3, TimeUnit.SECONDS);
                connected = nodes != null && !nodes.isEmpty();
                lastConnected = connected;
                Log.d(TAG, "checkConnected => " + connected + ", nodes=" + (nodes == null ? 0 : nodes.size()));
            } catch (Exception e) {
                Log.w(TAG, "checkConnected failed", e);
            }
            try {
                callback.onResult(connected);
            } catch (Exception ignored) {}
        });
    }

    public void sendMessage(String path, String message) {
        executor.execute(() -> {
            try {
                List<Node> nodes;
                if (preferredNodeId != null) {
                    // Try preferred node first
                    Node single = null;
                    for (Node n : Tasks.await(Wearable.getNodeClient(appContext).getConnectedNodes(), 3, TimeUnit.SECONDS)) {
                        if (n.getId().equals(preferredNodeId)) { single = n; break; }
                    }
                    if (single != null) {
                        nodes = java.util.Collections.singletonList(single);
                    } else {
                        nodes = Tasks.await(Wearable.getNodeClient(appContext).getConnectedNodes(), 5, TimeUnit.SECONDS);
                    }
                } else {
                    nodes = Tasks.await(Wearable.getNodeClient(appContext).getConnectedNodes(), 5, TimeUnit.SECONDS);
                }
                lastConnected = nodes != null && !nodes.isEmpty();

                if (!lastConnected) {
                    Log.w(TAG, "No connected nodes to send message");
                    return;
                }

                for (Node node : nodes) {
                    try {
                        Integer result = Tasks.await(
                                Wearable.getMessageClient(appContext)
                                        .sendMessage(node.getId(), path, message.getBytes()),
                                5, TimeUnit.SECONDS);
                        Log.d(TAG, "Message sent to " + node.getDisplayName() + " (" + node.getId() + ") result=" + result);
                    } catch (Exception sendEx) {
                        Log.e(TAG, "Failed to send message to node: " + node.getId(), sendEx);
                    }
                }
            } catch (Exception e) {
                Log.e(TAG, "Error sending message", e);
            }
        });
    }

    public void setMessageListener(MessageClient.OnMessageReceivedListener listener) {
        this.internalListener = listener;
        Wearable.getMessageClient(appContext).addListener(listener);
    }

    public void removeMessageListener(MessageClient.OnMessageReceivedListener listener) {
        try {
            Wearable.getMessageClient(appContext).removeListener(listener);
        } catch (Exception e) {
            Log.w(TAG, "removeMessageListener failed", e);
        }
    }

    private void refreshConnectedNodesAsync() {
        executor.execute(() -> {
            try {
                List<Node> nodes = Tasks.await(
                        Wearable.getNodeClient(appContext).getConnectedNodes(),
                        5, TimeUnit.SECONDS);
                lastConnected = nodes != null && !nodes.isEmpty();
                Log.d(TAG, "Connected nodes: " + (nodes == null ? 0 : nodes.size()));
                if (nodes != null && !nodes.isEmpty()) {
                    // Prefer nearby (companion) node if flagged
                    preferredNodeId = nodes.get(0).getId();
                }
            } catch (Exception e) {
                Log.w(TAG, "Failed to refresh connected nodes", e);
                lastConnected = false;
            }
        });
    }

    private void subscribeToCapabilityChanges() {
        executor.execute(() -> {
            try {
                CapabilityInfo info = Tasks.await(
                        Wearable.getCapabilityClient(appContext)
                                .getCapability("camera_remote_watch", CapabilityClient.FILTER_REACHABLE),
                        5, TimeUnit.SECONDS);
                selectPreferredNode(info);
                Wearable.getCapabilityClient(appContext)
                        .addListener(this::onCapabilityChanged, "camera_remote_phone");
            } catch (Exception e) {
                Log.w(TAG, "subscribeToCapabilityChanges failed", e);
            }
        });
    }

    private void onCapabilityChanged(CapabilityInfo capabilityInfo) {
        selectPreferredNode(capabilityInfo);
    }

    private void selectPreferredNode(CapabilityInfo capabilityInfo) {
        if (capabilityInfo == null) return;
        for (Node node : capabilityInfo.getNodes()) {
            if (node.isNearby()) {
                preferredNodeId = node.getId();
                lastConnected = true;
                Log.d(TAG, "Preferred node set (nearby): " + node.getDisplayName());
                return;
            }
        }
        // Fallback: pick any
        for (Node node : capabilityInfo.getNodes()) {
            preferredNodeId = node.getId();
            lastConnected = true;
            Log.d(TAG, "Preferred node set: " + node.getDisplayName());
            return;
        }
        preferredNodeId = null;
        lastConnected = false;
    }
}
