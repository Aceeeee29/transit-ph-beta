# Tutorial Integration Plan for Contribute Screen

## Task: Integrate TutorialService and TutorialOverlay into lib/screens/contribute_screen.dart

### Information Gathered:
- `lib/services/tutorial_service.dart`: Contains TutorialService class with:
  - `hasSeenContributeTutorial()` - Check if user has seen tutorial
  - `markContributeTutorialAsSeen()` - Mark tutorial as seen
  - `getContributeTutorialSteps()` - Get 10 tutorial steps
  - `getExampleRoute()` - Example route for demo
- `lib/widgets/tutorial_overlay.dart`: Contains TutorialOverlay widget that:
  - Takes List<TutorialStep>, Map<String, GlobalKey>, onComplete callback
  - Highlights target widgets with animations
  - Shows step-by-step guidance

### Plan:
- [ ] lib/screens/contribute_screen.dart
  - [ ] Add imports for TutorialService and TutorialOverlay
  - [ ] Add state variables: _showTutorial, _targetKeys
  - [ ] Initialize _targetKeys in initState
  - [ ] Add check for tutorial status in initState (show on first visit)
  - [ ] Add GlobalKey to FlutterMap widget (target: 'map')
  - [ ] Add GlobalKey to mode selector elements
  - [ ] Add GlobalKey to finish route button (target: 'finish_button')
  - [ ] Add GlobalKey to form fields container (target: 'route_form')
  - [ ] Add GlobalKey to media buttons (target: 'media_buttons')
  - [ ] Add GlobalKey to preview button (target: 'preview_button')
  - [ ] Add GlobalKey to submit button (target: 'submit_button')
  - [ ] Add _onTutorialComplete method to mark tutorial as seen
  - [ ] Add TutorialOverlay to Stack in build method

### Dependent Files:
- lib/screens/contribute_screen.dart (main file to modify)
- lib/services/tutorial_service.dart (already exists)
- lib/widgets/tutorial_overlay.dart (already exists)

### Followup steps:
- [ ] Test the tutorial integration
- [ ] Verify tutorial shows on first visit
- [ ] Verify tutorial doesn't show after being dismissed
