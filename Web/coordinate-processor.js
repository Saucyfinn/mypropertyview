/**
 * LINZ Property Boundary Coordinate Processor
 * Downloads GPS coordinates from LINZ API and converts them for AR usage
 */

class CoordinateProcessor {
    constructor(apiKey) {
        this.apiKey = apiKey;
        this.downloadedCoordinates = null;
        this.arCoordinates = null;
        this.subjectProperty = null;
    }

    /**
     * Download property boundary coordinates from LINZ API
     */
    async downloadPropertyBoundaries(longitude, latitude, radiusMeters = 80) {
        if (!this.apiKey) {
            throw new Error('LINZ API key is required');
        }

        console.log(`Downloading property boundaries for: ${latitude}, ${longitude}`);
        
        // Calculate bounding box for LINZ WFS request
        const dLat = radiusMeters / 111320.0;
        const dLon = radiusMeters / (111320.0 * Math.cos(latitude * Math.PI / 180.0));
        const bbox = {
            minLon: longitude - dLon,
            minLat: latitude - dLat,
            maxLon: longitude + dLon,
            maxLat: latitude + dLat
        };

        // Construct LINZ WFS URL
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
            const response = await fetch(linzUrl.toString());
            if (!response.ok) {
                throw new Error(`LINZ API request failed: ${response.status} ${response.statusText}`);
            }

            const geoJsonData = await response.json();
            
            // Save raw coordinates
            this.downloadedCoordinates = geoJsonData;
            
            // Save to local file for persistence
            await this.saveCoordinatesToFile(geoJsonData, latitude, longitude);
            
            // Process and identify subject property
            this.identifySubjectProperty(latitude, longitude);
            
            console.log(`Downloaded ${geoJsonData.features?.length || 0} property boundaries`);
            return geoJsonData;
            
        } catch (error) {
            console.error('Error downloading property boundaries:', error);
            throw error;
        }
    }

    /**
     * Save downloaded coordinates to a local file
     */
    async saveCoordinatesToFile(geoJsonData, queryLat, queryLon) {
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
        const fileName = `property-boundaries-${timestamp}.json`;
        
        const dataToSave = {
            downloadedAt: new Date().toISOString(),
            queryLocation: { latitude: queryLat, longitude: queryLon },
            totalProperties: geoJsonData.features?.length || 0,
            geoJsonData: geoJsonData,
            coordinates: this.extractCoordinateArrays(geoJsonData)
        };

        try {
            // Save to browser's local storage for web app
            if (typeof localStorage !== 'undefined') {
                localStorage.setItem('last-property-download', JSON.stringify(dataToSave));
                localStorage.setItem('property-file-name', fileName);
            }
            
            // Create downloadable file
            const blob = new Blob([JSON.stringify(dataToSave, null, 2)], { type: 'application/json' });
            const url = URL.createObjectURL(blob);
            
            // For debugging - create download link
            const downloadLink = document.createElement('a');
            downloadLink.href = url;
            downloadLink.download = fileName;
            downloadLink.style.display = 'none';
            document.body.appendChild(downloadLink);
            
            console.log(`Property coordinates saved as: ${fileName}`);
            console.log('Data also saved to localStorage for persistence');
            
        } catch (error) {
            console.error('Error saving coordinates to file:', error);
        }
    }

    /**
     * Extract coordinate arrays from GeoJSON for easier processing
     */
    extractCoordinateArrays(geoJsonData) {
        const coordinateArrays = [];
        
        if (!geoJsonData.features) return coordinateArrays;
        
        geoJsonData.features.forEach((feature, index) => {
            if (feature.geometry && feature.geometry.coordinates) {
                const propertyInfo = {
                    propertyId: index,
                    appellation: feature.properties?.appellation || feature.properties?.Appellation || `Property ${index + 1}`,
                    geometry: feature.geometry,
                    coordinates: this.flattenCoordinates(feature.geometry),
                    boundingBox: this.calculateBoundingBox(feature.geometry)
                };
                coordinateArrays.push(propertyInfo);
            }
        });
        
        return coordinateArrays;
    }

    /**
     * Flatten geometry coordinates to simple array
     */
    flattenCoordinates(geometry) {
        const coords = [];
        
        if (geometry.type === 'Polygon') {
            geometry.coordinates.forEach(ring => {
                ring.forEach(coord => {
                    coords.push({ longitude: coord[0], latitude: coord[1] });
                });
            });
        } else if (geometry.type === 'MultiPolygon') {
            geometry.coordinates.forEach(polygon => {
                polygon.forEach(ring => {
                    ring.forEach(coord => {
                        coords.push({ longitude: coord[0], latitude: coord[1] });
                    });
                });
            });
        }
        
        return coords;
    }

    /**
     * Calculate bounding box for a geometry
     */
    calculateBoundingBox(geometry) {
        let minLon = Infinity, minLat = Infinity;
        let maxLon = -Infinity, maxLat = -Infinity;
        
        const processCoords = (coords) => {
            coords.forEach(coord => {
                minLon = Math.min(minLon, coord[0]);
                maxLon = Math.max(maxLon, coord[0]);
                minLat = Math.min(minLat, coord[1]);
                maxLat = Math.max(maxLat, coord[1]);
            });
        };
        
        if (geometry.type === 'Polygon') {
            geometry.coordinates.forEach(ring => processCoords(ring));
        } else if (geometry.type === 'MultiPolygon') {
            geometry.coordinates.forEach(polygon => {
                polygon.forEach(ring => processCoords(ring));
            });
        }
        
        return { minLon, minLat, maxLon, maxLat };
    }

    /**
     * Identify the subject property (closest to query point)
     */
    identifySubjectProperty(queryLat, queryLon) {
        if (!this.downloadedCoordinates?.features) return null;
        
        let closestProperty = null;
        let minDistance = Infinity;
        
        this.downloadedCoordinates.features.forEach((feature, index) => {
            if (feature.geometry) {
                try {
                    // Calculate centroid using turf.js if available
                    let centroid;
                    if (typeof turf !== 'undefined') {
                        centroid = turf.centroid(feature).geometry.coordinates;
                    } else {
                        // Fallback: use bounding box center
                        const bbox = this.calculateBoundingBox(feature.geometry);
                        centroid = [(bbox.minLon + bbox.maxLon) / 2, (bbox.minLat + bbox.maxLat) / 2];
                    }
                    
                    const distance = this.calculateDistance(queryLat, queryLon, centroid[1], centroid[0]);
                    if (distance < minDistance) {
                        minDistance = distance;
                        closestProperty = { feature, index, distance };
                    }
                } catch (error) {
                    console.warn(`Error processing property ${index}:`, error);
                }
            }
        });
        
        this.subjectProperty = closestProperty;
        console.log(`Subject property identified: ${closestProperty?.feature?.properties?.appellation || 'Unknown'}`);
        return closestProperty;
    }

    /**
     * Calculate distance between two lat/lon points (Haversine formula)
     */
    calculateDistance(lat1, lon1, lat2, lon2) {
        const R = 6371000; // Earth's radius in meters
        const dLat = (lat2 - lat1) * Math.PI / 180;
        const dLon = (lon2 - lon1) * Math.PI / 180;
        const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
                Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
                Math.sin(dLon/2) * Math.sin(dLon/2);
        const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
        return R * c;
    }

    /**
     * Convert GPS coordinates to AR coordinate system
     */
    convertToARCoordinates(originLat, originLon, originAlt = 0) {
        if (!this.subjectProperty) {
            throw new Error('No subject property identified. Download boundaries first.');
        }
        
        const arCoordinates = {
            origin: { latitude: originLat, longitude: originLon, altitude: originAlt },
            subjectProperty: {
                appellation: this.subjectProperty.feature.properties?.appellation || 'Unknown',
                arPoints: []
            },
            neighborProperties: []
        };
        
        // Convert subject property coordinates
        const subjectCoords = this.flattenCoordinates(this.subjectProperty.feature.geometry);
        subjectCoords.forEach((coord, index) => {
            const arPoint = this.gpsToARCoordinate(
                originLat, originLon, originAlt,
                coord.latitude, coord.longitude, 0
            );
            arCoordinates.subjectProperty.arPoints.push({
                id: index,
                originalGPS: coord,
                arPosition: arPoint
            });
        });
        
        // Convert neighbor properties
        this.downloadedCoordinates.features.forEach((feature, featureIndex) => {
            if (featureIndex !== this.subjectProperty.index) {
                const neighborCoords = this.flattenCoordinates(feature.geometry);
                const neighborAR = {
                    appellation: feature.properties?.appellation || `Neighbor ${featureIndex + 1}`,
                    arPoints: []
                };
                
                neighborCoords.forEach((coord, coordIndex) => {
                    const arPoint = this.gpsToARCoordinate(
                        originLat, originLon, originAlt,
                        coord.latitude, coord.longitude, 0
                    );
                    neighborAR.arPoints.push({
                        id: coordIndex,
                        originalGPS: coord,
                        arPosition: arPoint
                    });
                });
                
                arCoordinates.neighborProperties.push(neighborAR);
            }
        });
        
        this.arCoordinates = arCoordinates;
        
        // Save AR coordinates to file
        this.saveARCoordinatesToFile(arCoordinates);
        
        console.log(`Converted ${arCoordinates.subjectProperty.arPoints.length} subject points and ${arCoordinates.neighborProperties.length} neighbor properties to AR coordinates`);
        return arCoordinates;
    }

    /**
     * Convert GPS coordinates to AR coordinate system (ENU - East North Up)
     */
    gpsToARCoordinate(originLat, originLon, originAlt, targetLat, targetLon, targetAlt) {
        // Convert degrees to radians
        const lat1 = originLat * Math.PI / 180;
        const lon1 = originLon * Math.PI / 180;
        const lat2 = targetLat * Math.PI / 180;
        const lon2 = targetLon * Math.PI / 180;
        
        // Earth's radius
        const R = 6378137.0; // WGS84 equatorial radius
        
        // Calculate differences
        const dLat = lat2 - lat1;
        const dLon = lon2 - lon1;
        
        // Convert to ENU (East-North-Up) coordinates
        const east = R * dLon * Math.cos(lat1);
        const north = R * dLat;
        const up = targetAlt - originAlt;
        
        return {
            x: east,   // East (positive = east of origin)
            y: up,     // Up (positive = above origin)  
            z: -north  // Forward in AR (negative because AR uses -Z as forward)
        };
    }

    /**
     * Save AR coordinates to file
     */
    async saveARCoordinatesToFile(arCoordinates) {
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
        const fileName = `ar-coordinates-${timestamp}.json`;
        
        try {
            // Save to localStorage
            if (typeof localStorage !== 'undefined') {
                localStorage.setItem('last-ar-coordinates', JSON.stringify(arCoordinates));
                localStorage.setItem('ar-file-name', fileName);
            }
            
            // Create downloadable file
            const blob = new Blob([JSON.stringify(arCoordinates, null, 2)], { type: 'application/json' });
            const url = URL.createObjectURL(blob);
            
            console.log(`AR coordinates saved as: ${fileName}`);
            return { fileName, url, data: arCoordinates };
            
        } catch (error) {
            console.error('Error saving AR coordinates:', error);
            throw error;
        }
    }

    /**
     * Load previously saved coordinates
     */
    loadSavedCoordinates() {
        try {
            const savedData = localStorage.getItem('last-property-download');
            const savedAR = localStorage.getItem('last-ar-coordinates');
            
            if (savedData) {
                const data = JSON.parse(savedData);
                this.downloadedCoordinates = data.geoJsonData;
                console.log('Loaded saved property coordinates');
            }
            
            if (savedAR) {
                this.arCoordinates = JSON.parse(savedAR);
                console.log('Loaded saved AR coordinates');
            }
            
            return { hasPropertyData: !!savedData, hasARData: !!savedAR };
        } catch (error) {
            console.error('Error loading saved coordinates:', error);
            return { hasPropertyData: false, hasARData: false };
        }
    }

    /**
     * Get current coordinates for AR system
     */
    getARCoordinates() {
        return this.arCoordinates;
    }

    /**
     * Get subject property data
     */
    getSubjectProperty() {
        return this.subjectProperty;
    }

    /**
     * Get all downloaded property data
     */
    getDownloadedCoordinates() {
        return this.downloadedCoordinates;
    }
}

// Export for use in other files
if (typeof window !== 'undefined') {
    window.CoordinateProcessor = CoordinateProcessor;
}