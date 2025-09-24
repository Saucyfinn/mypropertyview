package com.propertymap.android.data

import com.google.gson.annotations.SerializedName

/**
 * Data classes for property boundary information
 * Matches the boundary-schema.json specification
 */
data class PropertyBoundaryData(
    val version: String,
    val timestamp: String,
    val coordinates: List<Coordinate>,
    val property: PropertyInfo,
    val metadata: Metadata
)

data class Coordinate(
    val latitude: Double,
    val longitude: Double
)

data class PropertyInfo(
    val id: String,
    val appellation: String,
    val address: String,
    val area: Double,
    @SerializedName("landDistrict")
    val landDistrict: String,
    val region: String,
    @SerializedName("territorialAuthority")
    val territorialAuthority: String
)

data class Metadata(
    val source: String,
    @SerializedName("coordinateSystem")
    val coordinateSystem: String,
    val units: String
)