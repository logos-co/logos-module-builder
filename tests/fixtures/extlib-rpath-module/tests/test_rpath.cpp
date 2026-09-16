#include <logos_test.h>
#include "rpatha.h"
#include "rpathb.h"

LOGOS_TEST(calls_both_external_libraries) {
    LOGOS_ASSERT_EQ(rpatha_value(), 1);
    LOGOS_ASSERT_EQ(rpathb_value(), 2);
}
