import Darwin

public enum DiskIOPolicy {
    /// Process scope follows utility work across executor threads; never fetch dataless content.
    @discardableResult public static func disableMaterialization() -> Bool {
        setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_PROCESS,
                      IOPOL_MATERIALIZE_DATALESS_FILES_OFF) == 0
    }
}
