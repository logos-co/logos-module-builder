#pragma once

#include <string>
#include "logos_module_context.h"

class OptionalConsumerImpl : public LogosModuleContext
{
public:
    std::string greetViaMinimal(const std::string& name);
};
