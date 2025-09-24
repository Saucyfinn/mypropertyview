// --- Enhanced PropertyView Configuration ----------------------------------------
const LINZ_KEY = window.LINZ_API_KEY || ""; // Will be set by environment or prompt user
const SEARCH_RADIUS_M = 150;                    // Enhanced search radius

// Initialize coordinate processor for AR support
let coordinateProcessor = null;

// Check for LINZ API key and initialize or prompt user
function initializeLINZIntegration() {
    const storedKey = localStorage.getItem('linz_api_key');
    const envKey = window.LINZ_API_KEY;
    const urlKey = new URLSearchParams(window.location.search).get('linz_key');
    
    const apiKey = envKey || urlKey || storedKey;
    
    if (apiKey) {
        coordinateProcessor = new CoordinateProcessor(apiKey);
        if (urlKey && urlKey !== storedKey) {
            localStorage.setItem('linz_api_key', urlKey);
        }
        console.log('LINZ integration initialized successfully');
        return true;
    } else {
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
        setTopText("Property: <strong>LINZ API key saved! Click on map to find your property.</strong>");
        return true;
    } else {
        setTopText("Property: <strong>LINZ API key required for property boundary data</strong>");
        return false;
    }
}

// Initialize LINZ integration on load
initializeLINZIntegration();

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

// --- Enhanced Map Setup --------------------------------------------------------------
window.map = L.map("map").setView([-41, 173], 6);
const map = window.map;

const baseLayers = {
  "OpenStreetMap": L.tileLayer(
    "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
    { maxZoom: 20, attribution: "© OpenStreetMap contributors" }
  ).addTo(map),
  "Esri Satellite": L.tileLayer(
    "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}",
    { maxZoom: 20, attribution: "Tiles © Esri" }
  )
};

// Enhanced controls
L.control.layers(baseLayers, {}, { position: "topright" }).addTo(map);
L.control.scale({ metric: true, imperial: false }).addTo(map);

// Enhanced property boundary styling
const subjectProperty = L.geoJSON(null, { 
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

const neighborProperties = L.geoJSON(null, { 
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

  // Satellite toggle button
  const satelliteButton = document.createElement('button');
  satelliteButton.className = 'floating-btn';
  satelliteButton.id = 'satellite-toggle';
  satelliteButton.textContent = 'Satellite';
  satelliteButton.style.top = '80px';
  document.body.appendChild(satelliteButton);
  satelliteBtn = satelliteButton;

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

createFloatingControls();

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
function toggleSatellite() {
  if (currentSatelliteLayer) {
    map.removeLayer(currentSatelliteLayer);
    currentSatelliteLayer = null;
    satelliteBtn.classList.remove('active');
  } else {
    currentSatelliteLayer = baseLayers["Esri Satellite"];
    map.addLayer(currentSatelliteLayer);
    satelliteBtn.classList.add('active');
  }
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
        console.log('AR coordinates prepared:', arCoords.subjectProperty.arPoints.length, 'points for subject property');
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

// --- Enhanced Auto-Start System (Real GPS Location) ------------------------------
const qs = new URLSearchParams(location.search);
const initLat = parseFloat(qs.get("lat"));
const initLng = parseFloat(qs.get("lng"));
const initZ   = parseInt(qs.get("z") || "17", 10);

function autoStart() {
  if (!Number.isNaN(initLat) && !Number.isNaN(initLng)) {
    map.setView([initLat, initLng], initZ);
    requestParcels(initLng, initLat, SEARCH_RADIUS_M);
    return;
  }
  
  if (navigator.geolocation) {
    setTopText("Property: <strong>Getting your location…</strong>");
    navigator.geolocation.getCurrentPosition(p => {
      const { latitude: lat, longitude: lon } = p.coords;
      map.setView([lat, lon], 15);
      requestParcels(lon, lat, SEARCH_RADIUS_M);
    }, error => { 
      console.log("Geolocation failed:", error);
      setTopText("Property: <strong>Click on map to find your property</strong>");
      map.setView([-41.0, 174.0], 6);
    }, { enableHighAccuracy: true, timeout: 10000 });
  } else {
    setTopText("Property: <strong>Click on map to find your property</strong>");
    map.setView([-41.0, 174.0], 6);
  }
}

// --- Enhanced Event Handlers -----------------------------------------------------
// Wire up all buttons
exportBtn.addEventListener("click", exportKML);
satelliteBtn.addEventListener("click", toggleSatellite);
neighborsBtn.addEventListener("click", toggleNeighbors);
document.getElementById('ar-alignment').addEventListener("click", toggleARAlignment);
document.getElementById('ar-btn').addEventListener("click", openARView);

// Enhanced map interactions
map.on("click", (e) => {
  if (alignmentMode) {
    addAlignmentPoint(e.latlng);
  } else {
    requestParcels(e.latlng.lng, e.latlng.lat, SEARCH_RADIUS_M);
  }
});

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