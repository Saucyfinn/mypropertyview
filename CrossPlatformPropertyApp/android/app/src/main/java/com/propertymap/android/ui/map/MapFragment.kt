package com.propertymap.android.ui.map

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.fragment.app.Fragment
import com.propertymap.android.MainActivity
import com.propertymap.android.R
import com.propertymap.android.databinding.FragmentMapBinding

/**
 * Map fragment that displays the shared web mapping interface
 * Uses WebView to load the cross-platform mapping component
 */
class MapFragment : Fragment() {

    private var _binding: FragmentMapBinding? = null
    private val binding get() = _binding!!
    
    private lateinit var webView: WebView

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View {
        _binding = FragmentMapBinding.inflate(inflater, container, false)
        val root: View = binding.root

        setupWebView()
        loadMapInterface()

        return root
    }
    
    private fun setupWebView() {
        webView = binding.webView
        
        // Configure WebView settings
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            databaseEnabled = true
            allowFileAccess = true
            allowContentAccess = true
            allowFileAccessFromFileURLs = true
            allowUniversalAccessFromFileURLs = true
            cacheMode = WebSettings.LOAD_NO_CACHE
            mixedContentMode = WebSettings.MIXED_CONTENT_ALWAYS_ALLOW
        }
        
        // Set up WebView client
        webView.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, url: String?) {
                super.onPageFinished(view, url)
                // Notify bridge that page is loaded
                (activity as? MainActivity)?.getPropertyBridge()?.attachToWebView(webView)
            }
        }
        
        // Attach property bridge
        (activity as? MainActivity)?.getPropertyBridge()?.attachToWebView(webView)
    }
    
    private fun loadMapInterface() {
        // Load the shared web mapping interface
        webView.loadUrl("file:///android_asset/shared-web/index.html")
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }
}