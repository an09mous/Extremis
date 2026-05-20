# Contract: ImagePersistence

**Module**: `Utilities/ImagePersistence.swift`
**Type**: `actor` (thread-safe file I/O)

## Public Interface

```swift
actor ImagePersistence {
    static let shared = ImagePersistence()

    /// Directory for stored images.
    /// ~/Library/Application Support/Extremis/images/
    var imagesDirectory: URL { get }

    /// Save an ImageAttachment's full-resolution data to disk.
    /// - Returns: ImageRef for persistence in PersistedMessage
    func save(_ attachment: ImageAttachment) throws -> ImageRef

    /// Save multiple attachments.
    func save(_ attachments: [ImageAttachment]) throws -> [ImageRef]

    /// Load full-resolution image data by reference.
    func loadImageData(for ref: ImageRef) throws -> Data

    /// Restore an ImageAttachment from an ImageRef (loads full image from disk).
    func restore(from ref: ImageRef) throws -> ImageAttachment

    /// Restore multiple ImageAttachments from refs.
    func restore(from refs: [ImageRef]) throws -> [ImageAttachment]

    /// Delete image file from disk.
    func delete(ref: ImageRef) throws

    /// Remove orphaned image files not referenced by any active session.
    /// - Parameter activeRefs: Set of image IDs currently referenced by sessions
    func cleanupOrphaned(activeRefs: Set<UUID>) throws -> Int
}
```

## Behavior Contract

1. **Directory creation**: `imagesDirectory` is created on first access if it doesn't exist.
2. **File naming**: Images stored as `{uuid}.{format}` (e.g., `abc123.jpg`).
3. **Atomic writes**: Use `Data.write(to:options:.atomic)` to prevent corruption.
4. **Thumbnail in ref**: `ImageRef.thumbnailBase64` is set from `ImageAttachment.thumbnailData` at save time — no separate thumbnail file.
5. **Restoration**: `restore(from:)` loads file data and reconstructs `ImageAttachment` using ref metadata (dimensions, format, filename).
6. **Missing files**: If image file is missing on restore, throw error but don't crash — caller should handle gracefully (show placeholder).
7. **Cleanup**: `cleanupOrphaned()` is called during session garbage collection. It scans `imagesDirectory` and deletes files not in `activeRefs`.
8. **Thread safety**: Actor isolation ensures concurrent save/load operations don't corrupt state.

## File Layout

```text
~/Library/Application Support/Extremis/
├── sessions/
│   ├── {session-id-1}.json    # PersistedSession with imageRefs
│   └── {session-id-2}.json
└── images/
    ├── {uuid-1}.jpg
    ├── {uuid-2}.jpg
    └── {uuid-3}.png
```
