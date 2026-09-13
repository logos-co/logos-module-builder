#include "optional_consumer_impl.h"
#include "logos_sdk.h"

std::string OptionalConsumerImpl::greetViaMinimal(const std::string& name)
{
    // Compiles against the typed wrapper generated from the optional dependency's contract.
    logos::CallError err;
    std::string out = modules().minimal.greet(name, &err, 2000);
    return err.ok() ? out : "ABSENT:" + err.code;
}
