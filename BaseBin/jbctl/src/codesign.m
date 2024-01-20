#include <Foundation/Foundation.h>
#include <Security/Security.h>
#include <TargetConditionals.h>
#import <libjailbreak/libjailbreak.h>

#ifdef __cplusplus
extern "C" {
#endif

#if TARGET_OS_OSX
#include <Security/SecCode.h>
#include <Security/SecStaticCode.h>
#else

// CSCommon.h
typedef struct CF_BRIDGED_TYPE(id) __SecCode const* SecStaticCodeRef; /* code on disk */

typedef CF_OPTIONS(uint32_t, SecCSFlags) {
    kSecCSDefaultFlags = 0, /* no particular flags (default behavior) */

    kSecCSConsiderExpiration = 1U << 31,     /* consider expired certificates invalid */
    kSecCSEnforceRevocationChecks = 1 << 30, /* force revocation checks regardless of preference settings */
    kSecCSNoNetworkAccess = 1 << 29,         /* do not use the network, cancels "kSecCSEnforceRevocationChecks"  */
    kSecCSReportProgress = 1 << 28,          /* make progress report call-backs when configured */
    kSecCSCheckTrustedAnchors = 1 << 27,     /* build certificate chain to system trust anchors, not to any self-signed certificate */
    kSecCSQuickCheck = 1 << 26,              /* (internal) */
    kSecCSApplyEmbeddedPolicy = 1 << 25,     /* Apply Embedded (iPhone) policy regardless of the platform we're running on */
};

typedef CF_OPTIONS(uint32_t, SecPreserveFlags) {
	kSecCSPreserveIdentifier = 1 << 0,
	kSecCSPreserveRequirements = 1 << 1,
	kSecCSPreserveEntitlements = 1 << 2,
	kSecCSPreserveResourceRules = 1 << 3,
	kSecCSPreserveFlags = 1 << 4,
	kSecCSPreserveTeamIdentifier = 1 << 5,
	kSecCSPreserveDigestAlgorithm = 1 << 6,
	kSecCSPreservePreEncryptHashes = 1 << 7,
	kSecCSPreserveRuntime = 1 << 8,
};

// SecStaticCode.h
OSStatus SecStaticCodeCreateWithPathAndAttributes(CFURLRef path, SecCSFlags flags, CFDictionaryRef attributes,
                                                  SecStaticCodeRef* __nonnull CF_RETURNS_RETAINED staticCode);

// SecCode.h
CF_ENUM(uint32_t){
    kSecCSInternalInformation = 1 << 0, kSecCSSigningInformation = 1 << 1, kSecCSRequirementInformation = 1 << 2,
    kSecCSDynamicInformation = 1 << 3,  kSecCSContentInformation = 1 << 4, kSecCSSkipResourceDirectory = 1 << 5,
    kSecCSCalculateCMSDigest = 1 << 6,
};

OSStatus SecCodeCopySigningInformation(SecStaticCodeRef code, SecCSFlags flags, CFDictionaryRef* __nonnull CF_RETURNS_RETAINED information);

extern const CFStringRef kSecCodeInfoEntitlements;    /* generic */
extern const CFStringRef kSecCodeInfoIdentifier;      /* generic */
extern const CFStringRef kSecCodeInfoRequirementData; /* Requirement */

#endif

// SecCodeSigner.h
#ifdef BRIDGED_SECCODESIGNER
typedef struct CF_BRIDGED_TYPE(id) __SecCodeSigner* SecCodeSignerRef SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));
#else
typedef struct __SecCodeSigner* SecCodeSignerRef SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));
#endif

extern const CFStringRef kSecCodeSignerEntitlements SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));
extern const CFStringRef kSecCodeSignerIdentifier SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));
extern const CFStringRef kSecCodeSignerIdentity SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));
extern const CFStringRef kSecCodeSignerPreserveMetadata SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));
extern const CFStringRef kSecCodeSignerRequirements SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));
extern const CFStringRef kSecCodeSignerResourceRules SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));

#ifdef BRIDGED_SECCODESIGNER
OSStatus SecCodeSignerCreate(CFDictionaryRef parameters, SecCSFlags flags, SecCodeSignerRef* __nonnull CF_RETURNS_RETAINED signer)
    SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));
#else
OSStatus SecCodeSignerCreate(CFDictionaryRef parameters, SecCSFlags flags, SecCodeSignerRef* signer)
    SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));
#endif

OSStatus SecCodeSignerAddSignatureWithErrors(SecCodeSignerRef signer, SecStaticCodeRef code, SecCSFlags flags, CFErrorRef* errors)
    SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));

// SecCodePriv.h
extern const CFStringRef kSecCodeInfoResourceDirectory; /* Internal */

#ifdef __cplusplus
}
#endif

int resign_file(NSString *filePath, bool preserveMetadata)
{
	OSStatus status = 0;
	int retval = 200;

	// the special value "-" (dash) indicates ad-hoc signing
	SecIdentityRef identity = (SecIdentityRef)kCFNull;
	NSMutableDictionary* parameters = [[NSMutableDictionary alloc] init];
	parameters[(__bridge NSString*)kSecCodeSignerIdentity] = (__bridge id)identity;
	if (preserveMetadata) {
		parameters[(__bridge NSString*)kSecCodeSignerPreserveMetadata] = @(kSecCSPreserveIdentifier | kSecCSPreserveRequirements | kSecCSPreserveEntitlements | kSecCSPreserveResourceRules);
	}

	SecCodeSignerRef signerRef;
	status = SecCodeSignerCreate((__bridge CFDictionaryRef)parameters, kSecCSDefaultFlags, &signerRef);
	if (status == 0) {
		SecStaticCodeRef code;
		status = SecStaticCodeCreateWithPathAndAttributes((__bridge CFURLRef)[NSURL fileURLWithPath:filePath], kSecCSDefaultFlags, NULL, &code);
		if (status == 0) {
			status = SecCodeSignerAddSignatureWithErrors(signerRef, code, kSecCSDefaultFlags, NULL);
			if (status == 0) {
				CFDictionaryRef newSigningInformation;
				// Difference from codesign: added kSecCSSigningInformation, kSecCSRequirementInformation, kSecCSInternalInformation
				status = SecCodeCopySigningInformation(code, kSecCSDefaultFlags | kSecCSSigningInformation | kSecCSRequirementInformation | kSecCSInternalInformation, &newSigningInformation);
				if (status == 0) {
					printf("SecCodeCopySigningInformation succeeded: %s\n", ((__bridge NSDictionary*)newSigningInformation).description.UTF8String);
					retval = 0;
					CFRelease(newSigningInformation);
				} else {
					printf("SecCodeCopySigningInformation failed: %s (%d)\n", ((__bridge NSString*)SecCopyErrorMessageString(status, NULL)).UTF8String, status);
					retval = 203;
				}
			}
			CFRelease(code);
		}
		else {
			printf("SecStaticCodeCreateWithPathAndAttributes failed: %s (%d)\n", ((__bridge NSString*)SecCopyErrorMessageString(status, NULL)).UTF8String, status);
			retval = 202;
		}
		CFRelease(signerRef);
	}
	else {
		printf("SecCodeSignerCreate failed: %s (%d)\n", ((__bridge NSString*)SecCopyErrorMessageString(status, NULL)).UTF8String, status);
		retval = 201;
	}

	return retval;
}
