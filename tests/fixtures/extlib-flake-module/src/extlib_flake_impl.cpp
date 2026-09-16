#include "extlib_flake_impl.h"
#include "greeting.h"

std::string ExtlibFlakeImpl::greet(const std::string& name)
{
    return greetingFor(name);
}
