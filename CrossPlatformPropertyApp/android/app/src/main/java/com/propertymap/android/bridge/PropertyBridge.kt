package com.propertymap.android.bridge

import android.content.Context
import android.util.Log
import android.webkit.JavascriptInterface
import android.webkit.WebView
import com.google.gson.Gson
import com.google.gson.JsonObject
import com.propertymap.android.data.PropertyBoundaryData
import com.propertymap.android.location.LocationManager

/**
 * Android implementation of the cross-platform PropertyBridge
 * Handles communication between WebView and native Android components
 * Mirrors the iOS WKScriptMessageHandler functionality
 */
class PropertyBridge(
    private val context: Context,
    private val locationManager: LocationManager
) {
    
    private val gson = Gson()
    private var webView: WebView? = null
    private var arCallback: ((PropertyBoundaryData) -> Unit)? = null
    
    companion object {
        private const val TAG = "PropertyBridge"
    }
    
    fun attachToWebView(webView: WebView) {
        this.webView = webView
        webView.addJavascriptInterface(this, "Android")
        injectApiKeys()
    }
    
    fun setArCallback(callback: (PropertyBoundaryData) -> Unit) {
        this.arCallback = callback
    }
    
    private fun injectApiKeys() {
        // Get API keys from secure storage or environment
        val linzKey = getSecureApiKey("LINZ_API_KEY")
        val locationiqKey = getSecureApiKey("LOCATIONIQ_API_KEY") 
        val googleKey = getSecureApiKey("GOOGLE_API_KEY")
        
        val script = """
            console.log('🔑 Android injecting API keys...');
            window.LINZ_API_KEY = '$linzKey';
            window.LOCATIONIQ_API_KEY = '$locationiqKey';
            window.GOOGLE_API_KEY = '$googleKey';
            console.log('🔑 API Keys injected from Android:', {
                LINZ: !!window.LINZ_API_KEY,
                LocationIQ: !!window.LOCATIONIQ_API_KEY,
                Google: !!window.GOOGLE_API_KEY
            });
            console.log('🔑 LINZ API Key length:', window.LINZ_API_KEY.length);
            
            // Set flag that Android injection happened
            window.ANDROID_INJECTION_COMPLETE = true;
            
            // Initialize bridge if available
            if (window.propertyBridge) {
                window.propertyBridge.platform = 'android';
            }
        """.trimIndent()
        
        webView?.post {
            webView?.evaluateJavascript(script) { result ->
                Log.d(TAG, "API keys injected successfully")
            }
        }
    }
    
    private fun getSecureApiKey(keyName: String): String {
        // In production, retrieve from Android Keystore or secure storage
        // For now, using environment or placeholder
        return when (keyName) {
            "LINZ_API_KEY" -> System.getenv("LINZ_API_KEY") ?: ""
            "LOCATIONIQ_API_KEY" -> System.getenv("LOCATIONIQ_API_KEY") ?: ""
            "GOOGLE_API_KEY" -> System.getenv("GOOGLE_API_KEY") ?: ""
            else -> ""
        }
    }
    
    // JavaScript interface methods - called from web page
    
    @JavascriptInterface
    fun log(message: String) {
        Log.d(TAG, "[Web] $message")
    }
    
    @JavascriptInterface
    fun requestLocation() {
        Log.d(TAG, "Location requested from web")
        locationManager.getCurrentLocation { latitude, longitude ->
            sendLocationToWeb(latitude, longitude)
        }
    }
    
    @JavascriptInterface
    fun receivePropertyData(jsonData: String) {
        Log.d(TAG, "Property data received: ${jsonData.take(100)}...")
        
        try {
            val propertyData = gson.fromJson(jsonData, PropertyBoundaryData::class.java)
            Log.d(TAG, "Parsed property data: ${propertyData.coordinates.size} coordinates")
            
            // Pass to AR callback if registered
            arCallback?.invoke(propertyData)
            
        } catch (e: Exception) {
            Log.e(TAG, "Error parsing property data: ${e.message}")
        }
    }
    
    @JavascriptInterface
    fun openARView() {
        Log.d(TAG, "AR view requested from web")
        
        // Switch to AR tab in main activity
        if (context is MainActivity) {
            val activity = context as MainActivity
            activity.runOnUiThread {
                // TODO: Implement tab switching to AR fragment
                Log.d(TAG, "🥽 Switching to AR view")
            }
        }
    }
    
    // Native methods - called from Android code
    
    fun sendLocationToWeb(latitude: Double, longitude: Double) {
        val script = "if (window.receiveLocation) { window.receiveLocation($latitude, $longitude); }"
        
        webView?.post {
            webView?.evaluateJavascript(script) { result ->
                Log.d(TAG, "Location sent to web: $latitude, $longitude")
            }
        }
    }
    
    fun sendApiKeysToWeb(keys: Map<String, String>) {
        val keysJson = gson.toJson(keys)
        val script = "if (window.receiveApiKeys) { window.receiveApiKeys($keysJson); }"
        
        webView?.post {
            webView?.evaluateJavascript(script) { result ->
                Log.d(TAG, "API keys sent to web")
            }
        }
    }
    
    fun getPlatformInfo(): String {
        return gson.toJson(mapOf(
            "platform" to "android",
            "version" to android.os.Build.VERSION.RELEASE,
            "device" to android.os.Build.MODEL,
            "capabilities" to mapOf(
                "arcore" to true,
                "location" to true,
                "camera" to true
            )
        ))
    }
}