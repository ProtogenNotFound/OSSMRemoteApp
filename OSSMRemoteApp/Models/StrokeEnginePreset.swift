//
//  StrokeEnginePreset.swift
//  OSSMRemoteApp
//

import Foundation
import SwiftData

@Model
final class StrokeEnginePreset {
    @Attribute(.unique) var id: UUID
    var name: String
    var speed: Int
    var stroke: Int
    var depth: Int
    var sensation: Int
    var pattern: Int
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        name: String,
        speed: Int,
        stroke: Int,
        depth: Int,
        sensation: Int,
        pattern: Int,
        sortOrder: Int
    ) {
        self.id = id
        self.name = name
        self.speed = speed
        self.stroke = stroke
        self.depth = depth
        self.sensation = sensation
        self.pattern = pattern
        self.sortOrder = sortOrder
    }
}

