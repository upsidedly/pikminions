// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

enum IslandDestination:Equatable {
    case embedded,shared
    static func select(hostAvailable:Bool,hasAccess:Bool)->Self {hostAvailable && hasAccess ? .shared:.embedded}
}
