// Checks djinni::FutureAdaptor in both directions. fromCpp: a failed C++ future rejects the DJFuture for every exception,
// an NSException of the conversion keeps its name and reason, and an exception of a downstream handler does not complete
// the DJPromise a second time. toCpp: a rejected DJFuture, also of NSNull, and an exception of the conversion reject the
// C++ future. Build and run the test with ci/objc-future-test.sh.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#include "Future_objc.hpp"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <stdexcept>
#include <string>

namespace {

int failures = 0;
int setExceptionCalls = 0;

void check(bool condition, const char* name, NSString* message) {
    if (!condition) {
        std::printf("FAIL: %s: %s\n", name, message.UTF8String);
        failures++;
    }
}

// Counts the calls of -[DJPromise setException:], so a case can see a second completion, which DJPromise ignores.
void countSetExceptionCalls() {
    Method method = class_getInstanceMethod([DJPromise class], @selector(setException:));
    auto original = reinterpret_cast<void (*)(id, SEL, NSException*)>(method_getImplementation(method));
    method_setImplementation(method, imp_implementationWithBlock(^(id self, NSException* exception) {
        setExceptionCalls++;
        original(self, @selector(setException:), exception);
    }));
}

// A nil name skips the check of the name.
void expectRejected(const char* name, DJFuture* future, NSString* reason, NSString* exceptionName = nil) {
    if (![future isReady]) {
        check(false, name, @"the future has no result");
        return;
    }
    NSException* actual = nil;
    @try {
        [future get];
    } @catch (NSException* e) {
        actual = e;
    }
    if (actual == nil) {
        check(false, name, @"the future resolved, but it must reject");
        return;
    }
    check([actual.reason isEqualToString:reason], name,
          [NSString stringWithFormat:@"reason '%@', expected '%@'", actual.reason, reason]);
    if (exceptionName != nil) {
        check([actual.name isEqualToString:exceptionName], name,
              [NSString stringWithFormat:@"name '%@', expected '%@'", actual.name, exceptionName]);
    }
}

template <typename T>
void expectCppRejected(const char* name, djinni::Future<T>& future, const std::string& what) {
    if (!future.isReady()) {
        check(false, name, @"the C++ future has no result");
        return;
    }
    try {
        future.get();
        check(false, name, @"the C++ future resolved, but it must reject");
    } catch (const std::exception& e) {
        check(what == e.what(), name, [NSString stringWithFormat:@"what() '%s', expected '%s'", e.what(), what.c_str()]);
    } catch (...) {
        check(false, name, @"the C++ future rejected with an exception outside std::exception");
    }
}

// toCpp throws a C++ exception, and fromCpp raises an NSException.
struct ThrowingMarshal {
    using CppType = int;
    using ObjcType = NSNumber*;
    using Boxed = ThrowingMarshal;

    static CppType toCpp(ObjcType) { throw std::runtime_error("toCpp failure"); }
    static ObjcType fromCpp(CppType) {
        [NSException raise:@"MarshalError" format:@"fromCpp failure"];
        return nil;
    }
};

// toCpp raises an NSException.
struct RaisingMarshal {
    using CppType = int;
    using ObjcType = NSNumber*;
    using Boxed = RaisingMarshal;

    static CppType toCpp(ObjcType) {
        [NSException raise:@"MarshalError" format:@"toCpp raised"];
        return 0;
    }
    static ObjcType fromCpp(CppType c) { return @(c); }
};

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

void conversionNSExceptionKeepsNameAndReason() {
    djinni::Promise<int> p;
    DJFuture* f = djinni::FutureAdaptor<ThrowingMarshal>::fromCpp(p.getFuture());
    p.setValue(1);
    expectRejected("nsexception-kept", f, @"fromCpp failure", @"MarshalError");
}

void downstreamThrowDoesNotCompleteTwice() {
    djinni::Promise<std::string> p;
    DJFuture* f = djinni::FutureAdaptor<djinni::String>::fromCpp(p.getFuture());
    __block id seen = nil;
    [f then:^id(DJFuture* r) {
        seen = [r get];
        throw std::runtime_error("handler failure");
    }];
    setExceptionCalls = 0;
    p.setValue("value");
    check([seen isEqual:@"value"], "downstream-throw", @"the handler did not get the value");
    check(setExceptionCalls == 0, "downstream-throw", @"setException: ran on a completed promise");
}

void rejectedVoidDJFutureRejectsCppFuture() {
    DJPromise* dp = [[DJPromise alloc] init];
    djinni::Future<void> cf = djinni::FutureAdaptor<djinni::Void>::toCpp([dp getFuture]);
    [dp setException:[NSException exceptionWithName:@"ObjcError" reason:@"objc failure" userInfo:nil]];
    expectCppRejected("void-tocpp-rejected", cf, "objc failure");
}

void rejectionWithoutReasonRejectsCppFuture() {
    DJPromise* dp = [[DJPromise alloc] init];
    djinni::Future<void> cf = djinni::FutureAdaptor<djinni::Void>::toCpp([dp getFuture]);
    [dp setException:[NSException exceptionWithName:@"ObjcError" reason:nil userInfo:nil]];
    expectCppRejected("tocpp-no-reason", cf, "ObjcError");
}

void conversionCppExceptionRejectsCppFuture() {
    DJPromise* dp = [[DJPromise alloc] init];
    djinni::Future<int> cf = djinni::FutureAdaptor<ThrowingMarshal>::toCpp([dp getFuture]);
    try {
        [dp setValue:@1];
    } catch (...) {
        check(false, "tocpp-cpp-exception", @"the exception of the conversion left setValue:");
        return;
    }
    expectCppRejected("tocpp-cpp-exception", cf, "toCpp failure");
}

void conversionNSExceptionRejectsCppFuture() {
    DJPromise* dp = [[DJPromise alloc] init];
    djinni::Future<int> cf = djinni::FutureAdaptor<RaisingMarshal>::toCpp([dp getFuture]);
    [dp setValue:@1];
    expectCppRejected("tocpp-nsexception", cf, "toCpp raised");
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
    {"nsexception-kept", conversionNSExceptionKeepsNameAndReason},
    {"downstream-throw", downstreamThrowDoesNotCompleteTwice},
    {"void-tocpp-rejected", rejectedVoidDJFutureRejectsCppFuture},
    {"tocpp-cpp-exception", conversionCppExceptionRejectsCppFuture},
    {"tocpp-nsexception", conversionNSExceptionRejectsCppFuture},
    {"tocpp-no-reason", rejectionWithoutReasonRejectsCppFuture},
};

} // namespace

// With no argument, the program runs every case. With the name of a case, it runs only that case.
int main(int argc, char** argv) {
    countSetExceptionCalls();
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
