/**
 * Cross-Platform Bridge API for PropertyMapApp
 * Handles communication between web mapping interface and native AR viewers
 * Works on both iOS (WKWebView) and Android (WebView)
 */

class PropertyBridge {
    constructor() {
        this.platform = this.detectPlatform();
        this.setupMessageHandlers();
    }

    detectPlatform() {
        if (window.webkit && window.webkit.messageHandlers) {
            return 'ios';
        } else if (window.Android) {
            return 'android';
        } else {
            return 'web';
        }
    }

    setupMessageHandlers() {
        // Expose global functions for native platforms to call
        window.receiveLocation = (latitude, longitude) => {
            this.handleLocationUpdate(latitude, longitude);
        };

        window.receiveApiKeys = (keys) => {
            this.handleApiKeys(keys);
        };
    }

    // Send log message to native platform
    log(message) {
        const logMessage = `[Web] ${new Date().toISOString()}: ${message}`;
        
        switch (this.platform) {
            case 'ios':
                if (window.webkit.messageHandlers.iosLog) {
                    window.webkit.messageHandlers.iosLog.postMessage(logMessage);
                }
                break;
            case 'android':
                if (window.Android && window.Android.log) {
                    window.Android.log(logMessage);
                }
                break;
            default:
                console.log(logMessage);
        }
    }

    // Request current location from native platform
    requestLocation() {
        this.log('Requesting location from native platform');
        
        switch (this.platform) {
            case 'ios':
                if (window.webkit.messageHandlers.requestLocation) {
                    window.webkit.messageHandlers.requestLocation.postMessage('');
                }
                break;
            case 'android':
                if (window.Android && window.Android.requestLocation) {
                    window.Android.requestLocation();
                }
                break;
            default:
                this.log('Location request not supported on web platform');
        }
    }

    // Send property boundary data to native AR viewer
    sendPropertyDataToAR(boundaryData) {
        const propertyPayload = this.createPropertyPayload(boundaryData);
        this.log(`Sending property data to AR: ${propertyPayload.coordinates.length} coordinates`);
        
        switch (this.platform) {
            case 'ios':
                if (window.webkit.messageHandlers.propertyData) {
                    window.webkit.messageHandlers.propertyData.postMessage(propertyPayload);
                }
                break;
            case 'android':
                if (window.Android && window.Android.receivePropertyData) {
                    window.Android.receivePropertyData(JSON.stringify(propertyPayload));
                }
                break;
            default:
                this.log('AR data transfer not supported on web platform');
        }
    }

    // Open native AR view
    openARView() {
        this.log('Opening AR view on native platform');
        
        switch (this.platform) {
            case 'ios':
                if (window.webkit.messageHandlers.openAR) {
                    window.webkit.messageHandlers.openAR.postMessage('');
                }
                break;
            case 'android':
                if (window.Android && window.Android.openARView) {
                    window.Android.openARView();
                }
                break;
            default:
                this.log('AR view not supported on web platform');
                alert('AR functionality requires the mobile app. Please download PropertyMapApp for iOS or Android.');
        }
    }

    // Create standardized property payload for AR viewers
    createPropertyPayload(boundaryData) {
        const { geometry, property } = boundaryData;
        
        // Extract coordinates from property boundary geometry
        const coordinates = [];
        if (geometry && geometry.coordinates && geometry.coordinates[0]) {
            for (const coord of geometry.coordinates[0]) {
                coordinates.push({
                    latitude: coord[1],
                    longitude: coord[0]
                });
            }
        }

        // Standardized property data schema
        return {
            version: "1.0",
            timestamp: new Date().toISOString(),
            coordinates: coordinates,
            property: {
                id: property.id || '',
                appellation: property.appellation || '',
                address: property.address || '',
                area: property.calc_area || 0,
                landDistrict: property.land_district || '',
                region: property.region || '',
                territorialAuthority: property.territorial_authority || ''
            },
            metadata: {
                source: 'LINZ',
                coordinateSystem: 'EPSG:4326', // WGS84
                units: 'degrees'
            }
        };
    }

    // Handle location updates from native platform
    handleLocationUpdate(latitude, longitude) {
        this.log(`Received location: ${latitude}, ${longitude}`);
        
        // Update global location for map centering
        if (window.updateMapLocation) {
            window.updateMapLocation(latitude, longitude);
        }
    }

    // Handle API keys from native platform
    handleApiKeys(keys) {
        this.log('Received API keys from native platform');
        
        // Store keys globally for map initialization
        window.apiKeys = keys;
        
        // Initialize map if not already done
        if (window.initializeMapWithKeys) {
            window.initializeMapWithKeys(keys);
        }
    }

    // Get platform info for debugging
    getPlatformInfo() {
        return {
            platform: this.platform,
            userAgent: navigator.userAgent,
            capabilities: {
                webkit: !!window.webkit,
                android: !!window.Android,
                geolocation: !!navigator.geolocation
            }
        };
    }
}

// Initialize bridge when DOM is ready
document.addEventListener('DOMContentLoaded', function() {
    window.propertyBridge = new PropertyBridge();
    console.log('PropertyBridge initialized for platform:', window.propertyBridge.platform);
});

// Export for module systems
if (typeof module !== 'undefined' && module.exports) {
    module.exports = PropertyBridge;
}