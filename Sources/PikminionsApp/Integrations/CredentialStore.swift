// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Matthew Williams

import Antille

enum PikminKeychain {
    static func read(_ account: String) -> String? {
        LocalCredentialStore.read(service: "dev.upsided.pikminions", account: account)
    }
    static func save(_ value: String, account: String) throws {
        try LocalCredentialStore.save(value, service: "dev.upsided.pikminions", account: account)
    }
    static func delete(_ account: String) {
        LocalCredentialStore.delete(service: "dev.upsided.pikminions", account: account)
    }
}
