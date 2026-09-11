# Usage Agents

Usage is a native macOS menu-bar and Windows taskbar monitor for the remaining
subscription quota of Claude, Codex, and Grok.

```text
[Claude] 82  [OpenAI] 63  [X] 91
```

This repository is the public source mirror of Usage Agents 2.0.38. It does not
currently publish compiled applications, DMGs, installers, or GitHub Releases.

HydRoMo-owned portions are source-available for personal and noncommercial use
under the PolyForm Noncommercial License 1.0.0. This is not OSI open source,
and the public source license does not grant commercial use. The official Mac
App Store application is distributed separately under its applicable Store
EULA.

## Highlights

- Claude, Codex, and Grok quota in one compact surface
- Native SwiftUI `MenuBarExtra(.window)` app for macOS 14+
- Small and medium WidgetKit widgets
- Native .NET Framework 4.8 taskbar companion for Windows 10/11
- Five-minute automatic refresh and manual refresh
- Provider-specific remaining percentages, reset times, and last-good-value handling
- Optional account-identifier display, off by default
- No Usage account, cloud database, analytics service, or browser-cookie import

## Privacy model

Usage relies on the locally installed provider CLIs and keeps provider
credentials owned by those CLIs. It does not bundle credentials, copy tokens
into this repository, or upload quota data to a Usage-operated server. The
macOS widget never contacts providers; it reads only a reduced snapshot written
by the host app into the shared app-group container.

Error text is bounded before display or snapshot persistence. Missing usage is
shown as unavailable and is never converted into an invented `0%` value.

## macOS source build

Requirements:

- macOS 14+
- Xcode 26.x
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- Installed and authenticated `claude`, `codex`, and/or `grok` CLIs

Generate the project and run the headless checks:

```bash
brew install xcodegen
xcodegen generate

xcodebuild \
  -project Usage.xcodeproj \
  -scheme Usage \
  -configuration Debug \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test

./scripts/verify_menubar_bundle.sh
```

`project.yml` contains the public placeholder Apple Team ID `XXXXXXXXXX`.
Replace it with your own 10-character Team ID and use your own bundle/app-group
configuration before producing a signed build. An unsigned Debug build cannot
validate the shared widget container.

Never launch the stable `com.example.usageagents` menu-bar bundle from Terminal, an IDE,
or an agent host. For a manual UI smoke, first use your own development bundle
identifier, then launch the built app directly from Finder once and quit with
the app's power button.

## Windows source build

Build `Windows/Usage.Windows.sln` with Visual Studio, MSBuild, and the .NET
Framework 4.8 developer pack. See [Windows/README.md](Windows/README.md).

## Repository model

This public repository is generated from a private canonical development
repository through an allowlisted, secret-scanned export. Each mirror update
is a normal Git commit; history is never force-pushed by the publisher.

Issues and reproducible bug reports are welcome. Until a contributor license
agreement or equivalent commercial inbound grant is adopted, this mirror does
not accept pull requests containing code, assets, translations, or substantial
documentation. Maintainers may independently implement reported fixes in the
private canonical repository and publish them in a later mirror sync.

## License and trademarks

HydRoMo-owned portions are available under the
[PolyForm Noncommercial License 1.0.0](LICENSE) for the purposes permitted by
that license. Commercial use requires a separate written license; see
[license scope](LICENSE_SCOPE.md). Third-party materials remain under their
own terms in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Claude, OpenAI, ChatGPT, Codex, Grok, X, and their marks belong to their
respective owners. They are used only to identify integrations. Usage is not
affiliated with, endorsed by, or sponsored by those providers. See the
[trademark notice](TRADEMARKS.md).
