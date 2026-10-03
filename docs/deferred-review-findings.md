# Deferred OriCmd review findings

These four findings from the 3 October 2026 review are deferred at the user's request because they affect functionality used less often. Deferral does not reduce their severity. Keep these acceptance criteria when scheduling the work; the implementation branches for testing, panel structure, update authentication and accessibility do not fix these issues.

## 1 Remote moves can delete items that were not transferred

**Priority: High. Status: Deferred.**

FTP upload planning omits symlinks and FIFOs but returns them as fully uploaded. Focused tests confirmed both omissions. SFTP uses error-suppressing batch commands for some symlink transfers (`-get` and `-put`); a failed `-get` returned exit status zero. The panel deletes items reported complete when moving, so those false successes can cause source data loss.

Relevant code: [FTP upload planning](../OriCmd/Remote/FTPFileSystem.swift), [SFTP transfers](../OriCmd/Remote/SFTPFileSystem.swift), and [move completion and deletion](../OriCmd/Panel/FilePanelController.swift).

Return completion only for items actually transferred. Propagate unsupported file types, unreadable directories and failed transfers into the selected item's incomplete status. Preserve sources whenever completion cannot be established.

Acceptance checks:

- Moving a symlink or FIFO never deletes it unless the destination has the intended representation.
- Moving a folder containing an unsupported or failed item preserves that item locally.
- Failed SFTP symlink transfers are reported and never followed by source deletion.
- Successful transfers and deliberately skipped conflicts retain their existing behavior.

## 2 Server listings can escape the download destination

**Priority: High. Status: Deferred.**

Remote listing parsers accept names containing path separators. Downloads append these names to a local destination. A focused test using `../outside.txt` as a parsed server entry wrote a file outside the chosen folder.

Relevant code: [FTP listing parser and download planning](../OriCmd/Remote/FTPFileSystem.swift), and [shared long listing parser](../OriCmd/Remote/RemoteFileSystem.swift).

Validate entries as single file names before exposing them in the panel or planning transfers. Reject separators, empty names, dot entries and embedded nulls. Enforce containment under the resolved destination and prevent existing destination symlinks from redirecting writes outside it.

Acceptance checks:

- Crafted MLSD and LIST entries cannot write outside the chosen destination.
- Recursive transfers enforce the same constraints at every level.
- Existing destination symlinks cannot redirect a download outside the destination.
- Spaces, Unicode and ordinary punctuation remain valid file names.

## 3 Interrupted downloads overwrite existing contents

**Priority: High. Status: Deferred.**

FTP and SFTP download directly to final destination paths. A failed FTP download replaced an existing file's contents with a 16 KiB partial download.

Relevant code: [FTP downloads](../OriCmd/Remote/FTPFileSystem.swift), [SFTP downloads](../OriCmd/Remote/SFTPFileSystem.swift), and the existing [atomic local transfer implementation](../OriCmd/FileSystem/Transfer.swift).

Download each file to a temporary sibling. Validate completion and replace the target only after success. Remove temporary files on failure or cancellation. Apply equivalent protection to uploads where the server supports a safe final rename.

Acceptance checks:

- Connection failures and cancellation preserve pre-existing destination contents.
- Failed downloads never appear under their final names.
- Successful downloads replace their targets only after completion.
- Temporary files are cleaned up, and move operations delete sources only after successful replacement.

## 4 Content synchronization can block on named pipes

**Priority: Medium. Status: Deferred.**

Directory comparison collects FIFOs as ordinary files. Opening a FIFO for content comparison blocks waiting for a writer. A focused test remained blocked after cancellation and was terminated after three seconds.

Relevant code: [directory collection and byte comparison](../OriCmd/Sync/DirectoryComparison.swift).

Read contents only from regular files, define explicit symlink behavior, and represent unsupported or unreadable items separately from missing or equal items. Check cancellation during traversal and byte comparison, and propagate read errors instead of treating them as end of file.

Acceptance checks:

- FIFOs, sockets and devices never block comparison.
- Cancellation stops traversal and regular-file comparison promptly.
- Read failures cannot be reported as equal contents or as absent files.
- Symlinks have documented, tested comparison behavior.

## Review validation

The Debug build passed. Focused tests exercised the project's actual Swift transfer and comparison sources with disposable fixtures, a localhost FTP server and the system SFTP client. The full UI regression suite was not run during the review.
