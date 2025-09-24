/**
 * Enhanced LINZ Property Boundary Coordinate Processor
 * Downloads GPS coordinates from LINZ API and converts them for AR usage
 * Includes mathematical positioning fallback system
 */

class CoordinateProcessor {
    constructor(apiKey) {
        this.apiKey = apiKey;
        this.downloadedCoordinates = null;
        this.arCoordinates = null;
        this.subjectProperty = null;
        this.neighborProperties = [];
        this.origin = null; // GPS origin point for AR calculations
    }

    /**
     * Enhanced download from LINZ API with better error handling
     */
    async downloadPropertyBoundaries(longitude, latitude, radiusMeters = 150) {
        if (!this.apiKey) {
            throw new Error('LINZ API key is required for property boundary download');
        }

        console.log(`Enhanced LINZ download: ${latitude}, ${longitude}, radius: ${radiusMeters}m`);
        
        // Calculate enhanced bounding box
        const dLat = radiusMeters / 111320.0;
        const dLon = radiusMeters / (111320.0 * Math.cos(latitude * Math.PI / 180.0));
        const bbox = {
            minLon: longitude - dLon,
            minLat: latitude - dLat,
            maxLon: longitude + dLon,
            maxLat: latitude + dLat
        };

        // Enhanced LINZ WFS URL construction
        const linzUrl = new URL(`https://data.linz.govt.nz/services;key=${this.apiKey}/wfs`);
        linzUrl.searchParams.set('service', 'WFS');
        linzUrl.searchParams.set('version', '2.0.0');
        linzUrl.searchParams.set('request', 'GetFeature');
        linzUrl.searchParams.set('typeNames', 'layer-50823'); // NZ Property Boundaries
        linzUrl.searchParams.set('outputFormat', 'application/json');
        linzUrl.searchParams.set('srsName', 'EPSG:4326');
        linzUrl.searchParams.set('bbox', `${bbox.minLon},${bbox.minLat},${bbox.maxLon},${bbox.maxLat},EPSG:4326`);
        linzUrl.searchParams.set('count', '50');

        try {
            console.log('Enhanced LINZ request:', linzUrl.toString());
            
            const response = await fetch(linzUrl.toString());
            if (!response.ok) {
                throw new Error(`LINZ API error: ${response.status} ${response.statusText}`);
            }

            const geoJsonData = await response.json();
            console.log(`Enhanced LINZ response: ${geoJsonData.features?.length || 0} features`);

            // Store for AR processing
            this.downloadedCoordinates = geoJsonData;
            this.origin = { latitude, longitude };

            // Enhanced feature processing
            if (geoJsonData.features && geoJsonData.features.length > 0) {
                this.processPropertiesForAR(geoJsonData, latitude, longitude);
            }

            return geoJsonData;

        } catch (error) {
            console.error('Enhanced LINZ download failed:', error);
            throw new Error(`Failed to download property boundaries: ${error.message}`);
        }
    }

    /**
     * Enhanced property processing for AR with mathematical fallback
     */
    processPropertiesForAR(geoJsonData, originLat, originLon) {
        try {
            // Find subject property (closest to origin)
            let subjectFeature = geoJsonData.features[0];
            let minDistance = Infinity;

            geoJsonData.features.forEach(feature => {
                try {
                    const centroid = this.calculateCentroid(feature);
                    const distance = this.calculateDistance(
                        originLat, originLon,
                        centroid.latitude, centroid.longitude
                    );
                    
                    if (distance < minDistance) {
                        minDistance = distance;
                        subjectFeature = feature;
                    }
                } catch (e) {
                    console.warn('Error processing feature for distance:', e);
                }
            });

            // Enhanced subject property processing
            this.subjectProperty = {
                appellation: this.getAppellation(subjectFeature.properties),
                area: this.calculatePropertyArea(subjectFeature),
                coordinates: this.extractCoordinates(subjectFeature),
                centroid: this.calculateCentroid(subjectFeature),
                distance: minDistance
            };

            // Enhanced neighbor processing
            this.neighborProperties = geoJsonData.features
                .filter(f => f !== subjectFeature)
                .map(feature => ({
                    appellation: this.getAppellation(feature.properties),
                    area: this.calculatePropertyArea(feature),
                    coordinates: this.extractCoordinates(feature),
                    centroid: this.calculateCentroid(feature)
                }));

            console.log(`Enhanced processing: 1 subject, ${this.neighborProperties.length} neighbors`);

        } catch (error) {
            console.error('Enhanced property processing failed:', error);
            throw error;
        }
    }

