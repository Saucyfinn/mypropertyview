package com.propertymap.android.location

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.util.Log
import androidx.core.content.ContextCompat
import com.google.android.gms.location.*

/**
 * Android location management for property mapping
 * Provides current location to web interface and AR system
 */
class LocationManager(private val context: Context) {
    
    private val fusedLocationClient: FusedLocationProviderClient = 
        LocationServices.getFusedLocationProviderClient(context)
    
    private val locationRequest = LocationRequest.Builder(
        Priority.PRIORITY_HIGH_ACCURACY,
        10000 // 10 seconds interval
    ).build()
    
    companion object {
        private const val TAG = "LocationManager"
        // Wellington fallback coordinates
        private const val FALLBACK_LATITUDE = -41.2865
        private const val FALLBACK_LONGITUDE = 174.7762
    }
    
    fun getCurrentLocation(callback: (Double, Double) -> Unit) {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) 
            != PackageManager.PERMISSION_GRANTED) {
            Log.w(TAG, "Location permission not granted, using fallback")
            callback(FALLBACK_LATITUDE, FALLBACK_LONGITUDE)
            return
        }
        
        try {
            fusedLocationClient.getCurrentLocation(
                Priority.PRIORITY_HIGH_ACCURACY,
                null
            ).addOnSuccessListener { location: Location? ->
                if (location != null) {
                    Log.d(TAG, "Location found: ${location.latitude}, ${location.longitude}")
                    callback(location.latitude, location.longitude)
                } else {
                    Log.w(TAG, "Location is null, using fallback")
                    callback(FALLBACK_LATITUDE, FALLBACK_LONGITUDE)
                }
            }.addOnFailureListener { exception ->
                Log.e(TAG, "Failed to get location: ${exception.message}")
                callback(FALLBACK_LATITUDE, FALLBACK_LONGITUDE)
            }
        } catch (e: SecurityException) {
            Log.e(TAG, "Security exception getting location: ${e.message}")
            callback(FALLBACK_LATITUDE, FALLBACK_LONGITUDE)
        }
    }
    
    fun startLocationUpdates(callback: (Double, Double) -> Unit) {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) 
            != PackageManager.PERMISSION_GRANTED) {
            Log.w(TAG, "Location permission not granted for updates")
            return
        }
        
        val locationCallback = object : LocationCallback() {
            override fun onLocationResult(locationResult: LocationResult) {
                locationResult.lastLocation?.let { location ->
                    callback(location.latitude, location.longitude)
                }
            }
        }
        
        try {
            fusedLocationClient.requestLocationUpdates(
                locationRequest,
                locationCallback,
                null
            )
        } catch (e: SecurityException) {
            Log.e(TAG, "Security exception for location updates: ${e.message}")
        }
    }
}