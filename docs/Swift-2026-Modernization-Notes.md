# Swift 2026 Modernization Notes (NeoHub)

This file captures the key public docs used to justify the 2026 modernization plan.

## Swift.org sources
- Swift 5.10 Released (Mar 5, 2024)
  - URL: https://www.swift.org/blog/swift-5.10-released/
  - Excerpt: "Swift was designed to be safe by default, preventing entire categories of programming mistakes at compile time. Sources of undefined behavior in C-based languages, such as using variables before they’re initialized or a use-after-free, are defined away in Swift."
- Swift 5.9 Released (Sep 18, 2023)
  - URL: https://www.swift.org/blog/swift-5.9-released/
  - Excerpt: "Swift 5.9 is now available!"
- Swift 5.8 Released (Mar 30, 2023)
  - URL: https://www.swift.org/blog/swift-5.8-released/
  - Excerpt: "Swift 5.8 is now officially released! ... including hasFeature to support piecemeal adoption of upcoming features, ... improvements to tools in the Swift ecosystem including Swift-DocC, Swift Package Manager, and SwiftSyntax, refined Windows support, and more."
- Using Upcoming Feature Flags (May 30, 2023)
  - URL: https://www.swift.org/blog/using-upcoming-feature-flags/
  - Excerpt: "Beginning in Swift 5.8 you can flexibly adopt upcoming Swift features using a new compiler flag and compilation condition. This post describes the problem upcoming feature flags solve, their benefits, and how to get started using them in your projects."
- Iterate Over Parameter Packs in Swift 6.0 (Mar 7, 2024)
  - URL: https://www.swift.org/blog/pack-iteration/
  - Excerpt: "Parameter packs, introduced in Swift 5.9, make it possible to write generics that abstract over the number of arguments... With Swift 6.0, pack iteration makes it easier than ever to work with parameter packs."

## Apple Developer Documentation
- Observation framework
  - URL: https://developer.apple.com/documentation/observation
  - Description: "Make responsive apps that update the presentation when underlying data changes."
- SMAppService (ServiceManagement)
  - URL: https://developer.apple.com/documentation/servicemanagement/smappservice
  - Description: "An object the framework uses to control helper executables that live inside an app's main bundle."
- Logger (os)
  - URL: https://developer.apple.com/documentation/os/logger
  - Description: "An object for writing interpolated string messages to the unified logging system."
- NWListener (Network)
  - URL: https://developer.apple.com/documentation/network/nwlistener
  - Description: "An object you use to listen for incoming network connections."
- Swift Testing
  - URL: https://developer.apple.com/documentation/testing
  - Description: "Create and run tests for your Swift packages and Xcode projects."

## Relevance to NeoHub modernization
- Observation and @MainActor align with SwiftUI state management updates.
- SMAppService replaces third-party launch-at-login helpers.
- os.Logger replaces swift-log + syslog backend with system logging.
- Network framework is the system alternative to SwiftNIO for Unix socket IPC.
- Upcoming-feature flags enable incremental Swift 6 readiness.
