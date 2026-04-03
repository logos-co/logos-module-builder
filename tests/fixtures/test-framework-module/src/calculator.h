#ifndef CALCULATOR_H
#define CALCULATOR_H

#include <string>

class Calculator {
public:
    int add(int a, int b) { return a + b; }
    int multiply(int a, int b) { return a * b; }
    bool isPositive(int n) { return n > 0; }
    std::string describe(int n) {
        if (n > 0) return "positive";
        if (n < 0) return "negative";
        return "zero";
    }
};

#endif
