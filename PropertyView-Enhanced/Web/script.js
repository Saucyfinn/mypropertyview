// --- Enhanced PropertyView Configuration ----------------------------------------
const LINZ_KEY = window.LINZ_API_KEY || ""; // Will be set by environment or prompt user
const LOCATIONIQ_KEY = window.LOCATIONIQ_API_KEY || ""; // LocationIQ API for address search
const GOOGLE_KEY = window.GOOGLE_API_KEY || ""; // Google API for enhanced geolocation
const SEARCH_RADIUS_M = 150;                    // Enhanced search radius

// Initialize coordinate processor for AR support
let coordinateProcessor = null;
let googleGeoManager = null;

// Check for LINZ API key and initialize or prompt user
function initializeLINZIntegration() {
    const storedKey = localStorage.getItem('linz_api_key');
    const envKey = window.LINZ_API_KEY;
    const urlKey = new URLSearchParams(window.location.search).get('linz_key');
    
    const apiKey = envKey || urlKey || storedKey;
    
    console.log('LINZ integration check:', {
        envKey: !!envKey,
        urlKey: !!urlKey, 
        storedKey: !!storedKey,
        finalKey: !!apiKey
    });
    
    if (apiKey && apiKey.trim()) {
        coordinateProcessor = new CoordinateProcessor(apiKey.trim());
        if (urlKey && urlKey !== storedKey) {
            localStorage.setItem('linz_api_key', urlKey.trim());
        }
        console.log('LINZ integration initialized successfully with key:', apiKey.substring(0, 8) + '...');
        // Don't set status text here - let automatic location detection handle it
        return true;
    } else {
        console.log('No LINZ API key found, prompting user');
        // Prompt user for API key
        promptForLINZKey();
        return false;
    }
}

function promptForLINZKey() {
    const apiKey = prompt(
        'Enter your LINZ API Key for property boundary data:\n\n' +
        'Get one free at: https://data.linz.govt.nz/\n' +
        'Create account → Request API Key → Copy key here'
    );
    
    if (apiKey && apiKey.trim()) {
        localStorage.setItem('linz_api_key', apiKey.trim());
        coordinateProcessor = new CoordinateProcessor(apiKey.trim());
        setTopText("Property: <strong>LINZ API key saved! Finding your location...</strong>");
        // Restart automatic location detection after saving key
        setTimeout(() => getUserLocationAutomatically(), 500);
        return true;
    } else {
        setTopText("Property: <strong>LINZ API key required for property boundary data</strong>");
        return false;
    }
}

// Initialize LINZ integration on load (moved to autoStart for proper timing)
// initializeLINZIntegration();

const FIT_PADDING_PX = 24;            // padding around subject bounds
const FIT_MAX_ZOOM = 18;              // cap zoom when fitting

// Optional: District Plan zoning via WFS (configure per council/vendor)
const ZONING_WFS = {
  url: "",                             // e.g. "https://<council>/geoserver/wfs"
  typeName: "",                        // e.g. "plan:district_zones"
  srsName: "EPSG:4326",
  propertyKeys: ["zone","Zone","ZONE","ZONING","Zoning","ZONE_NAME","planning_zone","PlanningZone","zone_desc"],
  searchRadiusM: 60
};

// --- Enhanced Map Setup (Will be initialized after DOM is ready) ----------------------
let map, subjectProperty, neighborProperties, baseLayers;

// Enhanced layer state tracking
let showNeighbors = true;
let currentSatelliteLayer = null;

// --- Enhanced UI Controls --------------------------------------------------------
let statusEl, exportBtn, neighborsBtn, satelliteBtn;

function createFloatingControls() {
  // Enhanced property status display
  const statusDiv = document.createElement('div');
  statusDiv.className = 'property-status';
  statusDiv.id = 'pv-status';
  statusDiv.innerHTML = 'Property: <strong>—</strong>';
  document.body.appendChild(statusDiv);
  statusEl = statusDiv;

  // Enhanced map layer toggle button (OSM → LINZ → Satellite)
  const mapLayerButton = document.createElement('button');
  mapLayerButton.className = 'floating-btn';
  mapLayerButton.id = 'map-layer-toggle';
  mapLayerButton.innerHTML = '🗺️ Maps';
  mapLayerButton.style.top = '80px';
  document.body.appendChild(mapLayerButton);
  satelliteBtn = mapLayerButton;

  // Neighbors toggle button
  const neighborsButton = document.createElement('button');
  neighborsButton.className = 'floating-btn active';
  neighborsButton.id = 'neighbors-toggle';
  neighborsButton.textContent = 'Neighbors';
  neighborsButton.style.top = '130px';
  document.body.appendChild(neighborsButton);
  neighborsBtn = neighborsButton;

  // AR Alignment button
  const alignmentButton = document.createElement('button');
  alignmentButton.className = 'floating-btn';
  alignmentButton.id = 'ar-alignment';
  alignmentButton.textContent = 'Set AR Points';
  alignmentButton.disabled = true;
  alignmentButton.style.top = '180px';
  document.body.appendChild(alignmentButton);
  
  // Export KML button
  const exportButton = document.createElement('button');
  exportButton.className = 'floating-btn';
  exportButton.id = 'pv-export';
  exportButton.textContent = 'Export KML';
  exportButton.disabled = true;
  exportButton.style.top = '230px';
  document.body.appendChild(exportButton);
  exportBtn = exportButton;

  // AR View button (bottom of screen)
  const arButton = document.createElement('button');
  arButton.className = 'ar-view-btn';
  arButton.id = 'ar-btn';
  arButton.textContent = 'Open AR View';
  arButton.disabled = true;
  document.body.appendChild(arButton);
}