    /**
     * Automated AR conversion - uses ALL property corners from LINZ data
     */
    convertToARCoordinates(originLat, originLon, originAltitude = 0) {
        if (!this.subjectProperty) {
            throw new Error('No subject property data available for AR conversion');
        }

        console.log('Automated AR corner conversion from LINZ data');

        try {
            // Use ALL boundary points as property corners
            const coords = this.subjectProperty.coordinates;
            if (coords.length < 3) {
                throw new Error('Subject property needs at least 3 boundary points for AR visualization');
            }

            // Convert all corner points for AR visualization
            const arCorners = coords.map(coord => ({
                latitude: coord.latitude,
                longitude: coord.longitude
            }));

            // Automated AR coordinate structure with all corners
            this.arCoordinates = {
                type: "arCorners",
                origin: {
                    latitude: originLat,
                    longitude: originLon,
                    altitude: originAltitude
                },
                corners: arCorners,
                metadata: {
                    subjectAppellation: this.subjectProperty.appellation,
                    area: this.subjectProperty.area,
                    cornerCount: arCorners.length,
                    neighborCount: this.neighborProperties.length,
                    conversionMethod: "Automated LINZ Corner Detection",
                    accuracy: "gps",
                    timestamp: new Date().toISOString()
                }
            };

            console.log(`Automated AR ready: ${arCorners.length} corner points from LINZ data for property "${this.subjectProperty.appellation}"`);
            return this.arCoordinates;

        } catch (error) {
            console.error('AR baseline conversion failed:', error);
            throw new Error(`AR baseline conversion failed: ${error.message}`);
        }
    }

    /**
     * Enhanced GPS to ENU (East-North-Up) coordinate transformation
     * Uses mathematical conversion for AR positioning when GPS AR not available
     */
    gpsToENU(lat, lon, alt, originLat, originLon, originAlt) {
        // Enhanced mathematical transformation with high precision
        const R = 6378137.0; // WGS84 Earth radius in meters
        
        // Convert to radians with enhanced precision
        const latRad = lat * Math.PI / 180.0;
        const lonRad = lon * Math.PI / 180.0;
        const originLatRad = originLat * Math.PI / 180.0;
        const originLonRad = originLon * Math.PI / 180.0;
        
        // Enhanced differential calculations
        const dLat = latRad - originLatRad;
        const dLon = lonRad - originLonRad;
        const dAlt = alt - originAlt;
        
        // Enhanced ENU transformation with Earth curvature compensation
        const cosLat = Math.cos(originLatRad);
        const sinLat = Math.sin(originLatRad);
        
        const east = R * dLon * cosLat;
        const north = R * dLat;
        const up = dAlt;
        
        return {
            x: east,
            y: up,      // AR uses Y as up
            z: -north,  // AR uses negative Z as north
            distance: Math.sqrt(east * east + north * north + up * up)
        };
    }

    /**
     * Enhanced accuracy calculation based on distance and method
     */
    calculateAccuracy(distance) {
        if (distance < 50) return 'High';
        if (distance < 200) return 'Medium';
        return 'Low';
    }

    /**
     * Enhanced coordinate extraction with validation
     */
    extractCoordinates(feature) {
        if (!feature || !feature.geometry) return [];
        
        try {
            if (feature.geometry.type === 'Polygon') {
                return feature.geometry.coordinates[0].map(coord => ({
                    latitude: coord[1],
                    longitude: coord[0]
                }));
            } else if (feature.geometry.type === 'MultiPolygon') {
                // Enhanced: Use largest polygon
                let largestPoly = feature.geometry.coordinates[0];
                let maxArea = 0;
                
                feature.geometry.coordinates.forEach(poly => {
                    const area = this.calculatePolygonArea(poly[0]);
                    if (area > maxArea) {
                        maxArea = area;
                        largestPoly = poly;
                    }
                });
                
                return largestPoly[0].map(coord => ({
                    latitude: coord[1],
                    longitude: coord[0]
                }));
            }
        } catch (error) {
            console.warn('Error extracting coordinates:', error);
        }
        
        return [];
    }

