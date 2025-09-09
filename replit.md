# Overview

Propertyview is a web-based property mapping application that displays property boundaries and zoning information on an interactive map. The project consists of a JavaScript web application built with Leaflet.js for mapping functionality, designed to integrate with LINZ (Land Information New Zealand) data services for property boundary retrieval and optional WFS services for district plan zoning information.

The application provides features for viewing property parcels, displaying neighboring properties with toggle controls, accessing satellite imagery with toggle functionality, and exporting data in KML format. It includes an AR viewing button for augmented reality property boundary visualization. The project is structured as a hybrid project that includes both a standalone web application and an iOS mobile app wrapper.

# Recent Changes

**September 2025 - Application Fixes and Enhancements**
- Fixed critical Swift syntax errors in ARTab.swift that prevented iOS app compilation
- Enhanced web application with neighbor boundaries toggle functionality (red dashed lines)
- Added satellite view toggle button in the control panel
- Implemented AR view button at bottom of screen for augmented reality access
- Improved property boundary visualization with distinct styling for subject (blue solid) and neighbor properties (red dashed)
- Updated user interface with better organized control panel including view options and status display
- Configured development server workflow for local testing and development
- **Enhanced Multi-Tier ARKit Fallback System** - Implemented comprehensive fallback positioning methods to ensure property boundaries can always be displayed in AR regardless of GPS availability or location coverage

**September 2025 - Multi-Tier ARKit Fallback System**
- **PlaneDetectionFallbackManager** - Uses ARKit plane detection to anchor boundaries to detected surfaces, perfect for indoor environments
- **VisualMarkerFallbackManager** - Computer vision-based positioning using QR codes or distinctive visual markers for high-precision alignment
- **CompassBearingFallbackManager** - Device compass-based orientation system for simple user-guided boundary positioning
- **Enhanced PositioningManager** - Intelligent cascading through all fallback methods with automatic timeouts and seamless transitions
- **Robust Status System** - Clear status feedback for each positioning method with user guidance when input is needed

# User Preferences

Preferred communication style: Simple, everyday language.

# System Architecture

## Frontend Architecture
The application uses a client-side JavaScript architecture built around Leaflet.js for interactive mapping. The frontend is structured as a single-page application with modular JavaScript components handling different aspects of the map functionality including property boundary visualization, zoning data display, and user interface controls.

## Map and Visualization Layer
The core mapping functionality is implemented using Leaflet.js with multiple tile layer options including OpenStreetMap and Esri Satellite imagery. Property boundaries are rendered as GeoJSON layers with distinct styling for subject properties (solid blue lines) and neighboring properties (dashed red lines). The application includes custom controls positioned strategically on the map interface.

## Data Integration Strategy
The application integrates with external geospatial services through configurable endpoints. Property boundary data is retrieved from LINZ services using coordinate-based queries, while zoning information can be optionally configured to use WFS (Web Feature Service) endpoints from various council/vendor systems. The integration supports multiple property key variations to accommodate different data schemas.

## Mobile Application Wrapper
The project includes an iOS application structure that wraps the web application in a native mobile container. This hybrid approach allows the same web-based mapping functionality to be deployed as both a web application and a mobile app, leveraging WebKit for rendering the JavaScript interface within the iOS app.

## Configuration Management
The application uses a centralized configuration approach with constants for API keys, search parameters, and service endpoints. This allows easy customization for different deployment environments and integration with various local government data sources without code changes.

# External Dependencies

## Mapping and Geospatial Libraries
- **Leaflet.js 1.9.4**: Core mapping library providing interactive map functionality, tile layer management, and geospatial data visualization
- **Turf.js 6.x**: Geospatial analysis library used for point-in-polygon operations and spatial calculations for zoning queries

## Data Services
- **LINZ Data Service**: New Zealand's official land information service for property boundary data retrieval
- **WFS Services**: Configurable Web Feature Service endpoints for district plan zoning information from various council systems
- **Tile Services**: OpenStreetMap and Esri ArcGIS Online services for base map imagery

## Development and Code Quality Tools
- **ESLint 9.34.0**: JavaScript linting with support for multiple file types including JSON and Markdown
- **Stylelint 16.23.1**: CSS linting with standard configuration
- **Markdownlint CLI2**: Markdown file linting and formatting
- **Prettier 3.6.2**: Code formatting for consistent style across the project

## iOS Development Framework
- **Xcode Project Structure**: Native iOS application wrapper with asset management and app configuration for mobile deployment