// Controls will be created after map initialization

// --- Enhanced Property Management ------------------------------------------------
let subjectPin = null;
let subjectFeature = null;
let currentQueryLatLng = null;
let subjectCenterLatLng = null;

// AR Alignment state
let alignmentMode = false;
let alignmentPoints = [];
let alignmentMarkers = [];
let cornerSelectionPins = [];

function updateSubjectPin(latlng) {
  if (!latlng) return;
  if (subjectPin) subjectPin.setLatLng(latlng);
  else subjectPin = L.marker(latlng).addTo(map);
}

function setTopText(html) { if (statusEl) statusEl.innerHTML = html; }
function setZoneText(html) { if (statusEl) statusEl.innerHTML = html; }

// Enhanced utility functions - Fixed for actual LINZ property field names
function getAppellation(props) {
  if (!props) return null;
  
  // Debug: Log available property keys to understand LINZ data structure
  if (Object.keys(props).length > 0) {
    console.log('Available LINZ property fields:', Object.keys(props));
  }
  
  // Check common LINZ field names for property appellations
  const candidates = [
    'appellation', 'full_appellation', 'legal_desc', 'title_no',
    'Appellation', 'APPELLATION', 'APP', 'name', 'legal_description',
    'parcel_id', 'id', 'title', 'description', 'full_legal_desc'
  ];
  
  for (const key of candidates) {
    if (props[key] && typeof props[key] === 'string' && props[key].trim()) {
      return props[key].trim();
    }
  }
  
  return null;
}

function calculateArea(feature) {
  try {
    return turf.area(feature);
  } catch (e) {
    return 0;
  }
}

// --- Enhanced Toggle Functions ---------------------------------------------------
// Enhanced map layer cycling: OSM → LINZ → Satellite → repeat
let currentMapLayer = 0; // 0=OSM, 1=LINZ, 2=Satellite
const mapLayerNames = ["OpenStreetMap", "LINZ Topographic", "Esri Satellite"];

function toggleMapLayers() {
  // Remove current active layer
  if (currentSatelliteLayer) {
    map.removeLayer(currentSatelliteLayer);
    currentSatelliteLayer = null;
  }
  
  // Cycle to next layer
  currentMapLayer = (currentMapLayer + 1) % mapLayerNames.length;
  
  // Skip LINZ if no API key available
  if (mapLayerNames[currentMapLayer] === "LINZ Topographic" && !baseLayers["LINZ Topographic"]) {
    currentMapLayer = (currentMapLayer + 1) % mapLayerNames.length;
  }
  
  const layerName = mapLayerNames[currentMapLayer];
  
  if (layerName === "OpenStreetMap") {
    // OpenStreetMap is the base layer, no need to add anything
    satelliteBtn.innerHTML = '🗺️ OSM';
    satelliteBtn.classList.remove('active');
  } else if (layerName === "LINZ Topographic" && baseLayers[layerName]) {
    currentSatelliteLayer = baseLayers[layerName];
    map.addLayer(currentSatelliteLayer);
    satelliteBtn.innerHTML = '🇳🇿 LINZ';
    satelliteBtn.classList.add('active');
  } else if (layerName === "Esri Satellite") {
    currentSatelliteLayer = baseLayers[layerName];
    map.addLayer(currentSatelliteLayer);
    satelliteBtn.innerHTML = '🛰️ Satellite';
    satelliteBtn.classList.add('active');
  }
}

// Legacy function for compatibility
function toggleSatellite() {
  toggleMapLayers();
}

function toggleNeighbors() {
  showNeighbors = !showNeighbors;
  if (showNeighbors) {
    if (neighborProperties.getLayers().length > 0) {
      map.addLayer(neighborProperties);
    }
    neighborsBtn.classList.add('active');
  } else {
    if (map.hasLayer(neighborProperties)) {
      map.removeLayer(neighborProperties);
    }
    neighborsBtn.classList.remove('active');
  }
}

// Enhanced AR Alignment System
function toggleARAlignment() {
  if (!subjectFeature) {
    alert('Please select a property first by clicking on the map.');
    return;
  }
  
  alignmentMode = !alignmentMode;
  const alignBtn = document.getElementById('ar-alignment');
  
  if (alignmentMode) {
    alignmentPoints = [];
    clearAlignmentMarkers();
    addCornerSelectionPins();
    alignBtn.textContent = 'Cancel AR Points';
    alignBtn.classList.add('active');
    setTopText('AR Alignment: <strong>Click 2 property corners</strong>');
  } else {
    clearAlignmentMarkers();
    clearCornerSelectionPins();
    alignBtn.textContent = 'Set AR Points';
    alignBtn.classList.remove('active');
    const app = getAppellation(subjectFeature?.properties);
    setTopText(app ? `Property: <strong>${app}</strong>` : "Property: <strong>Found</strong>");
  }
}

function clearAlignmentMarkers() {
  alignmentMarkers.forEach(marker => map.removeLayer(marker));
  alignmentMarkers = [];
}