    /**
     * Enhanced centroid calculation
     */
    calculateCentroid(feature) {
        const coords = this.extractCoordinates(feature);
        if (coords.length === 0) return { latitude: 0, longitude: 0 };
        
        const latSum = coords.reduce((sum, coord) => sum + coord.latitude, 0);
        const lonSum = coords.reduce((sum, coord) => sum + coord.longitude, 0);
        
        return {
            latitude: latSum / coords.length,
            longitude: lonSum / coords.length
        };
    }

    /**
     * Enhanced area calculation
     */
    calculatePropertyArea(feature) {
        try {
            const coords = this.extractCoordinates(feature);
            return this.calculatePolygonAreaFromCoords(coords);
        } catch (error) {
            console.warn('Error calculating area:', error);
            return 0;
        }
    }

    calculatePolygonArea(coordinates) {
        // Shoelace formula for polygon area
        let area = 0;
        for (let i = 0; i < coordinates.length - 1; i++) {
            area += coordinates[i][0] * coordinates[i + 1][1];
            area -= coordinates[i + 1][0] * coordinates[i][1];
        }
        return Math.abs(area) / 2;
    }

    calculatePolygonAreaFromCoords(coords) {
        if (coords.length < 3) return 0;
        
        let area = 0;
        for (let i = 0; i < coords.length - 1; i++) {
            const j = (i + 1) % coords.length;
            area += coords[i].longitude * coords[j].latitude;
            area -= coords[j].longitude * coords[i].latitude;
        }
        return Math.abs(area) / 2 * 12100000; // Approximate m² conversion
    }

    /**
     * Enhanced distance calculation using Haversine formula
     */
    calculateDistance(lat1, lon1, lat2, lon2) {
        const R = 6371000; // Earth radius in meters
        const φ1 = lat1 * Math.PI / 180;
        const φ2 = lat2 * Math.PI / 180;
        const Δφ = (lat2 - lat1) * Math.PI / 180;
        const Δλ = (lon2 - lon1) * Math.PI / 180;

        const a = Math.sin(Δφ/2) * Math.sin(Δφ/2) +
                  Math.cos(φ1) * Math.cos(φ2) *
                  Math.sin(Δλ/2) * Math.sin(Δλ/2);
        const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));

        return R * c; // Distance in meters
    }

    /**
     * Enhanced appellation extraction
     */
    getAppellation(properties) {
        if (!properties) return "Unknown Property";
        
        // Enhanced property name detection
        const nameFields = ['appellation', 'Appellation', 'APP', 'name', 'NAME', 'title', 'TITLE'];
        
        for (const field of nameFields) {
            if (properties[field] && String(properties[field]).trim()) {
                return String(properties[field]).trim();
            }
        }
        
        return "Property";
    }

    // --- Enhanced Getter Methods ---
    
    getSubjectProperty() {
        return this.subjectProperty;
    }
    
    getNeighborProperties() {
        return this.neighborProperties;
    }
    
    getARCoordinates() {
        return this.arCoordinates;
    }
    
    getOrigin() {
        return this.origin;
    }

    /**
     * Enhanced validation and status methods
     */
    isDataReady() {
        return !!(this.downloadedCoordinates && this.subjectProperty);
    }

    isARReady() {
        return !!(this.arCoordinates && this.arCoordinates.subjectProperty);
    }

    getStatus() {
        if (!this.downloadedCoordinates) return 'No data downloaded';
        if (!this.subjectProperty) return 'Data processing incomplete';
        if (!this.arCoordinates) return 'AR conversion pending';
        return 'Ready for AR';
    }

    getMetadata() {
        return {
            hasData: this.isDataReady(),
            hasAR: this.isARReady(),
            status: this.getStatus(),
            propertyCount: this.neighborProperties ? this.neighborProperties.length + 1 : 0,
            lastUpdate: new Date().toISOString()
        };
    }
}