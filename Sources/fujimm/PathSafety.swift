import Foundation

/// Path predicates that hold on macOS in the presence of symlinks, `..`,
/// case-insensitive volumes (the APFS and exFAT default) and destinations that
/// do not exist yet.
///
/// Foundation's obvious tools are all wrong for this job, each in a way that
/// looks correct in review:
///
///   - `standardizedFileURL` collapses `..` lexically and never resolves a
///     symlink, so `link/../x` becomes `x` even though `link/..` physically
///     leads somewhere else entirely.
///   - `resolvingSymlinksInPath()` is all-or-nothing: if the full path does not
///     exist it resolves nothing, not even leading components that exist and
///     are themselves symlinks — and a destination that does not exist yet is
///     the normal case for a first import. It also maps `/private/tmp` to
///     `/tmp`, the opposite direction from `realpath`, so mixing the two on the
///     two sides of a comparison guarantees a mismatch under `/tmp` and
///     `/var/folders`.
///   - `hasPrefix` says `/a/bc` is inside `/a/b`.
///
/// `realpath(3)` is the primitive that behaves: it resolves symlinks and `..`
/// physically, and returns each component's on-disk spelling, which makes its
/// output safe to compare with `==` on case-sensitive and case-insensitive
/// volumes alike. Its one limitation is that it requires the path to exist,
/// which is what `deepestExisting` works around.
enum PathSafety {

    // MARK: - Primitives

    /// `realpath(3)`. Nil when the path does not exist.
    static func canonical(_ path: String) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(path, &buffer) != nil else { return nil }
        return String(cString: buffer)
    }

    /// Canonicalise the deepest ancestor of `path` that exists, and return the
    /// components below it that do not exist yet.
    ///
    /// Nil when nothing resolves — including any path ending in `..`, because
    /// `deletingLastPathComponent` is a fixed point there. That both terminates
    /// the walk and fails such paths closed.
    static func deepestExisting(_ path: String) -> (resolved: String, tail: [String])? {
        var url = URL(fileURLWithPath: path)
        var tail: [String] = []
        while true {
            if let resolved = canonical(url.path) { return (resolved, tail.reversed()) }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { return nil }
            tail.append(url.lastPathComponent)
            url = parent
        }
    }

    private static func components(_ absolutePath: String) -> [String] {
        absolutePath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }

    private struct FileID: Equatable {
        let device: dev_t
        let inode: ino_t
    }

    /// `stat` follows symlinks, which is what we want: two paths that reach the
    /// same directory through different links are the same directory.
    private static func fileID(_ path: String) -> FileID? {
        var s = stat()
        guard stat(path, &s) == 0 else { return nil }
        return FileID(device: s.st_dev, inode: s.st_ino)
    }

    // MARK: - Containment — fails closed

    /// Can `candidate` only ever resolve to a location at or beneath `root`?
    ///
    /// Every uncertain branch answers `false`. This predicate is the last thing
    /// between a composed path and an arbitrary write: a wrong `false` costs one
    /// skipped file and an error message, a wrong `true` writes outside the
    /// directory the user named.
    static func isContained(_ candidate: String, in root: String) -> Bool {
        guard let rootCanonical = canonical(root) else { return false }
        guard let (ancestor, tail) = deepestExisting(candidate) else { return false }

        // Nothing below the resolved ancestor may steer back upwards.
        for component in tail where component.isEmpty || component == "." || component == ".." {
            return false
        }

        let rootComponents = components(rootCanonical)
        let ancestorComponents = components(ancestor)
        guard ancestorComponents.count >= rootComponents.count,
              Array(ancestorComponents.prefix(rootComponents.count)) == rootComponents
        else { return false }

        // Confirm by identity rather than by string: covers mount-point
        // substitution and anything else that yields two spellings for one
        // directory.
        let atRootDepth = "/" + ancestorComponents.prefix(rootComponents.count).joined(separator: "/")
        guard let rootID = fileID(rootCanonical),
              let ancestorID = fileID(atRootDepth),
              rootID == ancestorID
        else { return false }

        return true
    }

    // MARK: - Directory creation that will not follow a symlink out

    /// Create `path` and any missing parents, one component at a time.
    ///
    /// `FileManager.createDirectory(withIntermediateDirectories:)` follows a
    /// symlink: plant one inside the destination pointing elsewhere, ask for a
    /// directory beneath it, and the write lands outside. Containment is checked
    /// before the write, so only refusing to traverse the link at creation time
    /// closes the window.
    static func createDirectoryChain(at path: String) -> Bool {
        guard let (resolved, tail) = deepestExisting(path) else { return false }
        var current = resolved
        for component in tail {
            current += "/" + component
            if mkdir(current, 0o755) != 0 {
                guard errno == EEXIST else { return false }
                var s = stat()
                // lstat, not stat: an existing symlink here must not be accepted
                // as "the directory already exists".
                guard lstat(current, &s) == 0, (s.st_mode & S_IFMT) == S_IFDIR else { return false }
            }
        }
        return true
    }

    // MARK: - Flag validation

    /// A path fragment supplied on the command line is safe when no component
    /// steers upwards.
    ///
    /// `/` is deliberately allowed. `--date-format 'yyyy/MM/dd'` produces nested
    /// day folders and the README documents it, and `--photos-dir 'Raw/Fuji'`
    /// nests a bucket, which works today. Only `..` escapes, so only `..` is
    /// rejected.
    static func containsUpwardComponent(_ fragment: String) -> Bool {
        fragment.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    }
}
