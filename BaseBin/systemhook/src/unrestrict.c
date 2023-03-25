#import <CoreFoundation/CoreFoundation.h>
#import "common.h"
#import <stdio.h>

extern int64_t sandbox_extension_consume(const char *extension_token);

static void unsandbox(void)
{
	CFStringRef path = CFStringCreateWithCString(NULL, "/usr/lib/sandbox.plist", kCFStringEncodingUTF8);
    CFURLRef url = CFURLCreateWithFileSystemPath(NULL, path, kCFURLPOSIXPathStyle, false);
    CFReadStreamRef stream = CFReadStreamCreateWithFile(NULL, url);
    if (CFReadStreamOpen(stream)) {
        CFErrorRef error = NULL;
        CFPropertyListRef plist = CFPropertyListCreateWithStream(NULL, stream, 0, kCFPropertyListImmutable, NULL, &error);
        if (plist != NULL && CFGetTypeID(plist) == CFDictionaryGetTypeID()) {
            CFArrayRef array = CFDictionaryGetValue(plist, CFSTR("extensions"));
            if (array != NULL && CFGetTypeID(array) == CFArrayGetTypeID()) {
                CFIndex count = CFArrayGetCount(array);
                for (CFIndex i = 0; i < count; i++) {
                    CFStringRef stringRef = CFArrayGetValueAtIndex(array, i);
                    const char *extensionToken = CFStringGetCStringPtr(stringRef, kCFStringEncodingUTF8);
                    if (extensionToken) {
                        sandbox_extension_consume(extensionToken);
                    }
                }
            }
            CFRelease(plist);
        }
        CFRelease(stream);
    }
    CFRelease(url);
    CFRelease(path);
}

void unrestrict(void)
{
	unsandbox();
	jbdDebugMe();
}