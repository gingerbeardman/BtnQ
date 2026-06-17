//
//  DidactTests.swift
//  DidactTests
//
//  Created by Matt Sephton on 2026-06-13.
//

import Testing
import Foundation
@testable import Didact

struct DidactTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    // MARK: - KnownProfileMatcher autofill (P4)

    /// A minimal RD280UG-like profile: generic perfect-matchable controls plus a
    /// model-specific "Sensitivity" (conditional logic) and the distinctive Color
    /// Mode cycle on a vendor code.
    private func rd280ugLike() throws -> MonitorConfig {
        let json = """
        {
          "schemaVersion": 1, "name": "Fake RD280UG", "match": ["RD280U"],
          "controls": [
            { "kind": "range", "label": "Brightness", "vcp": "10", "min": 0, "max": 100 },
            { "kind": "range", "label": "Volume", "vcp": "62", "min": 0, "max": 100 },
            { "kind": "cycle", "label": "Source", "vcp": "60",
              "options": [ {"value":"0f","label":"DisplayPort"}, {"value":"11","label":"HDMI"}, {"value":"13","label":"USB-C"} ] },
            { "kind": "range", "label": "Sensitivity", "vcp": "e5", "min": 1, "max": 10,
              "hideWhen": { "vcp": "dc", "equalsAny": ["0a"], "system": "hdr" } },
            { "kind": "range", "label": "Night Level", "vcp": "d0", "min": 1, "max": 10 },
            { "kind": "cycle", "label": "Color Mode", "vcp": "dc",
              "options": [ {"value":"30","label":"Coding"}, {"value":"0a","label":"sRGB"}, {"value":"12","label":"User"} ] }
          ]
        }
        """
        return try JSONDecoder().decode(MonitorConfig.self, from: Data(json.utf8))
    }

    /// PD2705Q-like caps: it shares the generic codes and exposes a bare, continuous
    /// 0xE5 — but its Color Mode (0xDC) values do NOT match the RD280UG's, so the
    /// profile is not distinctively recognized.
    private let pd2705qCaps: [UInt8: [Int]] = [
        0x10: [], 0x12: [], 0x14: [0x04, 0x05, 0x08, 0x0B], 0x60: [0x0F, 0x11, 0x13],
        0x62: [], 0x87: [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A],
        0xB2: [], 0xDC: [0x00, 0x0A, 0x0C, 0x0F, 0x10, 0x12, 0x13, 0x14, 0x20, 0x23], 0xE5: [],
    ]

    @Test func autofillDoesNotLeakModelSpecificControlsOntoUnrecognizedMonitor() throws {
        let confirmed = KnownProfileMatcher.confirmedControls(from: [try rd280ugLike()], capabilities: pd2705qCaps)
        let codes = Set(confirmed.compactMap(\.featureCode))
        // Generic, condition-free controls are still useful to import.
        #expect(codes.contains(0x10))   // Brightness
        #expect(codes.contains(0x62))   // Volume
        #expect(codes.contains(0x60))   // Source
        // The model-specific Sensitivity (hideWhen) must NOT ride in on a bare 0xE5.
        #expect(!codes.contains(0xE5))
        // Nor a vendor-code range like Night Level (d0) onto an unrecognized monitor
        // (it isn't in these caps anyway, but the gate is what guarantees it).
        #expect(!codes.contains(0xD0))
    }

    @Test func unrecognizedMonitorIsNotRecognized() throws {
        // No distinctive vendor-cycle match (RD280UG's 0xDC values differ from this
        // monitor's), so it must not be adopted wholesale.
        #expect(KnownProfileMatcher.recognizedProfile(from: [try rd280ugLike()], capabilities: pd2705qCaps) == nil)
    }

    @Test func genuineRD280UGStillRecognizesAndImportsSensitivity() throws {
        // Caps where the distinctive Color Mode (0xDC) values match the profile.
        let rdCaps: [UInt8: [Int]] = [
            0x10: [], 0x62: [], 0x60: [0x0F, 0x11, 0x13], 0xE5: [],
            0xD0: [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A],
            0xDC: [0x30, 0x0A, 0x12],
        ]
        let profile = try rd280ugLike()
        #expect(KnownProfileMatcher.recognizedProfile(from: [profile], capabilities: rdCaps)?.name == "Fake RD280UG")
        // Distinctively recognized → its model-specific Sensitivity is now trusted.
        let codes = Set(KnownProfileMatcher.confirmedControls(from: [profile], capabilities: rdCaps).compactMap(\.featureCode))
        #expect(codes.contains(0xE5))
        // Gap A: a stepped range (Night Level d0, advertised as 01…0A) imports too.
        #expect(codes.contains(0xD0))
    }
}
