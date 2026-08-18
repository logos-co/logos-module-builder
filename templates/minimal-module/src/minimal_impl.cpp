#include "minimal_impl.h"

// LOGOS_MODULE_VERSION is defined by logos_module() from metadata.json's
// `version` field (or an explicit VERSION argument in CMakeLists.txt).
// The fallback keeps IDEs and standalone compiles working.
#ifndef LOGOS_MODULE_VERSION
#define LOGOS_MODULE_VERSION "0.0.0-dev"
#endif

std::string MinimalImpl::greet(const std::string& name)
{
    std::string greeting = "Hello, " + name + "! Greetings from the minimal module.";

    // The generated event body routes the typed payload to every subscriber.
    greeted(greeting);

    return greeting;
}

std::string MinimalImpl::getStatus()
{
    return "Minimal module v" LOGOS_MODULE_VERSION " is running.";
}
