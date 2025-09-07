import Foundation
import CoreLocation

/// Streaming KML parser that extracts all <coordinates> blocks into rings.
/// Call from a background queue; safe + lightweight.
final class KMLRingsParser: NSObject, XMLParserDelegate {
    private var rings: [[CLLocationCoordinate2D]] = []
    private var insideCoordinates = false
    private var buffer = String()

    /// Parse all coordinate rings from KML/XML data.
    static func parse(data: Data) -> [[CLLocationCoordinate2D]] {
        let delegate = KMLRingsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        _ = parser.parse()   // on error -> 0 rings; safe default
        return delegate.rings
    }

    // MARK: XMLParserDelegate
    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if elementName.lowercased() == "coordinates" {
            insideCoordinates = true
            buffer.removeAll(keepingCapacity: true)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideCoordinates { buffer.append(string) }
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        if elementName.lowercased() == "coordinates" {
            insideCoordinates = false
            let tokens = buffer.split(whereSeparator: { $0.isWhitespace })
            var ring: [CLLocationCoordinate2D] = []
            ring.reserveCapacity(tokens.count)

            for t in tokens {
                // KML: "lon,lat[,alt]"
                let parts = t.split(separator: ",")
                guard parts.count >= 2,
                      let lon = Double(parts[0]),
                      let lat = Double(parts[1]) else { continue }
                ring.append(.init(latitude: lat, longitude: lon))
            }
            if ring.count >= 3 { rings.append(ring) }
            buffer.removeAll(keepingCapacity: true)
        }
    }
}

//  KMLRingsParser.swift
//  PropertyView
//
//  Created by Brendon Hogg on 28/08/2025.
//
