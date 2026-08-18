import Foundation

#if EGRESS_FM_COACH && canImport(FoundationModels)
import FoundationModels
#endif

/// Whether the on-device Foundation model is usable on this device (§A.3). Drives the coach seam: when
/// this is `false`, the whole app runs on `CannedCoach` — a fully coherent experience, per the
/// §3.5.4 device-unsupported row.
///
/// The Foundation-model probe lives behind the `EGRESS_FM_COACH` build flag, which is defined in
/// Config/Shared.xcconfig. When the flag is set and the device reports Apple Intelligence as available,
/// the on-device coach runs; otherwise (flag off, unsupported device, or model not ready) this returns
/// `false` and the whole app runs on `CannedCoach` — a fully coherent experience per §3.5.4.
enum DeviceCapabilities {
    static var supportsOnDeviceModel: Bool {
        #if EGRESS_FM_COACH && canImport(FoundationModels)
        if #available(iOS 26, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        return false
        #else
        return false
        #endif
    }
}
