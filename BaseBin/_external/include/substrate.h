/* Cydia Substrate - Powerful Code Insertion Platform
 * Copyright (C) 2008-2019  Jay Freeman (saurik)
*/

/*
 *        Redistribution and use in source and binary
 * forms, with or without modification, are permitted
 * provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the
 *    above copyright notice, this list of conditions
 *    and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the
 *    above copyright notice, this list of conditions
 *    and the following disclaimer in the documentation
 *    and/or other materials provided with the
 *    distribution.
 * 3. The name of the author may not be used to endorse
 *    or promote products derived from this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS''
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING,
 * BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 * NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
 * TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
 * ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 * ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#ifndef SUBSTRATE_H_
#define SUBSTRATE_H_

#ifdef __APPLE__
#ifdef __cplusplus
extern "C" {
#endif
#include <mach-o/nlist.h>
#ifdef __cplusplus
}
#endif

#include <objc/runtime.h>
#include <objc/message.h>
#endif

#include <stdbool.h>
#include <stdlib.h>

#include <sys/types.h>

#define _finline \
    inline __attribute__((__always_inline__))
#define _disused \
    __attribute__((__unused__))

#ifdef __cplusplus
#define _default(value) = value
#else
#define _default(value)
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef const struct MSImage *MSImageRef;

#ifdef __APPLE__
#ifndef __LP64__
typedef struct mach_header MSImageHeader;
#else
typedef struct mach_header_64 MSImageHeader;
#endif
#else
typedef void MSImageHeader;
#endif

MSImageRef MSMapImage(const char *file);
const MSImageHeader *MSImageAddress(MSImageRef image);
void MSCloseImage(MSImageRef);

MSImageRef MSGetImageByName(const char *file);

void *MSFindSymbol(MSImageRef image, const char *name);
char *MSFindAddress(MSImageRef image, void **address);

void MSHookFunction(void *symbol, void *replace, void **result);
void MSHookMemory(void *target, const void *data, size_t size);

#ifdef __APPLE__
#ifdef __arm__
__attribute__((__deprecated__))
IMP MSHookMessage(Class _class, SEL sel, IMP imp, const char *prefix _default(NULL));
#endif
void MSHookMessageEx(Class _class, SEL sel, IMP imp, IMP *result);
void MSHookClassPair(Class target, Class hook, Class old);
#endif

#ifdef __ANDROID__
#include <jni.h>
void MSJavaHookClassLoad(JNIEnv *jni, const char *name, void (*callback)(JNIEnv *, jclass, void *), void *data _default(NULL));
void MSJavaHookMethod(JNIEnv *jni, jclass _class, jmethodID methodID, void *function, void **result);
void MSJavaBlessClassLoader(JNIEnv *jni, jobject loader);

typedef struct MSJavaObjectKey_ *MSJavaObjectKey;
MSJavaObjectKey MSJavaCreateObjectKey();
void MSJavaReleaseObjectKey(MSJavaObjectKey key);
void *MSJavaGetObjectKey(JNIEnv *jni, jobject object, MSJavaObjectKey key);
void MSJavaSetObjectKey(JNIEnv *jni, jobject object, MSJavaObjectKey key, void *value, void (*clean)(void *, JNIEnv *, void *) _default(NULL), void *data _default(NULL));
#endif

#ifdef __cplusplus
}
#endif

#ifdef __APPLE__

#define MSHookInterface(target, hook, base) \
@class target; \
@interface $ ## hook : base { target *$self; } @end \
@implementation $ ## hook \
+ (void) initialize {} \
@end \
@interface hook : $ ## hook @end \
@implementation hook (MS) + (void) load { \
    MSHookClassPair(objc_getClass(#target), self, class_getSuperclass(self)); \
} @end

#define MSSelf ((__typeof__($self)) self)

#endif

#ifdef __cplusplus

#ifdef __APPLE__

namespace etl {

template <unsigned Case_>
struct Case {
    static char value[Case_ + 1];
};

typedef Case<true> Yes;
typedef Case<false> No;

namespace be {
    template <typename Checked_>
    static Yes CheckClass_(void (Checked_::*)());

    template <typename Checked_>
    static No CheckClass_(...);
}

template <typename Type_>
struct IsClass {
    void gcc32();

    static const bool value = (sizeof(be::CheckClass_<Type_>(0).value) == sizeof(Yes::value));
};

}

#ifdef __arm__
template <typename Type_>
__attribute__((__deprecated__))
static inline Type_ *MSHookMessage(Class _class, SEL sel, Type_ *imp, const char *prefix = NULL) {
    return reinterpret_cast<Type_ *>(MSHookMessage(_class, sel, reinterpret_cast<IMP>(imp), prefix));
}
#endif

template <typename Type_>
static inline void MSHookMessage(Class _class, SEL sel, Type_ *imp, Type_ **result) {
    return MSHookMessageEx(_class, sel, reinterpret_cast<IMP>(imp), reinterpret_cast<IMP *>(result));
}

template <typename Type_>
static inline Type_ &MSHookIvar(id self, const char *name) {
    Ivar ivar(class_getInstanceVariable(object_getClass(self), name));
    void *pointer(ivar == NULL ? NULL : reinterpret_cast<char *>(
#if __has_feature(objc_arc)
        (__bridge void *)
#endif
    self) + ivar_getOffset(ivar));
    return *reinterpret_cast<Type_ *>(pointer);
}

#define MSAddMessage0(_class, type, arg0) \
    class_addMethod($ ## _class, @selector(arg0), (IMP) &$ ## _class ## $ ## arg0, type);
#define MSAddMessage1(_class, type, arg0) \
    class_addMethod($ ## _class, @selector(arg0:), (IMP) &$ ## _class ## $ ## arg0 ## $, type);
#define MSAddMessage2(_class, type, arg0, arg1) \
    class_addMethod($ ## _class, @selector(arg0:arg1:), (IMP) &$ ## _class ## $ ## arg0 ## $ ## arg1 ## $, type);
#define MSAddMessage3(_class, type, arg0, arg1, arg2) \
    class_addMethod($ ## _class, @selector(arg0:arg1:arg2:), (IMP) &$ ## _class ## $ ## arg0 ## $ ## arg1 ## $ ## arg2 ## $, type);
#define MSAddMessage4(_class, type, arg0, arg1, arg2, arg3) \
    class_addMethod($ ## _class, @selector(arg0:arg1:arg2:arg3:), (IMP) &$ ## _class ## $ ## arg0 ## $ ## arg1 ## $ ## arg2 ## $ ## arg3 ## $, type);
#define MSAddMessage5(_class, type, arg0, arg1, arg2, arg3, arg4) \
    class_addMethod($ ## _class, @selector(arg0:arg1:arg2:arg3:arg4:), (IMP) &$ ## _class ## $ ## arg0 ## $ ## arg1 ## $ ## arg2 ## $ ## arg3 ## $ ## arg4 ## $, type);
#define MSAddMessage6(_class, type, arg0, arg1, arg2, arg3, arg4, arg5) \
    class_addMethod($ ## _class, @selector(arg0:arg1:arg2:arg3:arg4:arg5:), (IMP) &$ ## _class ## $ ## arg0 ## $ ## arg1 ## $ ## arg2 ## $ ## arg3 ## $ ## arg4 ## $ ## arg5 ## $, type);
#define MSAddMessage7(_class, type, arg0, arg1, arg2, arg3, arg4, arg5, arg6) \
    class_addMethod($ ## _class, @selector(arg0:arg1:arg2:arg3:arg4:arg5:arg6:), (IMP) &$ ## _class ## $ ## arg0 ## $ ## arg1 ## $ ## arg2 ## $ ## arg3 ## $ ## arg4 ## $ ## arg5 ## $ $$ arg6 ## $, type);
#define MSAddMessage8(_class, type, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7) \
    class_addMethod($ ## _class, @selector(arg0:arg1:arg2:arg3:arg4:arg5:arg6:arg7:), (IMP) &$ ## _class ## $ ## arg0 ## $ ## arg1 ## $ ## arg2 ## $ ## arg3 ## $ ## arg4 ## $ ## arg5 ## $ $$ arg6 ## $ ## arg7 ## $, type);

#define MSHookMessage0(_class, arg0) \
    MSHookMessage($ ## _class, @selector(arg0), MSHake(_class ## $ ## arg0))
#define MSHookMessage1(_class, arg0) \
    MSHookMessage($ ## _class, @selector(arg0:), MSHake(_class ## $ ## arg0 ## $))
#define MSHookMessage2(_class, arg0, arg1) \
    MSHookMessage($ ## _class, @selector(arg0:arg1:), MSHake(_class ## $ ## arg0 ## $ ## arg1 ## $))
#define MSHookMessage3(_class, arg0, arg1, arg2) \
    MSHookMessage($ ## _class, @selector(arg0:arg1:arg2:), MSHake(_class ## $ ## arg0 ## $ ## arg1 ## $ ## arg2 ## $))
#define MSHookMessage4(_class, arg0, arg1, arg2, arg3) \
    MSHookMessage($ ## _class, @selector(arg0:arg1:arg2:arg3:), MSHake(_class ## $ ## arg0 ## $ ## arg1 ## $ ## arg2 ## $ ## arg3 ## $))
#define MSHookMessage5(_class, arg0, arg1, arg2, arg3, arg4) \
    MSHookMessage($ ## _class, @selector(arg0:arg1:arg2:arg3:arg4:), MSHake(_class ## $ ## arg0 ## $ ## arg1 ## $ ## arg2 ## $ ## arg3 ## $ ## arg4 ## $))
#define MSHookMessage6(_class, arg0, arg1, arg2, arg3, arg4, arg5) \
    MSHookMessage($ ## _class, @selector(arg0:arg1:arg2:arg3:arg4:arg5:), MSHake(_class ## $ ## arg0 ## $ ## arg1 ## $ ## arg2 ## $ ## arg3 ## $ ## arg4 ## $ ## arg5 ## $))
#define MSHookMessage7(_class, arg0, arg1, arg2, arg3, arg4, arg5, arg6) \
    MSHookMessage($ ## _class, @selector(arg0:arg1:arg2:arg3:arg4:arg5:arg6:), MSHake(_class ## $ ## arg0 ## $ ## arg1 ## $ ## arg2 ## $ ## arg3 ## $ ## arg4 ## $ ## arg5 ## $ ## arg6 ## $))
#define MSHookMessage8(_class, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7) \
    MSHookMessage($ ## _class, @selector(arg0:arg1:arg2:arg3:arg4:arg5:arg6:arg7:), MSHake(_class ## $ ## arg0 ## $ ## arg1 ## $ ## arg2 ## $ ## arg3 ## $ ## arg4 ## $ ## arg5 ## $ ## arg6 ## $ ## arg7 ## $))

#define MSRegister_(name, dollar, colon) \
    namespace { static class C_$ ## name ## $ ## dollar { public: _finline C_$ ## name ## $ ##dollar() { \
        MSHookMessage($ ## name, @selector(colon), MSHake(name ## $ ## dollar)); \
    } } V_$ ## name ## $ ## dollar; } \

#define MSIgnore_(name, dollar, colon)

#ifdef __arm64__
#define MS_objc_msgSendSuper_stret objc_msgSendSuper
#else
#define MS_objc_msgSendSuper_stret objc_msgSendSuper_stret
#endif

#define MSMessage_(extra, type, _class, name, dollar, colon, call, args...) \
    static type _$ ## name ## $ ## dollar(Class _cls, type (*_old)(_class, SEL, ## args, ...), type (*_spr)(struct objc_super *, SEL, ## args, ...), _class self, SEL _cmd, ## args); \
    MSHook(type, name ## $ ## dollar, _class self, SEL _cmd, ## args) { \
        Class const _cls($ ## name); \
        type (* const _old)(_class, SEL, ## args, ...) = reinterpret_cast<type (* const)(_class, SEL, ## args, ...)>(_ ## name ## $ ## dollar); \
        typedef type (*msgSendSuper_t)(struct objc_super *, SEL, ## args, ...); \
        msgSendSuper_t const _spr(::etl::IsClass<type>::value ? reinterpret_cast<msgSendSuper_t>(&MS_objc_msgSendSuper_stret) : reinterpret_cast<msgSendSuper_t>(&objc_msgSendSuper)); \
        return _$ ## name ## $ ## dollar call; \
    } \
    extra(name, dollar, colon) \
    static _finline type _$ ## name ## $ ## dollar(Class _cls, type (*_old)(_class, SEL, ## args, ...), type (*_spr)(struct objc_super *, SEL, ## args, ...), _class self, SEL _cmd, ## args)

/* for((x=1;x!=7;++x)){ echo -n "#define MSMessage${x}_(extra, type, _class, name";for((y=0;y!=x;++y));do echo -n ", sel$y";done;for((y=0;y!=x;++y));do echo -n ", type$y, arg$y";done;echo ") \\";echo -n "    MSMessage_(extra, type, _class, name,";for((y=0;y!=x;++y));do if [[ $y -ne 0 ]];then echo -n " ##";fi;echo -n " sel$y ## $";done;echo -n ", ";for((y=0;y!=x;++y));do echo -n "sel$y:";done;echo -n ", (_cls, _old, _spr, self, _cmd";for((y=0;y!=x;++y));do echo -n ", arg$y";done;echo -n ")";for((y=0;y!=x;++y));do echo -n ", type$y arg$y";done;echo ")";} */

