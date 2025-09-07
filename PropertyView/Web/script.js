// --- Config -----------------------------------------------------------------
const LINZ_KEY = "";                  // leave empty in-app; set only for Safari testing
const SEARCH_RADIUS_M = 80;
const FIT_PADDING_PX = 24;            // padding around subject bounds
const FIT_MAX_ZOOM = 18;              // cap zoom when fitting


// --- Map setup --------------------------------------------------------------
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

// Layers control first so our panel sits directly under it
L.control.layers(baseLayers, {}, { position: "topright" }).addTo(map);
L.control.scale({ metric: true, imperial: false }).addTo(map);

// Boundaries (no fill)
const parcels = L.geoJSON(null, { style: { color: "#ff3b30", weight: 2, fill: false } }).addTo(map);

// --- Custom control (topright, under Layers) --------------------------------

const AppPanel = L.Control.extend({
  onAdd: function () {
    const div = L.DomUtil.create('div', 'leaflet-control pv-panel');

    // Export KML button
    const btnX = L.DomUtil.create('button', '', div);
    btnX.id = 'pv-export';
    btnX.textContent = 'Export KML';
    btnX.disabled = true;

    // AR Alignment button
    const btnAR = L.DomUtil.create('button', '', div);
    btnAR.id = 'ar-alignment';
    btnAR.textContent = 'Set AR Points';
    btnAR.style.display = 'none';
    btnAR.disabled = true;

    // Appellation readout
    const status = L.DomUtil.create('div', 'pv-status', div);
    status.id = 'pv-status';
    status.innerHTML = 'Appellation: <strong>—</strong>';

    L.DomEvent.disableClickPropagation(div);
    this._exportBtn = btnX;
    this._arBtn = btnAR;
    this._statusDiv = status;
    return div;
  }
});
const panel = new AppPanel({ position: 'topright' }).addTo(map);
const exportBtn = panel._exportBtn;
const statusDiv = panel._statusDiv;

// --- Subject feature + marker ----------------------------------------------
let subjectPin = null;
let subjectFeature = null;         // chosen subject GeoJSON feature
let currentQueryLatLng = null;     // query origin (used to choose subject)
let subjectCenterLatLng = null;    // center of subject bounds

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
function setTopText(html) { statusDiv.innerHTML = html; }
function getAppellation(props) {
  return (props && (props.appellation ?? props.Appellation ?? props.APP ?? props.name)) || null;
}

// --- Helpers ----------------------------------------------------------------
function bboxAround(lon, lat, r) {
  const dLat = r / 111320;
  const dLon = r / (111320 * Math.cos(lat * Math.PI / 180));
  return { minLon: lon - dLon, minLat: lat - dLat, maxLon: lon + dLon, maxLat: lat + dLat };
}
function pickZoningValue(props, fallbacks = ZONING_WFS.propertyKeys) {
  if (!props) return null;
  for (const k of fallbacks) {
    if (k in props && props[k] != null && String(props[k]).trim() !== "") return String(props[k]);
  }
  for (const key of Object.keys(props)) {
    if (/zone/i.test(key) && String(props[key]).trim() !== "") return String(props[key]);
  }
  return null;
}
function chooseZoneFeature(gj, pt) {
  if (!gj?.features?.length) return null;
  const candidates = [];
  for (const f of gj.features) {
    if (!f.geometry) continue;
    try {
      if (turf.booleanPointInPolygon(pt, f)) {
        const area = turf.area(f); // m^2
        candidates.push({ f, area });
      }
    } catch { /* ignore invalid geom */ }
  }
  if (!candidates.length) return null;
  candidates.sort((a, b) => a.area - b.area);
  return candidates[0].f;
}