function addAlignmentPoint(latlng) {
  if (alignmentPoints.length >= 2) return;
  
  alignmentPoints.push(latlng);
  
  const marker = L.circleMarker(latlng, {
    color: '#ff3b30',
    fillColor: '#ff3b30',
    fillOpacity: 0.8,
    radius: 8,
    weight: 2
  }).addTo(map);
  
  alignmentMarkers.push(marker);
  
  if (alignmentPoints.length === 1) {
    setTopText('AR Alignment: <strong>Click second corner</strong>');
  } else if (alignmentPoints.length === 2) {
    saveAlignmentPoints();
    toggleARAlignment();
  }
}

function saveAlignmentPoints() {
  if (alignmentPoints.length !== 2 || !subjectFeature) return;
  
  const alignmentData = {
    subjectProperty: {
      appellation: getAppellation(subjectFeature.properties) || "Unknown Property",
      alignmentPoints: alignmentPoints.map(p => ({
        latitude: p.lat,
        longitude: p.lng
      })),
      boundaries: extractCoordinatesFromFeature(subjectFeature)
    },
    timestamp: new Date().toISOString()
  };
  
  // Send to native iOS app if available
  if (window.webkit?.messageHandlers?.saveAlignmentPoints) {
    window.webkit.messageHandlers.saveAlignmentPoints.postMessage(alignmentData);
  } else {
    localStorage.setItem('arAlignmentPoints', JSON.stringify(alignmentData));
    console.log('AR alignment points saved:', alignmentData);
  }
  
  setTopText('AR Alignment: <strong>Points saved for AR</strong>');
  document.getElementById('ar-btn').disabled = false;
}

function addCornerSelectionPins() {
  if (!subjectFeature?.geometry) return;
  
  let coordinates = [];
  if (subjectFeature.geometry.type === 'Polygon') {
    coordinates = subjectFeature.geometry.coordinates[0];
  } else if (subjectFeature.geometry.type === 'MultiPolygon') {
    coordinates = subjectFeature.geometry.coordinates[0][0];
  }
  
  if (coordinates.length < 3) return;
  
  coordinates.slice(0, -1).forEach((coord, index) => {
    const latlng = L.latLng(coord[1], coord[0]);
    
    const pin = L.marker(latlng, {
      icon: L.divIcon({
        className: 'corner-selection-pin',
        html: `<div class="pin-content">
                 <div class="pin-icon">📍</div>
                 <div class="pin-label">Corner ${index + 1}</div>
               </div>`,
        iconSize: [120, 60],
        iconAnchor: [60, 50]
      })
    }).addTo(map);
    
    cornerSelectionPins.push(pin);
  });
}

function clearCornerSelectionPins() {
  cornerSelectionPins.forEach(pin => map.removeLayer(pin));
  cornerSelectionPins = [];
}

function extractCoordinatesFromFeature(feature) {
  if (!feature?.geometry) return [];
  
  if (feature.geometry.type === 'Polygon') {
    return feature.geometry.coordinates[0].map(coord => ({
      latitude: coord[1],
      longitude: coord[0]
    }));
  } else if (feature.geometry.type === 'MultiPolygon') {
    let largest = feature.geometry.coordinates[0];
    let maxArea = 0;
    
    feature.geometry.coordinates.forEach(poly => {
      try {
        const area = turf.area(turf.polygon(poly));
        if (area > maxArea) {
          maxArea = area;
          largest = poly;
        }
      } catch (e) { /* ignore */ }
    });
    
    return largest[0].map(coord => ({
      latitude: coord[1],
      longitude: coord[0]
    }));
  }
  
  return [];
}

// Enhanced AR View Integration
function openARView() {
  if (coordinateProcessor && coordinateProcessor.getSubjectProperty()) {
    const arCoords = coordinateProcessor.getARCoordinates();
    if (arCoords) {
      console.log('AR Coordinates Ready:', arCoords);
      // Switch to AR tab in iOS app
      if (window.webkit?.messageHandlers?.switchToAR) {
        window.webkit.messageHandlers.switchToAR.postMessage({
          coordinates: arCoords,
          appellation: arCoords.subjectProperty.appellation
        });
      } else {
        // Updated to work with new fullBoundaries data structure
        const boundaryCount = arCoords.subjectProperty.boundaries ? arCoords.subjectProperty.boundaries.length : 0;
        const neighborCount = arCoords.neighborProperties ? arCoords.neighborProperties.length : 0;
        alert(`AR Ready!\\n\\nSubject Property: ${arCoords.subjectProperty.appellation}\\n` + 
              `Boundary Points: ${boundaryCount}\\n` +
              `Neighbor Properties: ${neighborCount}\\n` +
              `Conversion: ${arCoords.metadata.conversionMethod}`);
      }
    } else {
      alert('Converting coordinates for AR...\\nPlease wait and try again.');
    }
  } else if (subjectProperty && subjectProperty.getLayers().length > 0) {
    alert('Property found but AR coordinates not ready.\\nClick on the map to reload property data with AR support.');
  } else {
    alert('Please select a property first by clicking on the map.');
  }
}

