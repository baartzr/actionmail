## Release Preparation Plan (Android & Windows)

### Scope Overview
- Android (Play Store first release)
- Windows (packaged installer or Store baseline)

### Areas To Address
1. **Project Health**
   - Align Flutter/Dart with stable channel.
   - Eliminate analyzer warnings, deprecated APIs, dead code, and unused assets/dependencies.

2. **Functional Quality**
   - Validate end-to-end flows: authentication, Gmail sync, action banners, attachment handling.
   - Exercise background tasks, account switching, offline/poor-network handling, and error surfaces.

3. **Visual/UI Polish**
   - Review layout on varied screen sizes/DPI.
   - Ensure theming, iconography, typography consistency; verify dark mode.
   - Confirm mouse/keyboard support and window behavior on Windows.

4. **Localization & Accessibility**
   - Externalize user-facing strings; ensure English baseline is complete.
   - Run accessibility checks (screen reader labels, focus order, contrast).

5. **Performance & Stability**
   - Measure startup, sync latency, scrolling.
   - Monitor logs for exceptions, crashes, memory leaks.

6. **Security & Privacy**
   - Audit OAuth scopes, token storage, cached data.
   - Remove sensitive logging; prepare privacy notice and consent flows if needed.

7. **Platform-Specific Requirements**
   - **Android:** Manifest validation, permissions, adaptive icons, application ID, signing key, Play assets.
   - **Windows:** App icon, versioning, packaging (MSIX/installer), dependency/runtime handling, code signing plan.

8. **Analytics & Monitoring**
   - Integrate crash/analytics tooling (e.g., Firebase Crashlytics/Analytics).
   - Respect privacy opt-in/out requirements.

9. **Testing & Automation**
   - Establish unit, widget, integration suites for critical flows.
   - Set up CI for tests and clean-environment builds.

10. **Documentation**
    - Prepare release notes, onboarding/support docs, known issues, rollback plan.
    - Create an internal QA checklist for sign-off.

### Proposed Next Steps
1. **Baseline Assessment**
   - `flutter analyze`, unit/widget tests, manual smoke test on Android emulator and Windows build.
   - Document outstanding warnings, crashes, and blockers.

2. **Stabilize Codebase**
   - Resolve analyzer findings and deprecated API usage.
   - Address known functional issues (e.g., attachment closing behavior, actions window state).

3. **Platform Configuration**
   - Android: configure app name, bundle ID, signing, adaptive icons, permissions.
   - Windows: define app identity, manifests, packaging strategy, signing certificates.

4. **Monitoring Integration**
   - Add crash/analytics tooling; verify events in debug builds.

5. **QA Pass**
   - Execute scripted/manual tests covering major features and edge cases; log defects.

6. **Performance Pass**
   - Profile startup/sync/UI; optimize hotspots; confirm acceptable memory usage.

7. **Release Assets**
   - Produce marketing copy, screenshots, privacy policy, compliance disclosures.

8. **Build & Smoke-Test Release Packages**
   - Generate Android App Bundle (`.aab`) and Windows installer/package.
   - Install on physical devices/VMs; perform final smoke tests.

9. **Document & Handoff**
   - Compile release notes, QA summary, deployment checklist for future cycles.