// --- Zoning fetch -----------------------------------------------------------
async function fetchZoningForSubject(centerLatLng) {
  if (!centerLatLng) return;
  if (!ZONING_WFS.url || !ZONING_WFS.typeName) {
    setZoneText('Zoning: <strong>—</strong>');
    return;
  }
  try {
    setZoneText('Zoning: <strong>looking up…</strong>');
    const lon = centerLatLng.lng, lat = centerLatLng.lat;
    const { minLon, minLat, maxLon, maxLat } = bboxAround(lon, lat, ZONING_WFS.searchRadiusM);
    const url = new URL(ZONING_WFS.url);
    url.search = new URLSearchParams({
      service: "WFS",
      version: "2.0.0",
      request: "GetFeature",
      typeNames: ZONING_WFS.typeName,
      outputFormat: "application/json",
      srsName: ZONING_WFS.srsName,
      bbox: `${minLon},${minLat},${maxLon},${maxLat},EPSG:4326`,
      count: "50"
    }).toString();

    const res = await fetch(url);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const gj = await res.json();

    const pt = turf.point([lon, lat]);
    const zoneFeature = chooseZoneFeature(gj, pt);
    if (!zoneFeature) {
      setZoneText('Zoning: <strong>Unknown</strong>');
      return;
    }
    const zoneName = pickZoningValue(zoneFeature.properties) || "Unknown";
    setZoneText(`Zoning: <strong>${zoneName}</strong>`);
  } catch (e) {
    console.error("Zoning fetch failed:", e);
    setZoneText('Zoning: <strong>Unavailable</strong>');
  }
}