// --- Enhanced Property Rendering System ------------------------------------------
function renderAndCenter(gj) {
  subjectProperty.clearLayers();
  neighborProperties.clearLayers();
  
  if (!gj?.features?.length) {
    subjectFeature = null;
    subjectCenterLatLng = null;
    setTopText("Property: <strong>—</strong>");
    exportBtn.disabled = true;
    return;
  }

  // Find the subject property (closest to click point)
  let subjectFeatureData = gj.features[0];
  if (currentQueryLatLng && gj.features.length > 1) {
    let bestDistance = Infinity;
    gj.features.forEach(feature => {
      if (feature.geometry) {
        try {
          const center = turf.centroid(feature).geometry.coordinates;
          const distance = map.distance([center[1], center[0]], currentQueryLatLng);
          if (distance < bestDistance) {
            bestDistance = distance;
            subjectFeatureData = feature;
          }
        } catch (e) { /* ignore */ }
      }
    });
  }

  // Add subject property
  subjectProperty.addData(subjectFeatureData);
  
  // Add neighbors
  const neighbors = gj.features.filter(f => f !== subjectFeatureData);
  if (neighbors.length > 0) {
    neighborProperties.addData({
      type: "FeatureCollection",
      features: neighbors
    });
    
    if (showNeighbors && !map.hasLayer(neighborProperties)) {
      map.addLayer(neighborProperties);
    }
  }

  // Update global reference
  subjectFeature = subjectFeatureData;
  const layers = subjectProperty.getLayers();
  if (!layers.length) {
    subjectFeature = null;
    subjectCenterLatLng = null;
    setTopText("Property: <strong>—</strong>");
    exportBtn.disabled = true;
    return;
  }

  let subjectLayer = layers[0];
  if (currentQueryLatLng) {
    let best = Infinity;
    layers.forEach(l => {
      const c = l.getBounds().getCenter();
      const d = map.distance(c, currentQueryLatLng);
      if (d < best) { best = d; subjectLayer = l; }
    });
  }

  subjectFeature = subjectLayer.feature;
  const subjectBounds = subjectLayer.getBounds();
  const center = subjectBounds.getCenter();
  subjectCenterLatLng = center;

  const app = getAppellation(subjectFeature?.properties);
  
  // Request address via reverse geocoding from iOS bridge
  if (window.webkit?.messageHandlers?.requestAddress && center) {
    window.webkit.messageHandlers.requestAddress.postMessage({
      latitude: center.lat,
      longitude: center.lng
    });
  }
  
  setTopText(app ? `Property: <strong>${app}</strong>` : "Property: <strong>Found</strong>");

  updateSubjectPin(center);
  
  // Enhanced auto-zoom with perfect centering
  const zoom = Math.min(FIT_MAX_ZOOM, Math.max(16, map.getBoundsZoom(subjectBounds)));
  map.fitBounds(subjectBounds, { 
    padding: [FIT_PADDING_PX, FIT_PADDING_PX], 
    maxZoom: zoom 
  });
  
  // Perfect centering after zoom
  setTimeout(() => {
    map.panTo(center);
  }, 500);

  exportBtn.disabled = false;
  document.getElementById('ar-alignment').disabled = false;
  document.getElementById('ar-btn').disabled = false;
}

// --- Enhanced Request System (Real LINZ Data) ------------------------------------
async function requestParcels(lon, lat, r = SEARCH_RADIUS_M) {
  currentQueryLatLng = L.latLng(lat, lon);
  setTopText("Property: <strong>finding…</strong>");

  if (window.webkit?.messageHandlers?.getParcels) {
    window.webkit.messageHandlers.getParcels.postMessage({ lon, lat, radius: r });
    return;
  }

  // Enhanced LINZ integration with AR support
  if (coordinateProcessor) {
    try {
      setTopText("Property: <strong>downloading from LINZ…</strong>");
      const gj = await coordinateProcessor.downloadPropertyBoundaries(lon, lat, r);
      
      if (gj.features && gj.features.length > 0) {
        setTopText("Property: <strong>converting for AR…</strong>");
        const arCoords = coordinateProcessor.convertToARCoordinates(lat, lon, 0);
        console.log('AR coordinates prepared:', arCoords.subjectProperty.boundaries?.length || 0, 'boundary points for subject property');
      }
      
      renderAndCenter(gj);
    } catch (e) {
      console.error('LINZ fetch error:', e);
      if (e.message.includes('401') || e.message.includes('403')) {
        setTopText("Property: <strong>Invalid API key</strong>");
        localStorage.removeItem('linz_api_key');
        promptForLINZKey();
      } else {
        setTopText("Property: <strong>fetch failed - check connection</strong>");
      }
    }
    return;
  }

  // No API key available - prompt user  
  if (!initializeLINZIntegration()) {
    setTopText("Property: <strong>LINZ API key required</strong>");
    return; // Don't continue with automatic location if no API key
  }
}

// --- Enhanced KML Export ---------------------------------------------------------
function coordsToKml(coords) { return `${coords[0]},${coords[1]},0`; }
function ringToKml(ring) {
  const closed = ring.length && (ring[0][0] !== ring[ring.length - 1][0] || ring[0][1] !== ring[ring.length - 1][1])
    ? [...ring, ring[0]] : ring;
  return closed.map(coordsToKml).join(" ");
}

function polygonToKml(poly) {
  const outer = ringToKml(poly[0] || []);
  const holes = (poly.slice(1) || [])
    .map(h => `<innerBoundaryIs><LinearRing><coordinates>${ringToKml(h)}</coordinates></LinearRing></innerBoundaryIs>`)
    .join("");
  return `<Polygon><outerBoundaryIs><LinearRing><coordinates>${outer}</coordinates></LinearRing></outerBoundaryIs>${holes}</Polygon>`;
}

