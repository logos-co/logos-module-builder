#pragma once

#include "logos_module_context.h"

#include <string>

class PlainFixtureImpl : public LogosModuleContext
{
public:
    std::string echo(const std::string& value);
};
