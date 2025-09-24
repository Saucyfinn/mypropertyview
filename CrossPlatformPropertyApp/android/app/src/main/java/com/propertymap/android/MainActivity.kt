package com.propertymap.android

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.navigation.findNavController
import androidx.navigation.ui.AppBarConfiguration
import androidx.navigation.ui.setupActionBarWithNavController
import androidx.navigation.ui.setupWithNavController
import com.google.android.material.bottomnavigation.BottomNavigationView
import com.propertymap.android.databinding.ActivityMainBinding
import com.propertymap.android.bridge.PropertyBridge
import com.propertymap.android.location.LocationManager

class MainActivity : AppCompatActivity() {
    
    private lateinit var binding: ActivityMainBinding
    private lateinit var propertyBridge: PropertyBridge
    private lateinit var locationManager: LocationManager
    
    companion object {
        private const val LOCATION_PERMISSION_REQUEST_CODE = 1001
        private const val CAMERA_PERMISSION_REQUEST_CODE = 1002
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        binding = ActivityMainBinding.inflate(layoutInflater)
        setContentView(binding.root)

        val navView: BottomNavigationView = binding.navView
        val navController = findNavController(R.id.nav_host_fragment_activity_main)
        
        // Setup navigation with tabs: Map and AR
        val appBarConfiguration = AppBarConfiguration(
            setOf(R.id.navigation_map, R.id.navigation_ar)
        )
        setupActionBarWithNavController(navController, appBarConfiguration)
        navView.setupWithNavController(navController)
        
        // Initialize location manager and bridge
        locationManager = LocationManager(this)
        propertyBridge = PropertyBridge(this, locationManager)
        
        // Request permissions
        requestPermissions()
    }
    
    private fun requestPermissions() {
        val permissions = mutableListOf<String>()
        
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) 
            != PackageManager.PERMISSION_GRANTED) {
            permissions.add(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) 
            != PackageManager.PERMISSION_GRANTED) {
            permissions.add(Manifest.permission.CAMERA)
        }
        
        if (permissions.isNotEmpty()) {
            ActivityCompat.requestPermissions(
                this, 
                permissions.toTypedArray(), 
                LOCATION_PERMISSION_REQUEST_CODE
            )
        }
    }
    
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        
        when (requestCode) {
            LOCATION_PERMISSION_REQUEST_CODE -> {
                if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                    Toast.makeText(this, "Location permission granted", Toast.LENGTH_SHORT).show()
                } else {
                    Toast.makeText(this, "Location permission is required for property mapping", Toast.LENGTH_LONG).show()
                }
            }
        }
    }
    
    fun getPropertyBridge(): PropertyBridge = propertyBridge
    fun getLocationManager(): LocationManager = locationManager
}