function featureToKmlPlacemark(feature) {
  const props = feature.properties || {};
  const app = getAppellation(props) || "Subject Property";
  let body = "";
  if (feature.geometry?.type === "Polygon") {
    body = polygonToKml(feature.geometry.coordinates);
  } else if (feature.geometry?.type === "MultiPolygon") {
    body = feature.geometry.coordinates.map(polygonToKml).join("");
  } else { return ""; }
  return `<Placemark><name>${app}</name><styleUrl>#boundaryStyle</styleUrl>${body}</Placemark>`;
}

function buildSubjectKml() {
  if (!subjectFeature) return null;
  const pm = featureToKmlPlacemark(subjectFeature);
  if (!pm) return null;
  
  const style = `<Style id="boundaryStyle">
    <LineStyle>
      <color>ff0000ff</color>
      <width>2</width>
    </LineStyle>
    <PolyStyle>
      <fill>0</fill>
      <outline>1</outline>
    </PolyStyle>
  </Style>`;
  
  return `<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2"><Document>${style}${pm}</Document></kml>`;
}

function exportKML() {
  const kml = buildSubjectKml();
  if (!kml) { 
    setTopText("Property: <strong>No property to export</strong>"); 
    return; 
  }

  if (window.webkit?.messageHandlers?.exportKML) {
    const b64 = btoa(unescape(encodeURIComponent(kml)));
    window.webkit.messageHandlers.exportKML.postMessage({ filename: "parcel.kml", base64: b64 });
    return;
  }

  // Browser fallback
  const blob = new Blob([kml], { type: "application/vnd.google-earth.kml+xml" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url; 
  a.download = "parcel.kml";
  document.body.appendChild(a); 
  a.click();
  setTimeout(() => { URL.revokeObjectURL(url); a.remove(); }, 0);
  setTopText("Property: <strong>Exported</strong>");
}

// --- Enhanced LocationIQ Integration for Address Search --------------------------
function setupLocationIQSearch() {
  const searchInput = document.getElementById('search-input');
  const searchBtn = document.getElementById('search-btn');
  const suggestionsContainer = document.getElementById('search-suggestions');
  
  if (!searchInput || !searchBtn) return;
  
  let searchTimeout;
  
  // Enhanced address search with autocomplete
  searchInput.addEventListener('input', function() {
    clearTimeout(searchTimeout);
    const query = this.value.trim();
    
    if (query.length < 3) {
      hideSuggestions();
      return;
    }
    
    // Check if input looks like coordinates
    if (isCoordinateInput(query)) {
      hideSuggestions();
      return;
    }
    
    searchTimeout = setTimeout(() => {
      searchAddresses(query);
    }, 300);
  });
  
  // Enhanced search button handler
  searchBtn.addEventListener('click', function() {
    const query = searchInput.value.trim();
    if (query) {
      handleSearch(query);
    }
  });
  
  // Enhanced enter key support
  searchInput.addEventListener('keypress', function(e) {
    if (e.key === 'Enter') {
      const query = this.value.trim();
      if (query) {
        handleSearch(query);
      }
    }
  });
  
  // Hide suggestions when clicking outside
  document.addEventListener('click', function(e) {
    if (!e.target.closest('.search-container')) {
      hideSuggestions();
    }
  });
  
  function isCoordinateInput(input) {
    // Check for lat,lng format
    const coordPattern = /^-?\d+\.?\d*,\s*-?\d+\.?\d*$/;
    return coordPattern.test(input);
  }
  
  function handleSearch(query) {
    hideSuggestions();
    
    if (isCoordinateInput(query)) {
      // Handle coordinate input
      const [lat, lng] = query.split(',').map(s => parseFloat(s.trim()));
      if (!isNaN(lat) && !isNaN(lng)) {
        map.setView([lat, lng], 16);
        requestParcels(lng, lat);
      }
    } else {
      // Handle address search via LocationIQ
      geocodeAddress(query);
    }
  }
  
  async function searchAddresses(query) {
    if (!LOCATIONIQ_KEY) return;
    
    try {
      const response = await fetch(
        `https://us1.locationiq.com/v1/autocomplete?key=${LOCATIONIQ_KEY}&q=${encodeURIComponent(query)}&countrycodes=nz&limit=5&format=json&addressdetails=1`
      );
      
      if (response.ok) {
        const results = await response.json();
        showSuggestions(results);
      }
    } catch (error) {
      console.error('LocationIQ autocomplete error:', error);
    }
  }
  
  async function geocodeAddress(address) {
    if (!LOCATIONIQ_KEY) {
      setTopText("Address search requires LocationIQ API");
      return;
    }
    
    try {
      setTopText("Address: <strong>searching...</strong>");
      
      const response = await fetch(
        `https://us1.locationiq.com/v1/search?key=${LOCATIONIQ_KEY}&q=${encodeURIComponent(address)}&countrycodes=nz&limit=1&format=json&addressdetails=1`
      );
      
      if (response.ok) {
        const results = await response.json();
        if (results.length > 0) {
          const result = results[0];
          const lat = parseFloat(result.lat);
          const lng = parseFloat(result.lon);
          
          setTopText(`Address: <strong>${result.display_name.split(',')[0]}</strong>`);
          map.setView([lat, lng], 16);
          
          // Enhanced: Search for property boundaries at this address
          setTimeout(() => {
            requestParcels(lng, lat);
          }, 500);
        } else {
          setTopText("Address: <strong>not found in New Zealand</strong>");
        }
      } else {
        setTopText("Address: <strong>search failed</strong>");
      }
    } catch (error) {
      console.error('LocationIQ geocoding error:', error);
      setTopText("Address: <strong>search error</strong>");
    }
  }
  
  function showSuggestions(results) {
    if (!results || results.length === 0) {
      hideSuggestions();
      return;
    }
    
    suggestionsContainer.innerHTML = '';
    
    results.forEach(result => {
      const suggestion = document.createElement('div');
      suggestion.className = 'search-suggestion';
      suggestion.textContent = result.display_name;
      
      suggestion.addEventListener('click', function() {
        searchInput.value = result.display_name;
        hideSuggestions();
        
        const lat = parseFloat(result.lat);
        const lng = parseFloat(result.lon);
        map.setView([lat, lng], 16);
        requestParcels(lng, lat);
      });
      
      suggestionsContainer.appendChild(suggestion);
    });
    
    suggestionsContainer.style.display = 'block';
  }
  
  function hideSuggestions() {
    suggestionsContainer.style.display = 'none';
  }
}

// --- Enhanced Google Geolocation Integration for Parallel Tracking --------------
class GoogleGeolocationManager {
  constructor(apiKey) {
    this.apiKey = apiKey;
    this.isTracking = false;
    this.lastPosition = null;
    this.accuracy = null;
  }

  // Enhanced geolocation with WiFi/Cell tower assistance
  async getCurrentPosition() {
    if (!this.apiKey) {
      console.log('Google Geolocation: No API key, falling back to device GPS');
      return this.getDevicePosition();
    }

    try {
      console.log('Google Geolocation: Requesting enhanced position...');
      
      // First get a rough position for context
      const devicePos = await this.getDevicePosition();
      
      // Enhanced geolocation request with network assistance
      const response = await fetch(`https://www.googleapis.com/geolocation/v1/geolocate?key=${this.apiKey}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          considerIp: true,
          wifiAccessPoints: [],
          cellTowers: []
        })
      });

      if (response.ok) {
        const result = await response.json();
        const position = {
          latitude: result.location.lat,
          longitude: result.location.lng,
          accuracy: result.accuracy,
          timestamp: Date.now(),
          source: 'google-geolocation'
        };
        
        this.lastPosition = position;
        this.accuracy = result.accuracy;
        
        console.log(`Google Geolocation: Enhanced position (±${result.accuracy}m)`, position);
        return position;
      } else {
        console.log('Google Geolocation: API failed, using device GPS');
        return devicePos;
      }
    } catch (error) {
      console.error('Google Geolocation error:', error);
      return this.getDevicePosition();
    }
  }

  // Fallback to device GPS
  async getDevicePosition() {
    return new Promise((resolve, reject) => {
      if (!navigator.geolocation) {
        reject(new Error('Geolocation not supported'));
        return;
      }

      navigator.geolocation.getCurrentPosition(
        (position) => {
          const pos = {
            latitude: position.coords.latitude,
            longitude: position.coords.longitude,
            accuracy: position.coords.accuracy,
            timestamp: position.timestamp,
            source: 'device-gps'
          };
          resolve(pos);
        },
        (error) => reject(error),
        {
          enableHighAccuracy: true,
          timeout: 15000,
          maximumAge: 60000
        }
      );
    });
  }

  // Enhanced reverse geocoding with Google
  async reverseGeocode(lat, lng) {
    if (!this.apiKey) return null;

    try {
      const response = await fetch(
        `https://maps.googleapis.com/maps/api/geocode/json?latlng=${lat},${lng}&key=${this.apiKey}&result_type=street_address|premise`
      );

      if (response.ok) {
        const result = await response.json();
        if (result.results && result.results.length > 0) {
          const address = result.results[0];
          return {
            formattedAddress: address.formatted_address,
            streetNumber: this.extractComponent(address, 'street_number'),
            streetName: this.extractComponent(address, 'route'),
            suburb: this.extractComponent(address, 'sublocality_level_1'),
            city: this.extractComponent(address, 'locality'),
            region: this.extractComponent(address, 'administrative_area_level_1'),
            country: this.extractComponent(address, 'country'),
            source: 'google-geocoding'
          };
        }
      }
    } catch (error) {
      console.error('Google reverse geocoding error:', error);
    }
    
    return null;
  }

  extractComponent(address, type) {
    const component = address.address_components?.find(comp => 
      comp.types.includes(type)
    );
    return component?.long_name || '';
  }

  // Parallel tracking with multiple sources
  async startParallelTracking() {
    this.isTracking = true;
    
    // Get positions from multiple sources in parallel
    const promises = [
      this.getCurrentPosition(),
    ];

    if (LOCATIONIQ_KEY) {
      promises.push(this.getLocationIQPosition());
    }

    try {
      const positions = await Promise.allSettled(promises);
      const validPositions = positions
        .filter(p => p.status === 'fulfilled' && p.value)
        .map(p => p.value);

      if (validPositions.length > 0) {
        // Choose best position based on accuracy
        const bestPosition = this.selectBestPosition(validPositions);
        console.log('Parallel Geolocation: Best position selected:', bestPosition);
        return bestPosition;
      }
    } catch (error) {
      console.error('Parallel geolocation failed:', error);
    }

    return null;
  }

  async getLocationIQPosition() {
    // This would integrate with existing LocationIQ if we had a position service
    // For now, just return null as LocationIQ is mainly for geocoding
    return null;
  }

  selectBestPosition(positions) {
    // Prefer Google Geolocation for accuracy, then device GPS
    const googlePos = positions.find(p => p.source === 'google-geolocation');
    if (googlePos && googlePos.accuracy < 100) return googlePos;

    const devicePos = positions.find(p => p.source === 'device-gps');
    if (devicePos && devicePos.accuracy < 50) return devicePos;

    // Return the most accurate position available
    return positions.reduce((best, current) => 
      (current.accuracy < best.accuracy) ? current : best
    );
  }
}

// Enhanced property information with multiple geocoding sources
async function enhancePropertyWithAddress(lat, lng) {
  const results = [];
  
  // Try Google Geocoding first (usually most accurate)
  if (GOOGLE_KEY && googleGeoManager) {
    const googleResult = await googleGeoManager.reverseGeocode(lat, lng);
    if (googleResult) results.push(googleResult);
  }
  
  // Try LocationIQ as backup
  if (LOCATIONIQ_KEY) {
    try {
      const response = await fetch(
        `https://us1.locationiq.com/v1/reverse?key=${LOCATIONIQ_KEY}&lat=${lat}&lon=${lng}&format=json&addressdetails=1`
      );
      
      if (response.ok) {
        const result = await response.json();
        results.push({
          streetNumber: result.address?.house_number || '',
          streetName: result.address?.road || '',
          suburb: result.address?.suburb || result.address?.neighbourhood || '',
          city: result.address?.city || result.address?.town || '',
          fullAddress: result.display_name || '',
          source: 'locationiq'
        });
      }
    } catch (error) {
      console.error('LocationIQ reverse geocoding error:', error);
    }
  }
  
  // Return best result (prefer Google, fallback to LocationIQ)
  return results.find(r => r.source === 'google-geocoding') || results[0] || null;
}

// --- Enhanced Auto-Start System (Real GPS Location) ------------------------------
const qs = new URLSearchParams(location.search);
const initLat = parseFloat(qs.get("lat"));
const initLng = parseFloat(qs.get("lng"));
const initZ   = parseInt(qs.get("z") || "17", 10);

function initializeMap() {
  console.log('Initializing map...');
  
  // Check if Leaflet is loaded
  if (typeof L === 'undefined') {
    console.error('Leaflet library not loaded!');
    setTopText("Property: <strong>Map library loading error</strong>");
    return false;
  }
  
  // Initialize map
  try {
    map = L.map("map").setView([-41, 173], 6);
    window.map = map; // For backward compatibility
    
    baseLayers = {
      "OpenStreetMap": L.tileLayer(
        "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
        { maxZoom: 20, attribution: "© OpenStreetMap contributors" }
      ).addTo(map),
      "LINZ Topographic": LINZ_KEY ? L.tileLayer(
        `https://basemaps.linz.govt.nz/v1/tiles/topographic/{z}/{x}/{y}.png?api=${LINZ_KEY}`,
        { maxZoom: 18, attribution: "© LINZ CC BY 4.0" }
      ) : null,
      "Esri Satellite": L.tileLayer(
        "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}",
        { maxZoom: 20, attribution: "Tiles © Esri" }
      )
    };

    // Remove null LINZ layer if no API key
    if (!baseLayers["LINZ Topographic"]) {
      delete baseLayers["LINZ Topographic"];
    }

    // Enhanced controls
    L.control.layers(baseLayers, {}, { position: "topright" }).addTo(map);
    L.control.scale({ metric: true, imperial: false }).addTo(map);

    // Enhanced property boundary styling
    subjectProperty = L.geoJSON(null, { 
      style: { color: "#007AFF", weight: 3, fill: false, dashArray: "" },
      onEachFeature: function(feature, layer) {
        // Enhanced tooltips with property information
        const props = feature.properties || {};
        const appellation = getAppellation(props) || "Property";
        const area = calculateArea(feature);
        const areaText = area > 10000 ? `${(area/10000).toFixed(2)} ha` : `${Math.round(area)} m²`;
        
        layer.bindTooltip(`<strong>${appellation}</strong><br>Area: ${areaText}`, {
          permanent: false,
          direction: "top",
          className: "property-tooltip"
        });
      }
    }).addTo(map);

    neighborProperties = L.geoJSON(null, { 
      style: { color: "#ff3b30", weight: 2, fill: false, dashArray: "5, 5" },
      onEachFeature: function(feature, layer) {
        const props = feature.properties || {};
        const appellation = getAppellation(props) || "Neighbor Property";
        layer.bindTooltip(`<strong>${appellation}</strong><br><em>Neighbor</em>`, {
          permanent: false,
          direction: "top", 
          className: "neighbor-tooltip"
        });
      }
    });
    
    // Enhanced map interactions
    map.on("click", (e) => {
      if (alignmentMode) {
        addAlignmentPoint(e.latlng);
      } else {
        requestParcels(e.latlng.lng, e.latlng.lat, SEARCH_RADIUS_M);
      }
    });
    
    console.log('Map initialized successfully');
    return true;
  } catch (error) {
    console.error('Map initialization failed:', error);
    setTopText("Property: <strong>Map initialization failed</strong>");
    return false;
  }
}

function autoStart() {
  console.log('Auto start triggered');
  
  // Create UI controls first
  createFloatingControls();
  
  // Initialize map
  if (!initializeMap()) {
    return; // Exit if map initialization failed
  }
  
  // Initialize LINZ integration after DOM and scripts are loaded
  console.log('Checking CoordinateProcessor availability:', typeof CoordinateProcessor);
  if (typeof CoordinateProcessor !== 'undefined') {
    const linzInitialized = initializeLINZIntegration();
    if (!linzInitialized) {
      return; // Don't proceed with automatic location if LINZ not available
    }
  } else {
    console.error('CoordinateProcessor not available - check script loading order');
    setTopText("Error: <strong>Failed to load coordinate processor</strong>");
    return;
  }
  
  // Initialize Google Geolocation Manager for parallel tracking
  googleGeoManager = new GoogleGeolocationManager(GOOGLE_KEY);
  console.log('Google Geolocation Manager initialized:', !!googleGeoManager);
  
  // Wire up button event handlers after map is ready
  exportBtn.addEventListener("click", exportKML);
  satelliteBtn.addEventListener("click", toggleMapLayers);
  neighborsBtn.addEventListener("click", toggleNeighbors);
  document.getElementById('ar-alignment').addEventListener("click", toggleARAlignment);
  document.getElementById('ar-btn').addEventListener("click", openARView);
  
  // Enhanced search functionality with LocationIQ
  setupLocationIQSearch();
  
  if (!Number.isNaN(initLat) && !Number.isNaN(initLng)) {
    map.setView([initLat, initLng], initZ);
    requestParcels(initLng, initLat, SEARCH_RADIUS_M);
    return;
  }
  
  // Enhanced automatic location detection
  getUserLocationAutomatically();
}

// --- Enhanced Automatic Location Detection ---------------------------------------
function getUserLocationAutomatically() {
  setTopText("Property: <strong>finding your location…</strong>");
  
  // Enhanced geolocation options for better accuracy
  const options = {
    enableHighAccuracy: true,
    timeout: 15000,  // 15 seconds timeout
    maximumAge: 60000 // Accept cached location up to 1 minute old
  };
  
  // Try enhanced Google geolocation first, then fallback to HTML5
  if (googleGeoManager && typeof googleGeoManager.getCurrentPosition === 'function') {
    console.log('Using enhanced Google geolocation for automatic location');
    googleGeoManager.getCurrentPosition()
      .then(position => {
        console.log('Enhanced location found:', position.coords.latitude, position.coords.longitude);
        handleAutomaticLocation(position.coords.latitude, position.coords.longitude);
      })
      .catch(error => {
        console.log('Enhanced geolocation failed, trying HTML5:', error);
        tryHTML5Geolocation(options);
      });
  } else {
    console.log('Using HTML5 geolocation for automatic location');
    tryHTML5Geolocation(options);
  }
}

function tryHTML5Geolocation(options) {
  if (!navigator.geolocation) {
    console.log('Geolocation not supported by browser');
    setTopText("Property: <strong>Location not available - click on map to find property</strong>");
    map.setView([-41.0, 174.0], 6);
    return;
  }
  
  navigator.geolocation.getCurrentPosition(
    (position) => {
      console.log('HTML5 location found:', position.coords.latitude, position.coords.longitude);
      handleAutomaticLocation(position.coords.latitude, position.coords.longitude);
    },
    (error) => {
      console.log('HTML5 geolocation error:', error.message);
      handleLocationError(error);
    },
    options
  );
}

function handleAutomaticLocation(latitude, longitude) {
  console.log(`Automatically loading property boundaries for: ${latitude}, ${longitude}`);
  
  // Center map on user's location with detailed zoom
  map.setView([latitude, longitude], 18);
  
  // Add a marker to show user's current location
  const userMarker = L.marker([latitude, longitude], {
    icon: L.divIcon({
      className: 'user-location-marker',
      html: '<div style="background: #007AFF; color: white; border-radius: 50%; width: 20px; height: 20px; display: flex; align-items: center; justify-content: center; font-size: 12px;">📍</div>',
      iconSize: [20, 20],
      iconAnchor: [10, 10]
    })
  }).addTo(map);
  
  // Add a tooltip to the user location marker
  userMarker.bindTooltip("Your Location", {
    permanent: false,
    direction: "top",
    className: "user-location-tooltip"
  });
  
  // Automatically load property boundaries for this location
  requestParcels(longitude, latitude, SEARCH_RADIUS_M);
}

function handleLocationError(error) {
  let errorMessage;
  switch(error.code) {
    case error.PERMISSION_DENIED:
      errorMessage = "Location access denied - click on map to find property";
      break;
    case error.POSITION_UNAVAILABLE:
      errorMessage = "Location unavailable - click on map to find property";
      break;
    case error.TIMEOUT:
      errorMessage = "Location timeout - click on map to find property";
      break;
    default:
      errorMessage = "Location error - click on map to find property";
      break;
  }
  
  console.log('Location error:', errorMessage);
  setTopText(`Property: <strong>${errorMessage}</strong>`);
  
  // Default to New Zealand view when location fails
  map.setView([-41.0, 174.0], 6);
}

// --- Enhanced Event Handlers -----------------------------------------------------
// Note: Button event handlers will be wired up after map initialization

// Native bridge for iOS integration
window.renderParcelsFromBase64 = function (b64) {
  try {
    const json = JSON.parse(atob(b64));
    renderAndCenter(json);
  } catch (e) {
    console.error(e);
    setTopText("Property: <strong>parse failed</strong>");
  }
};

// Receive address from iOS reverse geocoding bridge
window.receiveAddress = function (address) {
  if (address && subjectFeature) {
    const app = getAppellation(subjectFeature.properties);
    const displayText = app ? `${app}` : "Property Found";
    setTopText(`<strong>${displayText}</strong><br><small>${address}</small>`);
  }
};

// Start the enhanced app
window.addEventListener("load", autoStart);