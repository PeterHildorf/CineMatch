#!/usr/bin/env python3
"""Run the actual Swift scorer/service tests without Xcode or external packages.

Uses a temporary SwiftPM package, copying only the listed source files and public
model resources. No app credentials are copied. This complements an iOS build;
it does not compile SwiftUI. Use --with-supabase to compile the remote adapters
against the SDK version pinned by the Xcode project and run their local tests.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile


SOURCE_FILES = [
    "Core/ML/ConditionalNeighborModelFile.swift",
    "Core/ML/ConditionalNeighborRecommender.swift",
    "Core/ML/ConditionalNeighborModelStore.swift",
    "Core/ML/ModelStoreError.swift",
    "Core/Logging/AppLog.swift",
    "Core/Models/Verdict.swift",
    "Core/Models/TasteSignal.swift",
    "Core/Models/TasteInput.swift",
    "Core/Models/Title.swift",
    "Core/Models/Recommendation.swift",
    "Core/Models/RecommendationEvent.swift",
    "Core/Services/Protocols/MovieDataService.swift",
    "Core/Services/Protocols/TasteSignalService.swift",
    "Core/Services/Protocols/RecommendationService.swift",
    "Core/Services/Local/ConditionalNeighborMovieDataService.swift",
    "Core/Services/Local/ConditionalNeighborRecommendationService.swift",
    "Core/Services/Local/SupportedCatalogueTasteSignalService.swift",
    "Core/Services/Mock/MockTasteSignalService.swift",
    "Core/Persistence/DailyPickStore.swift",
    "Features/Recommendations/ViewModels/RecommendationsViewModel.swift",
    "Core/Models/TitleMedia.swift",
    "Core/Models/RecommendationReason.swift",
    "Core/Models/StreamingService.swift",
    "Core/Models/StreamingPreferences.swift",
    "Core/Services/Protocols/TitleMediaService.swift",
    "Core/Services/Protocols/PreferencesService.swift",
    "Core/Services/Protocols/RecommendationEventLogger.swift",
    "Core/Services/Mock/MockRecommendationService.swift",
    "Core/Services/Mock/MockMovieDataService.swift",
    "Core/Services/Mock/MockTitleMediaService.swift",
    "Core/Services/Mock/MockPreferencesService.swift",
    "Core/Services/Mock/MockRecommendationEventLogger.swift",
]
UNIT_TESTS = [
    "ConditionalNeighborTests.swift",
    "SupportedCatalogueTasteSignalTests.swift",
    "DailyPickMigrationTests.swift",
    "RecommendationsCacheRefreshTests.swift",
]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--unit-only", action="store_true", help="Run synthetic checks before a verified bundle is available")
    parser.add_argument("--with-supabase", action="store_true", help="Also compile and test the remote adapters using the project's pinned SDK")
    parser.add_argument("--test-file", action="append", choices=UNIT_TESTS, help="Limit the synthetic test files during development")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    with tempfile.TemporaryDirectory(prefix="cinematch-swift-") as directory:
        package = Path(directory)
        sources = package / "Sources/CineMatch"
        tests = package / "Tests/CineMatchTests"
        resources = tests / "Resources"
        sources.mkdir(parents=True)
        resources.mkdir(parents=True)
        # Ensures Bundle.module exists for the test target even during unit-only checks.
        (resources / "NOTICE.txt").write_text("Public CineMatch test resources only.\n")
        source_names = list(SOURCE_FILES)
        if args.with_supabase:
            source_names += ["Core/Services/Remote/SupabaseTasteSignalService.swift",
                             "Core/Services/Remote/SupabaseRecommendationEventLogger.swift"]
        for name in source_names:
            shutil.copy2(repo / "CineMatch" / name, sources / Path(name).name)
        test_names = list(args.test_file or UNIT_TESTS)
        if args.with_supabase:
            test_names.append("RecommendationEventIdentityTests.swift")
        if not args.unit_only:
            test_names.append("ConditionalNeighborReferenceTests.swift")
            shutil.copy2(repo / "CineMatch/Core/Resources/cinematch_knn.json", resources)
            shutil.copy2(repo / "CineMatchTests/knn_reference_cases.json", resources)
        for name in test_names:
            shutil.copy2(repo / "CineMatchTests" / name, tests / name)
        dependencies = "[]"
        core_dependencies = "[]"
        if args.with_supabase:
            lock = repo / "CineMatch.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
            pins = json.loads(lock.read_text())["pins"]
            version = next(pin["state"]["version"] for pin in pins if pin["identity"] == "supabase-swift")
            dependencies = '[.package(url: "https://github.com/supabase/supabase-swift", exact: "' + version + '")]'
            core_dependencies = '[.product(name: "Supabase", package: "supabase-swift")]'
            shutil.copy2(lock, package / "Package.resolved")
        (package / "Package.swift").write_text('''// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "CineMatchChecks",
    platforms: [.macOS(.v15)],
    products: [.library(name: "CineMatch", targets: ["CineMatch"])],
    dependencies: __DEPENDENCIES__,
    targets: [
        .target(name: "CineMatch", dependencies: __CORE_DEPENDENCIES__, swiftSettings: [.defaultIsolation(MainActor.self)]),
        .testTarget(name: "CineMatchTests", dependencies: ["CineMatch"],
                    resources: [.process("Resources")],
                    swiftSettings: [.defaultIsolation(MainActor.self)])
    ],
    swiftLanguageModes: [.v5]
)
'''.replace("__DEPENDENCIES__", dependencies).replace("__CORE_DEPENDENCIES__", core_dependencies))
        command = ["swift", "test", "--package-path", str(package), "--disable-xctest", "--enable-swift-testing"]
        # Command Line Tools ships Swift Testing as a developer framework, but
        # SwiftPM does not always add that framework directory automatically.
        developer = Path(subprocess.check_output(["xcode-select", "-p"], text=True).strip())
        frameworks = developer / "Library/Developer/Frameworks"
        if (frameworks / "Testing.framework").exists():
            command += ["-Xswiftc", "-F", "-Xswiftc", str(frameworks),
                        "-Xlinker", "-F", "-Xlinker", str(frameworks),
                        "-Xlinker", "-rpath", "-Xlinker", str(frameworks)]
            if not (frameworks / "_Testing_Foundation.framework/Modules").exists():
                # Some CLT releases ship the optional Foundation testing overlay
                # binary without its Swift module. The tests use core Testing APIs.
                command += ["-Xswiftc", "-Xfrontend", "-Xswiftc", "-disable-cross-import-overlays"]
        plugins = developer / "usr/lib/swift/host/plugins/testing"
        if plugins.exists():
            command += ["-Xswiftc", "-plugin-path", "-Xswiftc", str(plugins)]
        result = subprocess.run(command, check=False)
        raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
