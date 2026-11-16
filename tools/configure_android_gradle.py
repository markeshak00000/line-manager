#!/usr/bin/env python3
"""Apply Android desugaring settings required by flutter_local_notifications."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "android" / "app"


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def patch_kts(path: Path) -> None:
    text = path.read_text(encoding="utf-8")

    if "isCoreLibraryDesugaringEnabled" not in text:
        match = re.search(r"(?m)^\s*compileOptions\s*\{", text)
        if match:
            insert_at = match.end()
            text = text[:insert_at] + "\n        isCoreLibraryDesugaringEnabled = true" + text[insert_at:]
        else:
            match = re.search(r"(?m)^android\s*\{", text)
            if not match:
                fail(f"Could not find android {{ block in {path}")
            insert_at = match.end()
            block = (
                "\n    compileOptions {\n"
                "        isCoreLibraryDesugaringEnabled = true\n"
                "    }\n"
            )
            text = text[:insert_at] + block + text[insert_at:]

    if "coreLibraryDesugaring(" not in text:
        match = re.search(r"(?m)^dependencies\s*\{", text)
        if not match:
            text += (
                "\n\ndependencies {\n"
                '    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n'
                "}\n"
            )
        else:
            text = text[:match.end()] + (
                '\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")'
            ) + text[match.end():]

    # The notification plugin's Android setup calls for multidex in defaultConfig.
    if "multiDexEnabled" not in text:
        match = re.search(r"(?m)^\s*defaultConfig\s*\{", text)
        if match:
            text = text[:match.end()] + "\n        multiDexEnabled = true" + text[match.end():]

    path.write_text(text, encoding="utf-8")


def patch_groovy(path: Path) -> None:
    text = path.read_text(encoding="utf-8")

    if "coreLibraryDesugaringEnabled" not in text:
        match = re.search(r"(?m)^\s*compileOptions\s*\{", text)
        if match:
            text = text[:match.end()] + "\n        coreLibraryDesugaringEnabled true" + text[match.end():]
        else:
            match = re.search(r"(?m)^android\s*\{", text)
            if not match:
                fail(f"Could not find android {{ block in {path}")
            text = text[:match.end()] + (
                "\n    compileOptions {\n"
                "        coreLibraryDesugaringEnabled true\n"
                "    }\n"
            ) + text[match.end():]

    if "coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs" not in text and \
       'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs' not in text:
        match = re.search(r"(?m)^dependencies\s*\{", text)
        if not match:
            text += (
                "\n\ndependencies {\n"
                "    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n"
                "}\n"
            )
        else:
            text = text[:match.end()] + (
                "\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'"
            ) + text[match.end():]

    if "multiDexEnabled" not in text:
        match = re.search(r"(?m)^\s*defaultConfig\s*\{", text)
        if match:
            text = text[:match.end()] + "\n        multiDexEnabled true" + text[match.end():]

    path.write_text(text, encoding="utf-8")


def main() -> None:
    kts = APP / "build.gradle.kts"
    groovy = APP / "build.gradle"
    if kts.is_file():
        patch_kts(kts)
        print(f"Updated {kts.relative_to(ROOT)}")
    elif groovy.is_file():
        patch_groovy(groovy)
        print(f"Updated {groovy.relative_to(ROOT)}")
    else:
        fail("Neither android/app/build.gradle.kts nor android/app/build.gradle exists")


if __name__ == "__main__":
    main()