#define MSMessage0_(extra, type, _class, name, sel0) \
    MSMessage_(extra, type, _class, name, sel0, sel0, (_cls, _old, _spr, self, _cmd))
#define MSMessage1_(extra, type, _class, name, sel0, type0, arg0) \
    MSMessage_(extra, type, _class, name, sel0 ## $, sel0:, (_cls, _old, _spr, self, _cmd, arg0), type0 arg0)
#define MSMessage2_(extra, type, _class, name, sel0, sel1, type0, arg0, type1, arg1) \
    MSMessage_(extra, type, _class, name, sel0 ## $ ## sel1 ## $, sel0:sel1:, (_cls, _old, _spr, self, _cmd, arg0, arg1), type0 arg0, type1 arg1)
#define MSMessage3_(extra, type, _class, name, sel0, sel1, sel2, type0, arg0, type1, arg1, type2, arg2) \
    MSMessage_(extra, type, _class, name, sel0 ## $ ## sel1 ## $ ## sel2 ## $, sel0:sel1:sel2:, (_cls, _old, _spr, self, _cmd, arg0, arg1, arg2), type0 arg0, type1 arg1, type2 arg2)
#define MSMessage4_(extra, type, _class, name, sel0, sel1, sel2, sel3, type0, arg0, type1, arg1, type2, arg2, type3, arg3) \
    MSMessage_(extra, type, _class, name, sel0 ## $ ## sel1 ## $ ## sel2 ## $ ## sel3 ## $, sel0:sel1:sel2:sel3:, (_cls, _old, _spr, self, _cmd, arg0, arg1, arg2, arg3), type0 arg0, type1 arg1, type2 arg2, type3 arg3)
#define MSMessage5_(extra, type, _class, name, sel0, sel1, sel2, sel3, sel4, type0, arg0, type1, arg1, type2, arg2, type3, arg3, type4, arg4) \
    MSMessage_(extra, type, _class, name, sel0 ## $ ## sel1 ## $ ## sel2 ## $ ## sel3 ## $ ## sel4 ## $, sel0:sel1:sel2:sel3:sel4:, (_cls, _old, _spr, self, _cmd, arg0, arg1, arg2, arg3, arg4), type0 arg0, type1 arg1, type2 arg2, type3 arg3, type4 arg4)
#define MSMessage6_(extra, type, _class, name, sel0, sel1, sel2, sel3, sel4, sel5, type0, arg0, type1, arg1, type2, arg2, type3, arg3, type4, arg4, type5, arg5) \
    MSMessage_(extra, type, _class, name, sel0 ## $ ## sel1 ## $ ## sel2 ## $ ## sel3 ## $ ## sel4 ## $ ## sel5 ## $, sel0:sel1:sel2:sel3:sel4:sel5:, (_cls, _old, _spr, self, _cmd, arg0, arg1, arg2, arg3, arg4, arg5), type0 arg0, type1 arg1, type2 arg2, type3 arg3, type4 arg4, type5 arg5)
#define MSMessage7_(extra, type, _class, name, sel0, sel1, sel2, sel3, sel4, sel5, sel6, type0, arg0, type1, arg1, type2, arg2, type3, arg3, type4, arg4, type5, arg5, type6, arg6) \
    MSMessage_(extra, type, _class, name, sel0 ## $ ## sel1 ## $ ## sel2 ## $ ## sel3 ## $ ## sel4 ## $ ## sel5 ## $ ## sel6 ## $, sel0:sel1:sel2:sel3:sel4:sel5:sel6:, (_cls, _old, _spr, self, _cmd, arg0, arg1, arg2, arg3, arg4, arg5, arg6), type0 arg0, type1 arg1, type2 arg2, type3 arg3, type4 arg4, type5 arg5, type6 arg6)
#define MSMessage8_(extra, type, _class, name, sel0, sel1, sel2, sel3, sel4, sel5, sel6, sel7, type0, arg0, type1, arg1, type2, arg2, type3, arg3, type4, arg4, type5, arg5, type6, arg6, type7, arg7) \
    MSMessage_(extra, type, _class, name, sel0 ## $ ## sel1 ## $ ## sel2 ## $ ## sel3 ## $ ## sel4 ## $ ## sel5 ## $ ## sel6 ## $ ## sel7 ## $, sel0:sel1:sel2:sel3:sel4:sel5:sel6:sel7:, (_cls, _old, _spr, self, _cmd, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7), type0 arg0, type1 arg1, type2 arg2, type3 arg3, type4 arg4, type5 arg5, type6 arg6, type7 arg7)

#define MSInstanceMessage0(type, _class, args...) MSMessage0_(MSIgnore_, type, _class *, _class, ## args)
#define MSInstanceMessage1(type, _class, args...) MSMessage1_(MSIgnore_, type, _class *, _class, ## args)
#define MSInstanceMessage2(type, _class, args...) MSMessage2_(MSIgnore_, type, _class *, _class, ## args)
#define MSInstanceMessage3(type, _class, args...) MSMessage3_(MSIgnore_, type, _class *, _class, ## args)
#define MSInstanceMessage4(type, _class, args...) MSMessage4_(MSIgnore_, type, _class *, _class, ## args)
#define MSInstanceMessage5(type, _class, args...) MSMessage5_(MSIgnore_, type, _class *, _class, ## args)
#define MSInstanceMessage6(type, _class, args...) MSMessage6_(MSIgnore_, type, _class *, _class, ## args)
#define MSInstanceMessage7(type, _class, args...) MSMessage7_(MSIgnore_, type, _class *, _class, ## args)
#define MSInstanceMessage8(type, _class, args...) MSMessage8_(MSIgnore_, type, _class *, _class, ## args)

#define MSClassMessage0(type, _class, args...) MSMessage0_(MSIgnore_, type, Class, $ ## _class, ## args)
#define MSClassMessage1(type, _class, args...) MSMessage1_(MSIgnore_, type, Class, $ ## _class, ## args)
#define MSClassMessage2(type, _class, args...) MSMessage2_(MSIgnore_, type, Class, $ ## _class, ## args)
#define MSClassMessage3(type, _class, args...) MSMessage3_(MSIgnore_, type, Class, $ ## _class, ## args)
#define MSClassMessage4(type, _class, args...) MSMessage4_(MSIgnore_, type, Class, $ ## _class, ## args)
#define MSClassMessage5(type, _class, args...) MSMessage5_(MSIgnore_, type, Class, $ ## _class, ## args)
#define MSClassMessage6(type, _class, args...) MSMessage6_(MSIgnore_, type, Class, $ ## _class, ## args)
#define MSClassMessage7(type, _class, args...) MSMessage7_(MSIgnore_, type, Class, $ ## _class, ## args)
#define MSClassMessage8(type, _class, args...) MSMessage8_(MSIgnore_, type, Class, $ ## _class, ## args)

#define MSInstanceMessageHook0(type, _class, args...) MSMessage0_(MSRegister_, type, _class *, _class, ## args)
#define MSInstanceMessageHook1(type, _class, args...) MSMessage1_(MSRegister_, type, _class *, _class, ## args)
#define MSInstanceMessageHook2(type, _class, args...) MSMessage2_(MSRegister_, type, _class *, _class, ## args)
#define MSInstanceMessageHook3(type, _class, args...) MSMessage3_(MSRegister_, type, _class *, _class, ## args)
#define MSInstanceMessageHook4(type, _class, args...) MSMessage4_(MSRegister_, type, _class *, _class, ## args)
#define MSInstanceMessageHook5(type, _class, args...) MSMessage5_(MSRegister_, type, _class *, _class, ## args)
#define MSInstanceMessageHook6(type, _class, args...) MSMessage6_(MSRegister_, type, _class *, _class, ## args)
#define MSInstanceMessageHook7(type, _class, args...) MSMessage7_(MSRegister_, type, _class *, _class, ## args)
#define MSInstanceMessageHook8(type, _class, args...) MSMessage8_(MSRegister_, type, _class *, _class, ## args)

#define MSClassMessageHook0(type, _class, args...) MSMessage0_(MSRegister_, type, Class, $ ## _class, ## args)
#define MSClassMessageHook1(type, _class, args...) MSMessage1_(MSRegister_, type, Class, $ ## _class, ## args)
#define MSClassMessageHook2(type, _class, args...) MSMessage2_(MSRegister_, type, Class, $ ## _class, ## args)
#define MSClassMessageHook3(type, _class, args...) MSMessage3_(MSRegister_, type, Class, $ ## _class, ## args)
#define MSClassMessageHook4(type, _class, args...) MSMessage4_(MSRegister_, type, Class, $ ## _class, ## args)
#define MSClassMessageHook5(type, _class, args...) MSMessage5_(MSRegister_, type, Class, $ ## _class, ## args)
#define MSClassMessageHook6(type, _class, args...) MSMessage6_(MSRegister_, type, Class, $ ## _class, ## args)
#define MSClassMessageHook7(type, _class, args...) MSMessage7_(MSRegister_, type, Class, $ ## _class, ## args)
#define MSClassMessageHook8(type, _class, args...) MSMessage8_(MSRegister_, type, Class, $ ## _class, ## args)

#define MSOldCall(args...) \
    _old(self, _cmd, ## args)
#define MSSuperCall(args...) \
    _spr((struct objc_super[1]) {{self, class_getSuperclass(_cls)}}, _cmd, ## args)

#define MSIvarHook(type, name) \
    type &name(MSHookIvar<type>(self, #name))

#define MSClassHook(name) \
    @class name; \
    static Class $ ## name = objc_getClass(#name);
#define MSMetaClassHook(name) \
    @class name; \
    static Class $$ ## name = object_getClass($ ## name);

#endif/*__APPLE__*/

template <typename Type_>
static inline void MSHookFunction(Type_ *symbol, Type_ *replace, Type_ **result) {
    return MSHookFunction(
        reinterpret_cast<void *>(symbol),
        reinterpret_cast<void *>(replace),
        reinterpret_cast<void **>(result)
    );
}

template <typename Type_>
static inline void MSHookFunction(Type_ *symbol, Type_ *replace) {
    return MSHookFunction(symbol, replace, reinterpret_cast<Type_ **>(NULL));
}

template <typename Type_>
static inline void MSHookSymbol(Type_ *&value, const char *name, MSImageRef image = NULL) {
    value = reinterpret_cast<Type_ *>(MSFindSymbol(image, name));
}

template <typename Type_>
static inline void MSHookFunction(const char *name, Type_ *replace, Type_ **result = NULL) {
    Type_ *symbol;
    MSHookSymbol(symbol, name);
    return MSHookFunction(symbol, replace, result);
}

template <typename Type_>
static inline void MSHookFunction(MSImageRef image, const char *name, Type_ *replace, Type_ **result = NULL) {
    Type_ *symbol;
    MSHookSymbol(symbol, name, image);
    return MSHookFunction(symbol, replace, result);
}

template <typename Type_>
static inline void MSHookMemory(Type_ *target, const void *data, size_t size) {
    return MSHookMemory(reinterpret_cast<void *>(target), data, size);
}

#endif

// g++ versions before 4.7 define __cplusplus to 1
// http://gcc.gnu.org/bugzilla/show_bug.cgi?id=1773
#if __cplusplus >= 201103L || defined(__GXX_EXPERIMENTAL_CXX0X__)

#ifdef __ANDROID__

template <typename Type_, typename Kind_, typename... Args_>
static inline void MSJavaHookMethod(JNIEnv *jni, jclass _class, jmethodID method, Type_ (*replace)(JNIEnv *, Kind_, Args_...), Type_ (**result)(JNIEnv *, Kind_, ...)) {
    return MSJavaHookMethod(
        jni, _class, method,
        reinterpret_cast<void *>(replace),
        reinterpret_cast<void **>(result)
    );
}

#endif

#endif

#ifdef __ANDROID__

#ifdef __cplusplus

static inline void MSAndroidGetPackage(JNIEnv *jni, jobject global, const char *name, jobject &local, jobject &loader) {
    jclass Context(jni->FindClass("android/content/Context"));
    jmethodID Context$createPackageContext(jni->GetMethodID(Context, "createPackageContext", "(Ljava/lang/String;I)Landroid/content/Context;"));
    jmethodID Context$getClassLoader(jni->GetMethodID(Context, "getClassLoader", "()Ljava/lang/ClassLoader;"));

    jstring string(jni->NewStringUTF(name));
    local = jni->CallObjectMethod(global, Context$createPackageContext, string, 3);
    loader = jni->CallObjectMethod(local, Context$getClassLoader);
}

static inline jclass MSJavaFindClass(JNIEnv *jni, jobject loader, const char *name) {
    jclass Class(jni->FindClass("java/lang/Class"));
    jmethodID Class$forName(jni->GetStaticMethodID(Class, "forName", "(Ljava/lang/String;ZLjava/lang/ClassLoader;)Ljava/lang/Class;"));

    jstring string(jni->NewStringUTF(name));
    jobject _class(jni->CallStaticObjectMethod(Class, Class$forName, string, JNI_TRUE, loader));

    if (jni->ExceptionCheck()) {
        jni->ExceptionClear();
        return NULL;
    }

    return reinterpret_cast<jclass>(_class);
}

_disused static void MSJavaCleanWeak(void *data, JNIEnv *jni, void *value) {
    jni->DeleteWeakGlobalRef(reinterpret_cast<jweak>(value));
}

#endif

#endif

#define MSHook(type, name, args...) \
    _disused static type (*_ ## name)(args); \
    static type $ ## name(args)

#define MSJavaHook(type, name, arg0, args...) \
    _disused static type (*_ ## name)(JNIEnv *jni, arg0, ...); \
    static type $ ## name(JNIEnv *jni, arg0, ## args)

#ifdef __cplusplus
#define MSHake(name) \
    &$ ## name, &_ ## name
#else
#define MSHake(name) \
    &$ ## name, (void **) &_ ## name
#endif

#define SubstrateConcat_(lhs, rhs) \
    lhs ## rhs
#define SubstrateConcat(lhs, rhs) \
    SubstrateConcat_(lhs, rhs)

#define SubstrateStringize(value) \
    #value

#ifdef __APPLE__
    #define SubstrateSection \
        __attribute__((__section__("__TEXT, __substrate")))
#else
    #define SubstrateSection \
        __attribute__((__section__(".substrate")))
#endif

#ifdef __APPLE__
#define MSFilterCFBundleID "Filter:CFBundleID"
#define MSFilterObjC_Class "Filter:ObjC.Class"
#endif

#ifdef __ANDROID__
#define MSFilterLibrary "Filter:Library"
#endif

#define MSFilterCFVersion "Filter:CFVersion"
#define MSFilterExecutable "Filter:Executable"

#define MSConfig(name, value) \
    extern const char SubstrateConcat(_substrate_, __LINE__)[] SubstrateSection; \
    const char SubstrateConcat(_substrate_, __LINE__)[] SubstrateSection = name "=" value;

#define MSConfigValue(name, value) \
    char SubstrateConcat(_substrate_MSConfigValue_Invalid_, __LINE__)[((double)value, 0)]; \
    const char SubstrateConcat(_substrate_, __LINE__)[] SubstrateSection = name "=" SubstrateStringize(value);

#define MSConfigRange(name, lo, hi) \
    char SubstrateConcat(_substrate_MSConfigRange_Invalid_, __LINE__)[(double)lo <= (double)hi ? 0 : -1]; \
    MSConfig(name, SubstrateStringize(lo) "," SubstrateStringize(hi))

#ifdef __cplusplus
#define MSInitialize \
    static void SubstrateConcat(_MSInitialize, __LINE__)(void); \
    namespace { static class SubstrateConcat($MSInitialize, __LINE__) { public: _finline SubstrateConcat($MSInitialize, __LINE__)() { \
        SubstrateConcat(_MSInitialize, __LINE__)(); \
    } } SubstrateConcat($MSInitialize, __LINE__); } \
    static void SubstrateConcat(_MSInitialize, __LINE__)()
#else
#define MSInitialize \
    __attribute__((__constructor__)) static void SubstrateConcat(_MSInitialize, __LINE__)(void)
#endif

#define Foundation_f "/System/Library/Frameworks/Foundation.framework/Foundation"
#define UIKit_f "/System/Library/Frameworks/UIKit.framework/UIKit"
#define JavaScriptCore_f "/System/Library/PrivateFrameworks/JavaScriptCore.framework/JavaScriptCore"
#define IOKit_f "/System/Library/Frameworks/IOKit.framework/IOKit"

#endif//SUBSTRATE_H_
