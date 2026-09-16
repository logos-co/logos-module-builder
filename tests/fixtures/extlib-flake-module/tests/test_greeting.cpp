#include <logos_test.h>
#include "greeting.h"

LOGOS_TEST(greeting_comes_from_both_archives) {
    LOGOS_ASSERT_EQ(greetingFor("logos"), std::string("hello, logos (v1.0.0)"));
}
