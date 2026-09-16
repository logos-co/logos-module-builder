#pragma once

#include <string>
#include "logos_module_context.h"

class ExtlibFlakeImpl : public LogosModuleContext
{
public:
    std::string greet(const std::string& name);
};
