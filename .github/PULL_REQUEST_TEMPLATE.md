<!-- Thanks for contributing! English or German is fine. Please keep PRs small: one topic per PR. -->

## What and why
<!-- What does this PR change, and why? Link the issue: "Fixes #123". -->

## How I tested it
<!-- macOS version, bridge model (v2 / Pro), what you clicked or said. Tests never change anything on a real bridge. -->
- macOS:
- Bridge:
- [ ] `make test` passes (HueKit unit tests)
- [ ] Built and ran the app with `make install`

## Screenshots
<!-- For UI changes: before / after, light AND dark mode. Use made-up room and lamp names. -->

## Checklist
- [ ] Logic lives in `Packages/HueKit` (with tests), UI and macOS integration in `App/`
- [ ] No new warnings (Swift 6 strict concurrency)
- [ ] User-facing texts added to the String Catalog in German **and** English (or noted below which one is missing)
- [ ] Continuous animations pause while the panel is hidden (0 % CPU when closed)
- [ ] No new dependencies, network connections, analytics or Hue/Signify assets
- [ ] No private data (bridge keys, IPs, real names) in code, fixtures or screenshots
- [ ] CHANGELOG.md updated under "Unreleased" (if user-visible)

By submitting this pull request I agree that my contribution is licensed under the MIT License.
