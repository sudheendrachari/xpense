package io.github.sudheendrachari.xpense

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

class SmsReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "SmsReceiver"
        private const val CHANNEL_NAME = "xpense/sms_receiver"
        private var methodChannel: MethodChannel? = null
        
        fun setMethodChannel(channel: MethodChannel) {
            methodChannel = channel
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (Telephony.Sms.Intents.SMS_RECEIVED_ACTION == intent.action) {
            val smsMessages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
            
            for (smsMessage in smsMessages) {
                val sender = smsMessage.originatingAddress ?: ""
                val body = smsMessage.messageBody ?: ""
                val timestamp = smsMessage.timestampMillis
                
                // Filter by bank senders (HDFC and Axis)
                val senderUpper = sender.uppercase()
                if (senderUpper.contains("HDFCBK") || 
                    senderUpper.contains("HDFCBN") || 
                    senderUpper.contains("AXISBK") || 
                    senderUpper.contains("AXISBN")) {
                    
                    Log.d(TAG, "Received bank SMS from: $sender")
                    
                    // Send to Flutter via MethodChannel (only if Flutter engine is running)
                    val smsData = mapOf(
                        "sender" to sender,
                        "body" to body,
                        "timestamp" to timestamp,
                        "id" to "${sender}_${timestamp}"
                    )
                    
                    try {
                        if (methodChannel != null) {
                            methodChannel!!.invokeMethod("onSmsReceived", smsData)
                            Log.d(TAG, "Sent SMS to Flutter: $sender")
                        } else {
                            Log.d(TAG, "Flutter engine not running, SMS will be caught by app-open sync: $sender")
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error sending SMS to Flutter: ${e.message}")
                        // If Flutter isn't running, this is expected - app-open sync will catch it
                    }
                }
            }
        }
    }
}