// --- Render returned parcels & choose subject --------------------------------
function renderAndCenter(gj) {
  parcels.clearLayers().addData(gj);
  const layers = parcels.getLayers();
  if (!layers.length) {
    subjectFeature = null;
    subjectCenterLatLng = null;
    setTopText("Appellation: <strong>—</strong>");
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
  setTopText(app ? `Appellation: <strong>${app}</strong>` : "Appellation: <strong>Unknown</strong>");

  updateSubjectPin(center);
  map.fitBounds(subjectBounds, { padding: [FIT_PADDING_PX, FIT_PADDING_PX], maxZoom: FIT_MAX_ZOOM });

  // Save coordinates for AR
  saveCoordinatesForAR(subjectFeature, center, app);

  // Show AR alignment button
  const arBtn = document.getElementById('ar-alignment');
  if (arBtn) {
    arBtn.style.display = 'block';
    arBtn.disabled = false;
  }

  exportBtn.disabled = false;
}

// --- Native bridge (Swift) -> JS -------------------------------------------
window.renderParcelsFromBase64 = function (b64) {
  try {
    const json = JSON.parse(atob(b64));
    renderAndCenter(json);
  } catch (e) {
    console.error(e);
    setTopText("Appellation: <strong>parse failed</strong>");
  }
};

// --- Request parcels (JS -> Swift, with browser fallback) -------------------
async function requestParcels(lon, lat, r = SEARCH_RADIUS_M) {
  currentQueryLatLng = L.latLng(lat, lon);
  setTopText("Appellation: <strong>finding…</strong>");

  if (window.webkit?.messageHandlers?.getParcels) {
    window.webkit.messageHandlers.getParcels.postMessage({ lon, lat, radius: r });
    return;
  }

  if (LINZ_KEY) {
    try {
      const { minLon, minLat, maxLon, maxLat } = bboxAround(lon, lat, r);
      const url = new URL(`https://data.linz.govt.nz/services;key=${LINZ_KEY}/wfs`);
      url.search = new URLSearchParams({
        service: "WFS",
        version: "2.0.0",
        request: "GetFeature",
        typeNames: "layer-50823",
        outputFormat: "application/json",
        srsName: "EPSG:4326",
        bbox: `${minLon},${minLat},${maxLon},${maxLat},EPSG:4326`,
        count: "100"
      }).toString();
      const res = await fetch(url);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const gj = await res.json();
      renderAndCenter(gj);
    } catch (e) {
      console.error(e);
      setTopText("Appellation: <strong>fetch failed</strong>");
    }
    return;
  }

  setTopText("Appellation: <strong>—</strong>");
}

// --- KML export (subject feature only) --------------------------------------
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
  return `<Placemark><name>${app}</name>${body}</Placemark>`;
}
function buildSubjectKml() {
  if (!subjectFeature) return null;
  const pm = featureToKmlPlacemark(subjectFeature);
  if (!pm) return null;
  return `<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2"><Document>${pm}</Document></kml>`;
}
function exportKML() {
  const kml = buildSubjectKml();
  if (!kml) { setTopText("Appellation: <strong>No subject to export</strong>"); return; }

  // Preferred: native iOS share (Google Earth, Files, etc.)
  if (window.webkit?.messageHandlers?.exportKML) {
    const b64 = btoa(unescape(encodeURIComponent(kml))); // UTF-8 → base64
    window.webkit.messageHandlers.exportKML.postMessage({ filename: "parcel.kml", base64: b64 });
    return;
  }

  // Browser fallback: download
  const blob = new Blob([kml], { type: "application/vnd.google-earth.kml+xml" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url; a.download = "parcel.kml";
  document.body.appendChild(a); a.click();
  setTimeout(() => { URL.revokeObjectURL(url); a.remove(); }, 0);
  setTopText("Appellation: <strong>—</strong>");
}

// --- Save coordinates for AR ------------------------------------------------
function saveCoordinatesForAR(feature, center, appellation) {
  if (!feature?.geometry?.coordinates) return;
  
  const coordinates = [];
  const geom = feature.geometry;
  
  // Extract coordinates based on geometry type
  if (geom.type === "Polygon" && geom.coordinates[0]) {
    // Get outer ring coordinates
    coordinates.push(...geom.coordinates[0].map(coord => ({
      latitude: coord[1],
      longitude: coord[0]
    })));
  } else if (geom.type === "MultiPolygon" && geom.coordinates[0]?.[0]) {
    // Get first polygon's outer ring
    coordinates.push(...geom.coordinates[0][0].map(coord => ({
      latitude: coord[1], 
      longitude: coord[0]
    })));
  }
  
  const coordinateData = {
    subject_property: {
      coordinates: coordinates,
      appellation: appellation || "Unknown",
      center: {
        latitude: center.lat,
        longitude: center.lng
      },
      timestamp: new Date().toISOString()
    },
    neighboring_properties: []
  };
  
  // Send to iOS app if available
  if (window.webkit?.messageHandlers?.saveCoordinates) {
    window.webkit.messageHandlers.saveCoordinates.postMessage(coordinateData);
  }
  
  console.log("Coordinates saved for AR:", coordinateData);
}

// AR Alignment functions
function toggleARAlignment() {
  if (!subjectFeature) {
    alert('Please select a property first by clicking on the map.');
    return;
  }
  
  alignmentMode = !alignmentMode;
  const alignBtn = document.getElementById('ar-alignment');
  
  if (alignmentMode) {
    // Start alignment mode
    alignmentPoints = [];
    clearAlignmentMarkers();
    addCornerSelectionPins();
    alignBtn.textContent = 'Cancel AR Points';
    alignBtn.classList.add('active');
    setTopText('AR Alignment: <strong>Click 2 property corners</strong>');
  } else {
    // Cancel alignment mode
    clearAlignmentMarkers();
    clearCornerSelectionPins();
    alignBtn.textContent = 'Set AR Points';
    alignBtn.classList.remove('active');
    const app = getAppellation(subjectFeature?.properties);
    setTopText(app ? `Property: <strong>${app}</strong>` : "Property: <strong>Found</strong>");
  }
}

function addCornerSelectionPins() {
  if (!subjectFeature?.geometry) return;
  
  // Get property boundary coordinates
  let coordinates = [];
  if (subjectFeature.geometry.type === 'Polygon') {
    coordinates = subjectFeature.geometry.coordinates[0];
  } else if (subjectFeature.geometry.type === 'MultiPolygon') {
    coordinates = subjectFeature.geometry.coordinates[0][0];
  }
  
  // Only add 2 pins at strategic corners (first and middle point)
  if (coordinates.length >= 2) {
    const cornerIndices = [0, Math.floor(coordinates.length / 2)];
    
    cornerIndices.forEach((index, pinNumber) => {
      const coord = coordinates[index];
      const pin = L.marker([coord[1], coord[0]], {
        icon: L.divIcon({
          className: 'corner-selection-pin',
          html: `<div class="pin-content">
                   <div class="pin-icon">📍</div>
                   <div class="pin-label">Select Corner ${pinNumber + 1}</div>
                 </div>`,
          iconSize: [120, 60],
          iconAnchor: [60, 50]
        })
      }).addTo(map);
      
      cornerSelectionPins.push(pin);
    });
  }
}

function clearCornerSelectionPins() {
  cornerSelectionPins.forEach(pin => map.removeLayer(pin));
  cornerSelectionPins = [];
}

function clearAlignmentMarkers() {
  alignmentMarkers.forEach(marker => map.removeLayer(marker));
  alignmentMarkers = [];
}

function handleMapClick(e) {
  if (alignmentMode && alignmentPoints.length < 2) {
    // Add alignment point
    alignmentPoints.push({
      latitude: e.latlng.lat,
      longitude: e.latlng.lng
    });
    
    // Add visual marker with different colors for each point
    const markerColor = alignmentPoints.length === 1 ? 'red' : 'blue';
    const marker = L.circleMarker(e.latlng, {
      radius: 10,
      fillColor: markerColor,
      color: 'white',
      weight: 3,
      opacity: 1,
      fillOpacity: 0.9
    }).addTo(map);
    
    // Add number label to marker
    marker.bindTooltip(`Point ${alignmentPoints.length}`, {
      permanent: true,
      direction: 'top',
      className: 'alignment-tooltip'
    });
    
    alignmentMarkers.push(marker);
    
    console.log(`AR Alignment: Added point ${alignmentPoints.length}`, alignmentPoints[alignmentPoints.length - 1]);
    
    if (alignmentPoints.length === 1) {
      setTopText('AR Alignment: <strong>Click second property corner</strong>');
    } else if (alignmentPoints.length === 2) {
      // Save alignment points
      saveAlignmentPoints();
      setTopText('AR Alignment: <strong>2 points saved! Ready for AR</strong>');
      // Don't exit alignment mode immediately - let user manually exit
      const alignBtn = document.getElementById('ar-alignment');
      alignBtn.textContent = 'Points Set - Go to AR';
      alignBtn.classList.add('completed');
    }
    return;
  }
  
  // Normal property selection
  requestParcels(e.latlng.lng, e.latlng.lat, SEARCH_RADIUS_M);
}

function saveAlignmentPoints() {
  if (alignmentPoints.length !== 2) return;
  
  const alignmentData = {
    points: alignmentPoints,
    property: extractCoordinatesFromFeature(subjectFeature),
    timestamp: new Date().toISOString()
  };
  
  // Send to iOS app
  if (window.webkit?.messageHandlers?.saveAlignmentPoints) {
    window.webkit.messageHandlers.saveAlignmentPoints.postMessage(alignmentData);
  }
  
  // Also save to localStorage as backup
  if (typeof(Storage) !== "undefined") {
    localStorage.setItem('arAlignmentPoints', JSON.stringify(alignmentData));
    console.log('AR alignment points saved:', alignmentData);
  }
  
  setTopText('AR Alignment: <strong>Points saved for AR</strong>');
}

function extractCoordinatesFromFeature(feature) {
  if (!feature?.geometry) return [];
  
  if (feature.geometry.type === 'Polygon') {
    return feature.geometry.coordinates[0].map(coord => ({
      latitude: coord[1],
      longitude: coord[0]
    }));
  } else if (feature.geometry.type === 'MultiPolygon') {
    // Use the largest polygon
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

// Wire up the buttons
exportBtn.addEventListener("click", exportKML);
panel._arBtn.addEventListener("click", toggleARAlignment);

// --- Interactions -----------------------------------------------------------
map.on("click", handleMapClick);

// --- Auto-start on load -----------------------------------------------------
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
    navigator.geolocation.getCurrentPosition(p => {
      const { latitude: lat, longitude: lon } = p.coords;
      map.setView([lat, lon], 17);
      requestParcels(lon, lat, SEARCH_RADIUS_M);
    }, _ => { /* user denied; wait for tap */ }, { enableHighAccuracy: true, timeout: 15000 });
  }
}
window.addEventListener("load", autoStart);
