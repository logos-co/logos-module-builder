#include "ui_example_backend.h"

// Generated umbrella: LogosModules (behind modules()) from
// metadata.json#dependencies — typed wrappers + typed event accessors.
// (No dependencies here, but include it once you add some.)
// #include "logos_sdk.h"

int UiExampleBackend::add(int a, int b)
{
    int result = a + b;
    // PROP from the .rep — QtRO pushes every setStatus to the QML replica.
    setStatus(status(a, b, result));
    return result;
}

QString UiExampleBackend::status(int a, int b, int result) const
{
    return QStringLiteral("%1 + %2 = %3").arg(a).arg(b).arg(result);
}
