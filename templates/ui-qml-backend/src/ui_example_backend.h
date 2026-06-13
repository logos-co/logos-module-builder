#pragma once

#include "rep_ui_example_source.h"
#include "logos_module_context.h"

/**
 * @brief The hand-written UI backend (universal authoring model).
 *
 * You write only this class and the `.rep` view contract. The `*Plugin` and
 * `*Interface` classes — `Q_PLUGIN_METADATA`, `initLogos` wiring, QtRO
 * registration — are generated around it.
 *
 * It derives:
 *   - `UiExampleSimpleSource` — generated from ui_example.rep; implement its
 *     slots and feed its PROPs (e.g. `setStatus(...)`), which auto-sync to
 *     every QML replica.
 *   - `LogosModuleContext` — gives `onContextReady()` plus `modules()`, the
 *     typed callers and event subscriptions for any `dependencies` you declare
 *     (none here; see the typed-backend doc-test for a worked example).
 */
class UiExampleBackend : public UiExampleSimpleSource,
                         public LogosModuleContext
{
public:
    int add(int a, int b) override;
};
