#include <logos_test.h>
#include "calculator.h"

LOGOS_TEST(add_two_positive_numbers) {
    Calculator calc;
    LOGOS_ASSERT_EQ(calc.add(2, 3), 5);
}

LOGOS_TEST(add_negative_numbers) {
    Calculator calc;
    LOGOS_ASSERT_EQ(calc.add(-1, -2), -3);
}

LOGOS_TEST(multiply_returns_product) {
    Calculator calc;
    LOGOS_ASSERT_EQ(calc.multiply(4, 5), 20);
}

LOGOS_TEST(multiply_by_zero) {
    Calculator calc;
    LOGOS_ASSERT_EQ(calc.multiply(7, 0), 0);
}

LOGOS_TEST(isPositive_true_for_positive) {
    Calculator calc;
    LOGOS_ASSERT_TRUE(calc.isPositive(1));
}

LOGOS_TEST(isPositive_false_for_zero) {
    Calculator calc;
    LOGOS_ASSERT_FALSE(calc.isPositive(0));
}

LOGOS_TEST(isPositive_false_for_negative) {
    Calculator calc;
    LOGOS_ASSERT_FALSE(calc.isPositive(-5));
}

LOGOS_TEST(describe_positive) {
    Calculator calc;
    LOGOS_ASSERT_EQ(calc.describe(10), std::string("positive"));
}

LOGOS_TEST(describe_negative) {
    Calculator calc;
    LOGOS_ASSERT_EQ(calc.describe(-3), std::string("negative"));
}

LOGOS_TEST(describe_zero) {
    Calculator calc;
    LOGOS_ASSERT_EQ(calc.describe(0), std::string("zero"));
}
