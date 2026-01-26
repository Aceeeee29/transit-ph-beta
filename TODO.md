# TODO: Implement File Scanner and Security Manager

## Steps to Complete

- [ ] Add `crypto` and `mime` dependencies to `pubspec.yaml`
- [ ] Create `lib/security/models/` directory
- [ ] Create `lib/security/models/link_safety_result.dart`: Move `LinkSafetyResult` class from `link_safety_service.dart`
- [ ] Create `lib/security/models/file_scan_result.dart`: New class with `isBlocked`, `reasons`, `sha256`, `mimeType`, `sizeBytes`
- [ ] Modify `lib/security/link_safety_service.dart`: Import `LinkSafetyResult` from models, remove class definition
- [ ] Create `lib/security/file_scan_service.dart`: `FileScanService` class with `scanFile(File file)` method implementing SHA-256 hashing, file size limit, MIME type validation, dangerous extension blocking, and local bad-hash list with update stub
- [ ] Create `lib/security/security_manager.dart`: `SecurityManager` class exposing `openLink(BuildContext, String)` and `scanAttachment(File)` APIs
- [ ] Modify `lib/screens/feed_screen.dart`: Update `buildPostItem` to detect and make URLs in `post.content` tappable using `SecurityManager.openLink`
- [ ] Run `flutter pub get` after adding dependencies
- [ ] Test link tapping in feed screen and file scanning functionality
