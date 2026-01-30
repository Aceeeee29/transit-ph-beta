# TODO: Add Google Login

## Completed Steps
- [x] Add google_sign_in package to pubspec.yaml
- [x] Modify login_screen.dart to include Google sign-in button and logic
- [x] Implement _signInWithGoogle method with Firebase authentication and Firestore user creation
- [x] Run flutter pub get to install dependencies
- [x] Run flutter analyze to check for errors (no new errors introduced)

## Next Steps
- [ ] Configure Firebase project for Google sign-in (add Google as sign-in provider in Firebase Console)
- [ ] Test the Google login functionality on device/emulator
- [ ] Ensure SHA-1 certificate fingerprint is added to Firebase for Android
- [ ] Test on iOS if applicable (add reversed client ID to Info.plist)
