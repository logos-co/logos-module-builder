#pragma once

#include "rep_ui_example_source.h"
#include "logos_module_context.h"

/**
 * @brief The hand-written UI backend (universal authoring model).
 *
 * You write only this class and the `.rep` view contract. With
 * `"backend": "module"` in metadata.json it runs as the core module
 * `ui_example_backend`; the plugin glue around it — `Q_PLUGIN_METADATA`,
 * `initLogos` wiring, the private channel to the view — is generated.
 *
 * It derives:
 *   - `UiExampleSimpleSource` — generated from ui_example.rep; implement its
 *     slots and feed its PROPs (e.g. `setStatus(...)`), which auto-sync to
 *     every QML replica.
 *   - `LogosModuleContext` — what every C++ core module derives: `modules()`
 *     (Qt-typed callers and event subscriptions for the `dependencies` you
 *     declare; none here), `onContextReady()`, `instancePersistencePath()` (the
 *     module's data folder) and `aboutToUnload()` (runs when the app closes).
 */
class UiExampleBackend : public UiExampleSimpleSource,
                         public LogosModuleContext
{
public:
    int add(int a, int b) override;

private:
    // Named like the .rep's `status` property on purpose: the module glue must
    // publish the backend as its SimpleSource, or this hides the getter and the
    // backend does not compile.
    QString status(int a, int b, int result) const;
};
