# Repository Guidelines

## Project Structure & Module Organization
- Swift packages: `ChatClientKit/` (library) and `OAuthKit/` (library with tests).
- App entry: `test_chatclient/` (`main.swift`) with Xcode project `test_chatclient.xcodeproj`.
- JS utilities: `js/` (Bun runtime, ESM modules).
- Build artifacts: `build/` (derived data; do not edit or commit).

## Build, Test, and Development Commands
- SwiftPM build (libraries): `cd ChatClientKit && swift build` and `cd OAuthKit && swift build`.
- SwiftPM tests (OAuthKit): `cd OAuthKit && swift test`.
- Xcode app: `open test_chatclient.xcodeproj` to run from Xcode.
- CLI build (if configured): `xcodebuild -project test_chatclient.xcodeproj -scheme test_chatclient -configuration Debug -derivedDataPath ./build | xcbeautify`.
- JS: `cd js && bun install` then `bun run index.js`.

## Coding Style & Naming Conventions
- Swift: follow Swift API Design Guidelines; 4‑space indent; files `PascalCase.swift`; types `UpperCamelCase`; methods/vars `lowerCamelCase`; enum cases `lowerCamelCase`.
- Prefer small, focused types and extensions (see `ChatClientKit/Sources/ChatClientKit/Extension`).
- Use `Logger` for logging; avoid `print` in production code.
- JS: ESM modules, 2‑space indent, async/await; keep files small (e.g., `js/index.js`).

## Testing Guidelines
- Framework: XCTest under `OAuthKit/Tests/OAuthKitTests/*.swift`.
- Name tests `test...` within `XCTestCase` subclasses; cover auth flows, PKCE, and token storage.
- Run locally: `cd OAuthKit && swift test`.
- Add tests alongside code changes affecting OAuth behavior.

## Commit & Pull Request Guidelines
- Commits: clear, imperative subject (e.g., "Add PKCE validation"); one logical change per commit. Conventional prefixes allowed (`feat:`, `fix:`, `refactor:`).
- PRs: concise description, rationale, test coverage notes, and reproduction steps; link issues. Include screenshots only for UI changes.
- Keep diffs minimal; avoid touching `build/` and Xcode user data.

## Security & Configuration Tips
- Never commit client secrets or tokens; use placeholders and local env config.
- Prefer secure stores (e.g., Keychain) for token storage outside tests.
- Validate OAuth redirects and scopes; document provider‑specific settings in PRs.

## Agent‑Specific Notes
- Treat `ChatClientKit/` and `OAuthKit/` as SwiftPM‑first modules; do not rename.
- Prefer SwiftPM for library changes; validate with `swift build`/`swift test` before Xcode.

