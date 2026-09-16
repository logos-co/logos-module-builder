#include "runtime_lib_probe_impl.h"

#include <jansson.h>

std::string RuntimeLibProbeImpl::janssonVersion()
{
    return jansson_version_str();
}
