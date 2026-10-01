import Foundation

/// Byte-level total order over UUIDs — used as a deterministic tie-breaker in layout algorithms.
/// `UUID.uuidString` comparison (the previous tie-break in `TreeLayout`, `RadialLayout`, and
/// `SpiderLayout`) allocates two 36-byte `String`s per comparison; no caller depends on the
/// specific order chosen (only that *some* consistent order is used), so a plain byte compare
/// over the 16-byte `uuid_t` is a drop-in, allocation-free replacement.
public nonisolated func uuidIsOrderedBefore(_ a: UUID, _ b: UUID) -> Bool {
    let x = a.uuid
    let y = b.uuid
    if x.0 != y.0 { return x.0 < y.0 }
    if x.1 != y.1 { return x.1 < y.1 }
    if x.2 != y.2 { return x.2 < y.2 }
    if x.3 != y.3 { return x.3 < y.3 }
    if x.4 != y.4 { return x.4 < y.4 }
    if x.5 != y.5 { return x.5 < y.5 }
    if x.6 != y.6 { return x.6 < y.6 }
    if x.7 != y.7 { return x.7 < y.7 }
    if x.8 != y.8 { return x.8 < y.8 }
    if x.9 != y.9 { return x.9 < y.9 }
    if x.10 != y.10 { return x.10 < y.10 }
    if x.11 != y.11 { return x.11 < y.11 }
    if x.12 != y.12 { return x.12 < y.12 }
    if x.13 != y.13 { return x.13 < y.13 }
    if x.14 != y.14 { return x.14 < y.14 }
    return x.15 < y.15
}
