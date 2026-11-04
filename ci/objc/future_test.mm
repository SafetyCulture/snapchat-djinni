// Checks djinni::FutureAdaptor::fromCpp: a failed C++ future rejects the DJFuture, for a std::exception, for an exception
// outside std::exception, and for a Future<void>. Build and run the test with ci/objc-future-test.sh.
#import <Foundation/Foundation.h>

#include "Future_objc.hpp"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <stdexcept>
#include <string>

namespace {

int failures = 0;

void check(bool condition, const char* name, NSString* message) {
    if (!condition) {
        std::printf("FAIL: %s: %s\n", name, message.UTF8String);
        failures++;
    }
}

// The handlers run when the promise completes, so a future that is not ready here never gets a result.
void expectRejected(const char* name, DJFuture* future, NSString* reason) {
    if (![future isReady]) {
        check(false, name, @"the future has no result");
        return;
    }
    NSString* actual = nil;
    @try {
        [future get];
    } @catch (NSException* e) {
        actual = e.reason;
    }
    if (actual == nil) {
        check(false, name, @"the future resolved, but it must reject");
        return;
    }
    check([actual isEqualToString:reason], name, [NSString stringWithFormat:@"reason '%@', expected '%@'", actual, reason]);
}

void stdExceptionRejectsWithWhat() {
    djinni::Promise<std::string> p;
    DJFuture* f = djinni::FutureAdaptor<djinni::String>::fromCpp(p.getFuture());
    p.setException(std::runtime_error("cpp failure"));
    expectRejected("std-exception", f, @"cpp failure");
}

void nonStdExceptionRejects() {
    djinni::Promise<std::string> p;
    DJFuture* f = djinni::FutureAdaptor<djinni::String>::fromCpp(p.getFuture());
    p.setException(std::make_exception_ptr(42));
    expectRejected("non-std-exception", f, @"unknown C++ exception");
}

void failedVoidFutureRejects() {
    djinni::Promise<void> p;
    DJFuture* f = djinni::FutureAdaptor<djinni::Void>::fromCpp(p.getFuture());
    p.setException(std::runtime_error("void failure"));
    expectRejected("void-std-exception", f, @"void failure");
}

void nonStdExceptionRejectsVoidFuture() {
    djinni::Promise<void> p;
    DJFuture* f = djinni::FutureAdaptor<djinni::Void>::fromCpp(p.getFuture());
    p.setException(std::make_exception_ptr(42));
    expectRejected("void-non-std-exception", f, @"unknown C++ exception");
}

void voidFutureResolves() {
    djinni::Promise<void> p;
    DJFuture* f = djinni::FutureAdaptor<djinni::Void>::fromCpp(p.getFuture());
    p.setValue();
    if (![f isReady]) {
        check(false, "void-value", @"the future has no result");
        return;
    }
    @try {
        check([f get] == [NSNull null], "void-value", @"the value is not NSNull");
    } @catch (NSException* e) {
        check(false, "void-value", [NSString stringWithFormat:@"rejected with '%@'", e.reason]);
    }
}

struct Case {
    const char* name;
    void (*run)();
};

const Case cases[] = {
    {"std-exception", stdExceptionRejectsWithWhat},
    {"non-std-exception", nonStdExceptionRejects},
    {"void-std-exception", failedVoidFutureRejects},
    {"void-non-std-exception", nonStdExceptionRejectsVoidFuture},
    {"void-value", voidFutureResolves},
};

} // namespace

// With no argument, the program runs every case. With the name of a case, it runs only that case.
int main(int argc, char** argv) {
    @autoreleasepool {
        bool found = false;
        for (const auto& c : cases) {
            if (argc < 2 || std::strcmp(argv[1], c.name) == 0) {
                found = true;
                c.run();
            }
        }
        if (!found) {
            std::printf("FAIL: no case '%s'\n", argv[1]);
            return EXIT_FAILURE;
        }
    }
    if (failures == 0) {
        std::printf("PASS\n");
    }
    return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
