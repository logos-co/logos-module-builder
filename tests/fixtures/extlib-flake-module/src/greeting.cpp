#include "greeting.h"

// Nested headers: staged under lib/extfixture/, or read from the package root.
#include <extfixture/extfixture.hpp>
#include <extfixture/extfixture_c.h>

std::string greetingFor(const std::string& name)
{
    return extfixture::greeting(name) + " (v" + extfixture_c_version() + ")";
}
