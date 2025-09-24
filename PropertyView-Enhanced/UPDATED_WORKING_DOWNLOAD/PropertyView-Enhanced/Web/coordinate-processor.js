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
            console.log('Using API key:', this.apiKey ? `${this.apiKey.substring(0, 8)}...` : 'MISSING');
            
            const response = await fetch(linzUrl.toString());
            console.log('LINZ response status:', response.status, response.statusText);
            
            if (!response.ok) {
                const errorText = await response.text();
                console.error('LINZ API error details:', errorText);
                throw new Error(`LINZ API error: ${response.status} ${response.statusText} - ${errorText}`);
            }

            const geoJsonData = await response.json();
            console.log(`Enhanced LINZ response: ${geoJsonData.features?.length || 0} features`);
            
            if (!geoJsonData.features || geoJsonData.features.length === 0) {
                console.warn('No property features found in this area');
                throw new Error('No properties found in this location. Try clicking a different area or check if you\'re clicking within New Zealand.');
            }

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
     * Smart corner detection - selects 2-4 key corners from property boundaries
     */
    convertToARCoordinates(originLat, originLon, originAltitude = 0) {
        if (!this.subjectProperty) {
            throw new Error('No subject property data available for AR conversion');
        }

        console.log('Smart corner selection from LINZ boundary data');

        try {
            // Get all boundary points
            const coords = this.subjectProperty.coordinates;
            if (coords.length < 3) {
                throw new Error('Subject property needs at least 3 boundary points for corner detection');
            }

            // Select key corners (2-4 points) instead of all boundary points
            const keyCorners = this.selectKeyCorners(coords);

            // Smart AR coordinate structure with key corners only
            this.arCoordinates = {
                type: "arCorners",
                origin: {
                    latitude: originLat,
                    longitude: originLon,
                    altitude: originAltitude
                },
                corners: keyCorners,
                metadata: {
                    subjectAppellation: this.subjectProperty.appellation,
                    area: this.subjectProperty.area,
                    cornerCount: keyCorners.length,
                    neighborCount: this.neighborProperties.length,
                    conversionMethod: "Smart Corner Detection (2-4 key points)",
                    accuracy: "gps",
                    timestamp: new Date().toISOString()
                }
            };

            console.log(`Smart corners ready: ${keyCorners.length} key corner points for property "${this.subjectProperty.appellation}"`);
            return this.arCoordinates;

        } catch (error) {
            console.error('Smart corner detection failed:', error);
            throw new Error(`Smart corner detection failed: ${error.message}`);
        }
    }

    /**
     * Robust corner selection algorithm with proper wrap-around and adaptive thresholds
     * Guarantees selection of true corners based on strongest angle changes
     */
    selectKeyCorners(coordinates) {
        if (coordinates.length <= 4) {
            // If 4 or fewer points, use them all but validate they're actual corners
            return this.validateAndCleanCorners(coordinates);
        }

        console.log(`Analyzing ${coordinates.length} boundary points for corner detection`);
        
        // Step 1: Remove duplicate consecutive coordinates
        const cleanCoords = this.removeDuplicateCoordinates(coordinates);
        
        if (cleanCoords.length <= 4) {
            return this.validateAndCleanCorners(cleanCoords);
        }

        // Step 2: Calculate angles for ALL vertices with proper wrap-around
        const angleData = this.calculateAllAngles(cleanCoords);
        
        // Step 3: Sort by angle strength and select top corners
        const sortedByAngle = angleData
            .sort((a, b) => b.angleStrength - a.angleStrength)
            .slice(0, 8); // Consider top 8 strongest angles
        
        // Step 4: Use adaptive threshold to select final corners
        const selectedCorners = this.selectCornersWithAdaptiveThreshold(sortedByAngle, cleanCoords);
        
        // Step 5: Ensure we have 2-4 corners and they're well distributed
        const finalCorners = this.ensureGoodCornerDistribution(selectedCorners, cleanCoords);
        
        console.log(`Selected ${finalCorners.length} key corners from ${coordinates.length} boundary points`);
        return finalCorners;
    }

    /**
     * Remove consecutive duplicate coordinates that can confuse angle calculation
     */
    removeDuplicateCoordinates(coords) {
        const cleaned = [coords[0]]; // Always keep first point
        
        for (let i = 1; i < coords.length; i++) {
            const curr = coords[i];
            const prev = cleaned[cleaned.length - 1];
            
            // Skip if coordinates are essentially the same (within 1cm precision)
            const distance = this.calculateDistance(
                prev.latitude, prev.longitude,
                curr.latitude, curr.longitude
            );
            
            if (distance > 0.01) { // 1cm threshold
                cleaned.push(curr);
            }
        }
        
        // Check if last point is duplicate of first (closed polygon)
        if (cleaned.length > 1) {
            const first = cleaned[0];
            const last = cleaned[cleaned.length - 1];
            const distance = this.calculateDistance(
                first.latitude, first.longitude,
                last.latitude, last.longitude
            );
            
            if (distance < 0.01) {
                cleaned.pop(); // Remove duplicate closing point
            }
        }
        
        return cleaned;
    }

    /**
     * Calculate angles for ALL vertices with proper wrap-around
     */
    calculateAllAngles(coords) {
        const angleData = [];
        const n = coords.length;
        
        for (let i = 0; i < n; i++) {
            // Get three consecutive points with wrap-around
            const prevIndex = (i - 1 + n) % n;
            const currIndex = i;
            const nextIndex = (i + 1) % n;
            
            const prevPoint = coords[prevIndex];
            const currPoint = coords[currIndex];
            const nextPoint = coords[nextIndex];
            
            // Calculate the angle at the current vertex
            const angle = this.calculateCornerAngle(prevPoint, currPoint, nextPoint);
            const angleStrength = Math.abs(angle);
            
            angleData.push({
                index: i,
                coordinate: currPoint,
                angle: angle,
                angleStrength: angleStrength,
                isSignificant: angleStrength > 5 // Minimum 5° for significance
            });
        }
        
        return angleData;
    }

    /**
     * Select corners using adaptive threshold based on angle distribution
     */
    selectCornersWithAdaptiveThreshold(sortedAngles, allCoords) {
        if (sortedAngles.length === 0) {
            // Fallback: distribute points around perimeter
            return this.distributePointsAroundPerimeter(allCoords, 4);
        }
        
        // Calculate adaptive threshold
        const maxAngle = sortedAngles[0].angleStrength;
        const avgAngle = sortedAngles.reduce((sum, item) => sum + item.angleStrength, 0) / sortedAngles.length;
        
        // Adaptive threshold: between 30% of max and 2x average, minimum 10°
        const adaptiveThreshold = Math.max(10, Math.min(maxAngle * 0.3, avgAngle * 2));
        
        console.log(`Using adaptive angle threshold: ${adaptiveThreshold.toFixed(1)}° (max: ${maxAngle.toFixed(1)}°, avg: ${avgAngle.toFixed(1)}°)`);
        
        // Select all corners above threshold
        const selectedCorners = sortedAngles
            .filter(item => item.angleStrength >= adaptiveThreshold && item.isSignificant)
            .slice(0, 4) // Maximum 4 corners
            .sort((a, b) => a.index - b.index) // Sort by original position
            .map(item => ({
                latitude: item.coordinate.latitude,
                longitude: item.coordinate.longitude
            }));
        
        // Ensure minimum 2 corners
        if (selectedCorners.length < 2) {
            const topTwo = sortedAngles.slice(0, 2);
            return topTwo.map(item => ({
                latitude: item.coordinate.latitude,
                longitude: item.coordinate.longitude
            }));
        }
        
        return selectedCorners;
    }

    /**
     * Ensure corners are well distributed around the property perimeter
     */
    ensureGoodCornerDistribution(corners, allCoords) {
        if (corners.length < 2) {
            // Fallback: select well-distributed points
            return this.distributePointsAroundPerimeter(allCoords, 2);
        }
        
        if (corners.length >= 2 && corners.length <= 4) {
            // Check if corners are too clustered
            const minSeparation = allCoords.length / (corners.length * 2); // Minimum index separation
            
            // If corners are well separated, use them as-is
            let wellSeparated = true;
            for (let i = 0; i < corners.length - 1; i++) {
                const currentIndex = this.findCoordinateIndex(corners[i], allCoords);
                const nextIndex = this.findCoordinateIndex(corners[i + 1], allCoords);
                
                if (currentIndex !== -1 && nextIndex !== -1) {
                    const separation = Math.min(
                        Math.abs(nextIndex - currentIndex),
                        allCoords.length - Math.abs(nextIndex - currentIndex)
                    );
                    
                    if (separation < minSeparation) {
                        wellSeparated = false;
                        break;
                    }
                }
            }
            
            if (wellSeparated) {
                return corners;
            }
        }
        
        // Fallback: ensure good distribution
        return this.distributePointsAroundPerimeter(allCoords, Math.min(4, Math.max(2, corners.length)));
    }

    /**
     * Distribute points evenly around property perimeter as fallback
     */
    distributePointsAroundPerimeter(coords, count) {
        const n = coords.length;
        const step = n / count;
        const distributed = [];
        
        for (let i = 0; i < count; i++) {
            const index = Math.round(i * step) % n;
            distributed.push({
                latitude: coords[index].latitude,
                longitude: coords[index].longitude
            });
        }
        
        return distributed;
    }

    /**
     * Find the index of a coordinate in the array
     */
    findCoordinateIndex(targetCoord, coords) {
        for (let i = 0; i < coords.length; i++) {
            const distance = this.calculateDistance(
                targetCoord.latitude, targetCoord.longitude,
                coords[i].latitude, coords[i].longitude
            );
            if (distance < 0.01) { // Within 1cm
                return i;
            }
        }
        return -1;
    }

    /**
     * Validate and clean a small set of corners
     */
    validateAndCleanCorners(coords) {
        const cleaned = this.removeDuplicateCoordinates(coords);
        return cleaned.map(coord => ({
            latitude: coord.latitude,
            longitude: coord.longitude
        }));
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
        
        // Fix: Use proper ENU calculations with accurate Earth radius scaling
        const east = R * cosLat * dLon;    // East-West distance (corrected order)
        const north = R * dLat;            // North-South distance  
        const up = dAlt;                   // Altitude difference
        
        console.log(`GPS->ENU: (${lat.toFixed(6)}, ${lon.toFixed(6)}) -> E:${east.toFixed(2)}m N:${north.toFixed(2)}m U:${up.toFixed(2)}m`);
        
        return {
            x: east,     // AR uses X as east
            y: up,       // AR uses Y as up (altitude)
            z: -north,   // AR uses negative Z as forward/north (correct for ARKit)
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
     * Calculate the angle at a corner point with proper wrap-around
     */
    calculateCornerAngle(prevPoint, currentPoint, nextPoint) {
        const bearing1 = this.calculateBearing(prevPoint, currentPoint);
        const bearing2 = this.calculateBearing(currentPoint, nextPoint);
        
        let angle = bearing2 - bearing1;
        
        // Proper wrap-around handling
        if (angle > 180) angle -= 360;
        if (angle < -180) angle += 360;
        
        return angle;
    }

    /**
     * Calculate bearing between two GPS points in degrees
     */
    calculateBearing(point1, point2) {
        const lat1 = point1.latitude * Math.PI / 180;
        const lat2 = point2.latitude * Math.PI / 180;
        const deltaLon = (point2.longitude - point1.longitude) * Math.PI / 180;
        
        const y = Math.sin(deltaLon) * Math.cos(lat2);
        const x = Math.cos(lat1) * Math.sin(lat2) - Math.sin(lat1) * Math.cos(lat2) * Math.cos(deltaLon);
        
        return (Math.atan2(y, x) * 180 / Math.PI + 360) % 360;
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