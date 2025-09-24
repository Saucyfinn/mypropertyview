package com.propertymap.android.ar

import android.content.Context
import android.util.Log
import com.google.ar.core.*
import com.google.ar.sceneform.AnchorNode
import com.google.ar.sceneform.Node
import com.google.ar.sceneform.Scene
import com.google.ar.sceneform.math.Vector3
import com.google.ar.sceneform.rendering.Color
import com.google.ar.sceneform.rendering.MaterialFactory
import com.google.ar.sceneform.rendering.ShapeFactory
import com.google.ar.sceneform.ux.ArFragment
import com.google.ar.sceneform.ux.TransformableNode
import com.propertymap.android.data.PropertyInfo
import java.util.concurrent.CompletableFuture
import kotlin.math.*

/**
 * ARCore manager for property boundary visualization
 * Implements multi-tier positioning system similar to iOS ARKit version
 */
class ARCoreManager(
    private val context: Context,
    private val arFragment: ArFragment
) {
    
    companion object {
        private const val TAG = "ARCoreManager"
        private val EARTH_RADIUS_M = 6371000.0
    }
    
    private var session: Session? = null
    private var scene: Scene? = null
    private var isInitialized = false
    private var boundaryNodes = mutableListOf<Node>()
    
    fun initialize(callback: (Boolean) -> Unit) {
        try {
            // Check ARCore availability
            when (ArCoreApk.getInstance().checkAvailability(context)) {
                ArCoreApk.Availability.SUPPORTED_INSTALLED -> {
                    setupARSession(callback)
                }
                ArCoreApk.Availability.SUPPORTED_APK_TOO_OLD,
                ArCoreApk.Availability.SUPPORTED_NOT_INSTALLED -> {
                    Log.w(TAG, "ARCore needs to be updated or installed")
                    callback(false)
                }
                else -> {
                    Log.e(TAG, "ARCore not supported on this device")
                    callback(false)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing ARCore: ${e.message}")
            callback(false)
        }
    }
    
    private fun setupARSession(callback: (Boolean) -> Unit) {
        try {
            session = Session(context)
            
            // Configure AR session
            val config = Config(session).apply {
                // Try Geospatial mode first (requires Google Play Services)
                try {
                    geospatialMode = Config.GeospatialMode.ENABLED
                    Log.d(TAG, "Geospatial anchoring enabled")
                } catch (e: Exception) {
                    Log.w(TAG, "Geospatial mode not available, using standard tracking")
                    geospatialMode = Config.GeospatialMode.DISABLED
                }
                
                lightEstimationMode = Config.LightEstimationMode.ENVIRONMENTAL_HDR
                planeFindingMode = Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
            }
            
            session?.configure(config)
            arFragment.arSceneView.setupSession(session)
            scene = arFragment.arSceneView.scene
            
            isInitialized = true
            Log.d(TAG, "ARCore session initialized successfully")
            callback(true)
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to setup AR session: ${e.message}")
            callback(false)
        }
    }
    
    fun displayBoundaries(
        coordinates: List<Pair<Double, Double>>,
        propertyInfo: PropertyInfo
    ) {
        if (!isInitialized || coordinates.isEmpty()) {
            Log.w(TAG, "Cannot display boundaries - AR not initialized or no coordinates")
            return
        }
        
        Log.d(TAG, "Displaying property boundaries: ${coordinates.size} points")
        clearExistingBoundaries()
        
        // Try Geospatial anchoring first, fallback to relative positioning
        tryGeospatialAnchoring(coordinates, propertyInfo) { success ->
            if (!success) {
                Log.d(TAG, "Geospatial anchoring failed, using relative positioning")
                displayRelativeBoundaries(coordinates, propertyInfo)
            }
        }
    }
    
    private fun tryGeospatialAnchoring(
        coordinates: List<Pair<Double, Double>>,
        propertyInfo: PropertyInfo,
        callback: (Boolean) -> Unit
    ) {
        val session = this.session
        if (session?.config?.geospatialMode != Config.GeospatialMode.ENABLED) {
            callback(false)
            return
        }
        
        try {
            val earth = session.earth
            if (earth?.trackingState != TrackingState.TRACKING) {
                Log.w(TAG, "Earth tracking not available")
                callback(false)
                return
            }
            
            // Create geo anchors for each boundary point
            var successCount = 0
            val totalPoints = coordinates.size
            
            for ((index, coord) in coordinates.withIndex()) {
                val altitude = earth.cameraGeospatialPose.altitude // Use current altitude
                
                try {
                    val anchor = earth.createAnchor(
                        coord.first,  // latitude
                        coord.second, // longitude
                        altitude,
                        0f, 0f, 0f, 1f // quaternion (no rotation)
                    )
                    
                    createBoundaryMarker(anchor, index, totalPoints)
                    successCount++
                    
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to create geo anchor at $coord: ${e.message}")
                }
            }
            
            callback(successCount > 0)
            
        } catch (e: Exception) {
            Log.e(TAG, "Geospatial anchoring error: ${e.message}")
            callback(false)
        }
    }
    
    private fun displayRelativeBoundaries(
        coordinates: List<Pair<Double, Double>>,
        propertyInfo: PropertyInfo
    ) {
        // Convert lat/lon to local ENU coordinates relative to first point
        if (coordinates.isEmpty()) return
        
        val origin = coordinates[0]
        val localCoords = coordinates.map { coord ->
            latLonToENU(coord.first, coord.second, origin.first, origin.second)
        }
        
        // Create boundary visualization in local coordinate system
        for ((index, localCoord) in localCoords.withIndex()) {
            createLocalBoundaryMarker(localCoord.first, localCoord.second, index, localCoords.size)
        }
        
        // Connect boundary points with lines
        createBoundaryLines(localCoords)
    }
    
    private fun createBoundaryMarker(anchor: Anchor, index: Int, total: Int) {
        MaterialFactory.makeOpaqueWithColor(context, Color(0.0f, 0.5f, 1.0f, 1.0f))
            .thenAccept { material ->
                val sphere = ShapeFactory.makeSphere(0.1f, Vector3.zero(), material)
                
                val anchorNode = AnchorNode(anchor)
                val markerNode = Node().apply {
                    renderable = sphere
                    localPosition = Vector3(0f, 0f, 0f)
                }
                
                anchorNode.addChild(markerNode)
                scene?.addChild(anchorNode)
                boundaryNodes.add(anchorNode)
                
                Log.d(TAG, "Created boundary marker $index/$total")
            }
    }
    
    private fun createLocalBoundaryMarker(x: Float, z: Float, index: Int, total: Int) {
        MaterialFactory.makeOpaqueWithColor(context, Color(1.0f, 0.0f, 0.0f, 1.0f))
            .thenAccept { material ->
                val sphere = ShapeFactory.makeSphere(0.2f, Vector3.zero(), material)
                
                val markerNode = Node().apply {
                    renderable = sphere
                    localPosition = Vector3(x, 0f, z) // Place at ground level
                }
                
                scene?.addChild(markerNode)
                boundaryNodes.add(markerNode)
                
                Log.d(TAG, "Created local boundary marker $index/$total at ($x, $z)")
            }
    }
    
    private fun createBoundaryLines(coordinates: List<Pair<Float, Float>>) {
        // Create lines connecting boundary points
        for (i in coordinates.indices) {
            val start = coordinates[i]
            val end = coordinates[(i + 1) % coordinates.size]
            
            createLine(start.first, start.second, end.first, end.second)
        }
    }
    
    private fun createLine(x1: Float, z1: Float, x2: Float, z2: Float) {
        MaterialFactory.makeOpaqueWithColor(context, Color(0.0f, 0.5f, 1.0f, 0.8f))
            .thenAccept { material ->
                val midX = (x1 + x2) / 2
                val midZ = (z1 + z2) / 2
                val length = sqrt((x2 - x1).pow(2) + (z2 - z1).pow(2))
                
                val cylinder = ShapeFactory.makeCylinder(0.02f, length, Vector3.zero(), material)
                
                val lineNode = Node().apply {
                    renderable = cylinder
                    localPosition = Vector3(midX, 0f, midZ)
                    // TODO: Add proper rotation to align cylinder with line direction
                }
                
                scene?.addChild(lineNode)
                boundaryNodes.add(lineNode)
            }
    }
    
    private fun latLonToENU(lat: Double, lon: Double, originLat: Double, originLon: Double): Pair<Float, Float> {
        // Convert lat/lon difference to local East-North-Up coordinates
        val dLat = Math.toRadians(lat - originLat)
        val dLon = Math.toRadians(lon - originLon)
        
        val east = (dLon * cos(Math.toRadians(originLat)) * EARTH_RADIUS_M).toFloat()
        val north = (dLat * EARTH_RADIUS_M).toFloat()
        
        return Pair(east, north)
    }
    
    private fun clearExistingBoundaries() {
        boundaryNodes.forEach { node ->
            scene?.removeChild(node)
        }
        boundaryNodes.clear()
        Log.d(TAG, "Cleared existing boundary nodes")
    }
    
    fun onResume() {
        try {
            session?.resume()
        } catch (e: Exception) {
            Log.e(TAG, "Error resuming AR session: ${e.message}")
        }
    }
    
    fun onPause() {
        session?.pause()
    }
    
    fun cleanup() {
        clearExistingBoundaries()
        session?.close()
        session = null
        isInitialized = false
    }
}