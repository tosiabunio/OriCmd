# File panel controller

`FilePanelController` coordinates one panel on the main actor. Its extensions keep
related navigation and transfer code together while retaining the same controller,
delegates, task cancellation and tab state.

| File | Responsibility |
| --- | --- |
| `FilePanelController.swift` | Panel lifecycle, directory loading, commands, remote connections, and view delegates |
| `FilePanelController+Locations.swift` | Archive locations, history entries, and state owned by a folder tab |
| `FilePanelController+Tabs.swift` | Creating, moving and closing tabs; back/forward and recent-folder navigation |
| `FilePanelController+Archives.swift` | Browsing nested archives, rereading entries, and applying archive edits |
| `FilePanelController+Transfers.swift` | Uploads, downloads, clipboard copies, and promised-file delivery |

These files are included automatically by the Xcode project's synchronized source
group. They share the controller's main-actor isolation. Helpers used only within
one extension remain private; state and methods used across files have module
visibility because Swift's private access does not cross extension files.

This change moves existing implementations without changing file operations or
addressing the separately deferred remote-transfer and synchronization findings.
Debug builds and the existing UI regression suite exercise these same paths.
