#pragma once

#include <string>
#include "logos_module_context.h"

class RuntimeLibProbeImpl : public LogosModuleContext
{
public:
    std::string janssonVersion();
};
