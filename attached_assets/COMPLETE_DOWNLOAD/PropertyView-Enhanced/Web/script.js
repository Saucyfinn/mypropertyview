/* global L */
(() => {
  // --- Basic UI helpers
  const status = (msg) => {
    const el = document.getElementById('status');
    if (el) { el.textContent = msg || ''; el.style.display = msg ? 'block' : 'none'; }
  };

  // --- Map & layers
  const map = L.map('map', {
    zoomControl: true,
    attributionControl: true
  });

  // Satellite first (ESRI World Imagery), fallback to OSM if imagery not available
  const esriSat = L.tileLayer(
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    { maxZoom: 19, crossOrigin: true }
  );
  const osm = L.tileLayer(
    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
    { maxZoom: 19 }
  );

  let usingSat = true;
  esriSat.addTo(map);
  esriSat.on('tileerror', () => {
    if (usingSat) {
      usingSat = false;
      banner('Satellite not available here. Switching to map.');
      osm.addTo(map);
      map.removeLayer(esriSat);
    }
  });

  function banner(msg) {
    const el = document.getElementById('banner');
    if (!el) return;
    el.textContent = msg;
    el.style.display = 'block';
    setTimeout(() => (el.style.display = 'none'), 3500);
  }

  // Controls
  const layerCtl = L.control.layers(
    { 'Satellite': esriSat, 'Map': osm },
    {},
    { position: 'topright', collapsed: false }
  ).addTo(map);

  // --- Styles (VERY translucent)
  const SUBJECT_STYLE = { color: '#16a3b8', weight: 2, fillColor: '#16a3b8', fillOpacity: 0.02 };
  const NEIGH_STYLE   = { color: '#999999', weight: 1, fillColor: '#999999', fillOpacity: 0.015 };

  // --- State
  let subjectLayer = null;
  let neighboursGroup = L.layerGroup().addTo(map);
  let neighboursOn = false;
  let subjectRingsLonLat = null; // [[ [lon,lat], ... ], [hole...], ...]

  // --- Buttons
  document.getElementById('btnNeighbours').addEventListener('click', () => {
    neighboursOn = !neighboursOn;
    if (neighboursOn) { map.addLayer(neighboursGroup); } else { map.removeLayer(neighboursGroup); }
    document.getElementById('btnNeighbours').classList.toggle('active', neighboursOn);
  });

  document.getElementById('btnEarth').addEventListener('click', () => {
    if (!subjectRingsLonLat) {
      banner('No parcel loaded yet.');
      return;
    }
    const kml = buildKML(subjectRingsLonLat);
    // Prefer native share via iOS bridge
    if (window.webkit?.messageHandlers?.['ios.exportKML']) {
      window.webkit.messageHandlers['ios.exportKML'].postMessage({ kml, filename: 'parcel.kml' });
    } else {
      // Browser fallback: download blob
      const blob = new Blob([kml], { type: 'application/vnd.google-earth.kml+xml' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url; a.download = 'parcel.kml'; a.click();
      URL.revokeObjectURL(url);
    }
  });

  // --- Location bootstrap
  function requestLocation() {
    if (window.webkit?.messageHandlers?.['ios.requestLocation']) {
      status('Requesting device location…');
      window.webkit.messageHandlers['ios.requestLocation'].postMessage(null);
      return;
    }
    if ('geolocation' in navigator) {
      status('Getting browser location…');
      navigator.geolocation.getCurrentPosition(
        p => onLocation(p.coords.latitude, p.coords.longitude),
        e => onLocationError(e.message),
        { enableHighAccuracy: true, timeout: 7000 }
      );
      return;
    }
    status('No location available');
  }

  // JS handlers called by iOS
  window.__iosProvideLocation = (lat, lon) => onLocation(lat, lon);
  window.__iosLocationError = (msg) => onLocationError(msg);

  function onLocationError(msg) {
    console.warn('Location error:', msg);
    status('Location error. Showing default area.');
    const lat = -41.288889, lon = 174.777222; // Wellington CBD fallback
    map.setView([lat, lon], 16);
    fetchParcels(lat, lon);
  }

  async function onLocation(lat, lon) {
    status('Locating your property…');
    // Nice fly-in
    map.setView([lat, lon], 14, { animate: false });
    setTimeout(() => map.flyTo([lat, lon], 18, { duration: 1.0 }), 300);
    await fetchParcels(lat, lon);
    status('');
  }

  // --- LINZ fetch (WFS)
  async function fetchParcels(lat, lon) {
    const m = 200; // search radius
    const dLat = m / 110540.0;
    const dLon = m / (111320.0 * Math.cos(lat * Math.PI / 180));
    const bbox = `${lon - dLon},${lat - dLat},${lon + dLon},${lat + dLat},CRS:84`;

    const url = `https://data.linz.govt.nz/services;key=${window.LINZ_API_KEY}/wfs?` +
      new URLSearchParams({
        service: 'WFS',
        version: '2.0.0',
        request: 'GetFeature',
        typeNames: 'layer-50823',
        srsName: 'CRS:84',
        outputFormat: 'application/json',
        bbox
      }).toString();

    let fc;
    try {
      const r = await fetch(url);
      if (!r.ok) throw new Error('WFS bad response');
      fc = await r.json();
    } catch (e) {
      status('Could not load parcels.');
      console.error(e);
      return;
    }

    // GeoJSON → arrays; choose subject by point-in-polygon
    const polys = [];
    (fc.features || []).forEach(f => {
      if (f?.geometry?.type === 'MultiPolygon' && Array.isArray(f.geometry.coordinates)) {
        f.geometry.coordinates.forEach(polygon => {
          const rings = polygon.map(ring => ring.map(([x, y]) => [x, y]));
          polys.push(rings);
        });
      }
    });

    // Clear old layers
    if (subjectLayer) { map.removeLayer(subjectLayer); subjectLayer = null; }
    neighboursGroup.clearLayers();
    subjectRingsLonLat = null;

    if (!polys.length) return;

    const pt = [lon, lat];
    let subject = polys.find(rings => pointInPolygon(pt, rings[0]));
    if (!subject) {
      // pick nearest centroid
      subject = polys.slice().sort((a, b) => {
        const ca = centroid(ringsToOuter(a));
        const cb = centroid(ringsToOuter(b));
        return dist2(pt, ca) - dist2(pt, cb);
      })[0];
    }
    subjectRingsLonLat = subject;

    // Add subject polygon
    subjectLayer = L.polygon(subject.map(r => r.map(([x, y]) => [y, x])), SUBJECT_STYLE).addTo(map);
    // Fit bounds once
    map.flyToBounds(subjectLayer.getBounds(), { padding: [60, 60], duration: 1.0 });

    // Neighbours (off by default; toggle with button)
    polys.forEach(rings => {
      if (rings === subject) return;
      const pg = L.polygon(rings.map(r => r.map(([x, y]) => [y, x])), NEIGH_STYLE);
      neighboursGroup.addLayer(pg);
    });
  }

  // --- Geometry helpers
  function ringsToOuter(rings) { return rings[0] || []; }
  function centroid(ring) {
    if (!ring.length) return [0, 0];
    let sx = 0, sy = 0;
    ring.forEach(([x, y]) => { sx += x; sy += y; });
    return [sx / ring.length, sy / ring.length];
  }
  function dist2(a, b) { const dx = a[0] - b[0], dy = a[1] - b[1]; return dx*dx + dy*dy; }
  function pointInPolygon(pt, poly) {
    // pt=[x,y] lon/lat; poly=[ [x,y], ... ]
    let inside = false; let j = poly.length - 1;
    for (let i = 0; i < poly.length; i++) {
      const xi = poly[i][0], yi = poly[i][1];
      const xj = poly[j][0], yj = poly[j][1];
      const intersect = ((yi > pt[1]) !== (yj > pt[1])) &&
        (pt[0] < (xj - xi) * (pt[1] - yi) / ((yj - yi) || 1e-12) + xi);
      if (intersect) inside = !inside;
      j = i;
    }
    return inside;
  }

  // --- KML builder (subject only)
  function buildKML(rings) {
    const coords = (ring) => ring.map(([x, y]) => `${x},${y},0`).join(' ');
    let inner = '';
    if (rings.length > 1) {
      for (let i = 1; i < rings.length; i++) {
        inner += `
        <innerBoundaryIs>
          <LinearRing>
            <coordinates>${coords(rings[i])}</coordinates>
          </LinearRing>
        </innerBoundaryIs>`;
      }
    }
    return `<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>Subject Parcel</name>
    <Placemark>
      <name>Parcel</name>
      <Style>
        <LineStyle><color>ff666666</color><width>2</width></LineStyle>
        <PolyStyle><color>2200ffff</color></PolyStyle>
      </Style>
      <Polygon>
        <outerBoundaryIs>
          <LinearRing>
            <coordinates>${coords(rings[0])}</coordinates>
          </LinearRing>
        </outerBoundaryIs>
        ${inner}
      </Polygon>
    </Placemark>
  </Document>
</kml>`;
  }

  // Kick off
  requestLocation();
})();
