#include "display.h"

#import <Foundation/Foundation.h>
#import <IOMobileFramebuffer/IOMobileFramebuffer.h>
#import <IOSurface/IOSurfaceRef.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <UIKit/UIKit.h>
#import <sys/stat.h>
#import <dlfcn.h>

#define RADIANS(degrees) ( degrees * M_PI / 180 )

CFTypeRef MGCopyAnswer(CFStringRef str);

struct display {
	bool inited;
	void *base;
	IOMobileFramebufferDisplaySize size;
	int bytesPerRow;
	IOMobileFramebufferRef display;
	IOSurfaceRef surface;
} gDisplay;

int display_update(void)
{
	if (!gDisplay.display) return -1;

	int token;
	IOMobileFramebufferSwapBegin(gDisplay.display, &token);
	IOMobileFramebufferSwapSetLayer(gDisplay.display, 0, gDisplay.surface, (CGRect){ { 0, 0 }, { gDisplay.size.width, gDisplay.size.height } }, (CGRect){ { 0, 0 }, { gDisplay.size.width, gDisplay.size.height } }, 0);
	return IOMobileFramebufferSwapEnd(gDisplay.display);
}

IOMobileFramebufferReturn find_target_display(IOMobileFramebufferRef *pointer)
{
	if (!pointer) return -1;

	IOMobileFramebufferReturn r = IOMobileFramebufferGetMainDisplay(pointer);
	if (r != 0) {
		r = IOMobileFramebufferGetSecondaryDisplay(pointer);
	}

	return r;
}

CGSize find_display_size(void)
{
	CGSize displaySize = CGSizeMake(0,0);

	IOMobileFramebufferRef targetDisplay;
	IOMobileFramebufferReturn r = find_target_display(&targetDisplay);
	if (r == 0) {
		IOMobileFramebufferGetDisplaySize(targetDisplay, &displaySize);
	}
	else {
		// If we aren't entitled to get the display info from IOMobileFramebuffer, get it from GraphicsServices instead
		static CGSize (*__GSMainScreenPixelSize)(void) = NULL;
		if (!__GSMainScreenPixelSize) {
			void *graphicsServiceHandle = dlopen("/System/Library/PrivateFrameworks/GraphicsServices.framework/GraphicsServices", RTLD_NOW);
			__GSMainScreenPixelSize = dlsym(graphicsServiceHandle, "GSMainScreenPixelSize");
		}

		if (__GSMainScreenPixelSize) {
			displaySize = __GSMainScreenPixelSize();
		}
	}

	return displaySize;
}

IOSurfaceRef create_iosurface_for_display(IOMobileFramebufferDisplaySize size, uint32_t cacheMode)
{
	size_t bytesPerRow = IOSurfaceAlignProperty(kIOSurfaceBytesPerRow, 4 * size.width);

	NSDictionary *properties = @{
		(__bridge id)kIOSurfaceWidth : @(size.width),
		(__bridge id)kIOSurfaceHeight : @(size.height),
		(__bridge id)kIOSurfacePixelFormat : @0x42475241, // 'ARGB'
		(__bridge id)kIOSurfaceBytesPerRow : @(bytesPerRow),
		(__bridge id)kIOSurfaceCacheMode : @(cacheMode),
	};

	return IOSurfaceCreate((__bridge CFDictionaryRef)properties);
}

int display_init_internal(bool useDCPFlags)
{
	if (gDisplay.inited) return 0;

	int r = find_target_display(&gDisplay.display);
	if (r) return r;
	gDisplay.size = find_display_size();

	gDisplay.surface = create_iosurface_for_display(gDisplay.size, useDCPFlags ? kIOMapWriteCombineCache | kIOMapInhibitCache | kIOMapWriteThruCache | kIOMapCopybackCache : kIOMapWriteCombineCache);

	IOSurfaceLock(gDisplay.surface, 0, 0);
	gDisplay.base = IOSurfaceGetBaseAddress(gDisplay.surface);
	gDisplay.bytesPerRow = IOSurfaceGetBytesPerRow(gDisplay.surface);
	IOSurfaceUnlock(gDisplay.surface, 0, 0);

	kern_return_t kr = display_update();
	if (kr == KERN_SUCCESS) {
		gDisplay.inited = true;
	}
	else {
		CFRelease(gDisplay.surface);
		if (kr == kIOReturnBadMedia) {
			return kIOReturnBadMedia;
		}
		return -1;
	}
	return 0;
}

int display_init(void)
{
	int r = display_init_internal(false);
	if (r == kIOReturnBadMedia) {
		return display_init_internal(true);
	}
	return r;
}

int display_reset(void)
{
	if (!gDisplay.base) return -1;

	memset(gDisplay.base, 0, gDisplay.size.height * gDisplay.bytesPerRow);
	display_update();
	return 0;
}

int draw_image_to_buf(CGImageRef cgImage, IOMobileFramebufferDisplaySize size, CGFloat rotation, void **bufOut, size_t *bufSizeOut)
{
	size_t bytesPerRow = IOSurfaceAlignProperty(kIOSurfaceBytesPerRow, 4 * size.width);

	int retval = -1;
	CGContextRef context = NULL;
	CGColorSpaceRef rgbColorSpace = NULL;
	char *tmpBuf = NULL;
	size_t bufSize = size.height * bytesPerRow;

	rgbColorSpace = CGColorSpaceCreateDeviceRGB();
	if (!rgbColorSpace) goto finish;

	tmpBuf = malloc(bufSize);
	if (!tmpBuf) goto finish;
	memset(tmpBuf, 0, bufSize);

	context = CGBitmapContextCreate(tmpBuf, size.width, size.height, 8, bytesPerRow, rgbColorSpace, kCGImageAlphaPremultipliedFirst | kCGImageByteOrder32Little);
	if (!context) goto finish;

	CGFloat imageWidth  = CGImageGetWidth(cgImage);
	CGFloat imageHeight = CGImageGetHeight(cgImage);

	CGFloat radians = RADIANS(rotation);
	CGFloat cosTheta = fabs(cos(radians));
	CGFloat sinTheta = fabs(sin(radians));

	CGFloat rotatedWidth  = imageWidth * cosTheta + imageHeight * sinTheta;
	CGFloat rotatedHeight = imageWidth * sinTheta + imageHeight * cosTheta;

	CGFloat scale = MAX(size.width  / rotatedWidth, size.height / rotatedHeight);

	CGContextTranslateCTM(context, size.width  * 0.5, size.height * 0.5);
	CGContextRotateCTM(context, radians);
	CGContextScaleCTM(context, scale, scale);

	CGRect imageRect = CGRectMake(-imageWidth  * 0.5, -imageHeight * 0.5, imageWidth, imageHeight);

	CGContextDrawImage(context, imageRect, cgImage);

	*bufOut = tmpBuf;
	*bufSizeOut = bufSize;
	tmpBuf = NULL;
	retval = 0;

finish:
	if (context) CGContextRelease(context);
	if (rgbColorSpace) CGColorSpaceRelease(rgbColorSpace);
	if (tmpBuf) free(tmpBuf);

	return retval;
}

BOOL is_ipad(void)
{
	CFStringRef deviceClass = MGCopyAnswer(CFSTR("DeviceClass"));
	if (!deviceClass) return NO;
	BOOL result = CFStringCompare(deviceClass, CFSTR("iPad"), 0) == kCFCompareEqualTo;
	CFRelease(deviceClass);
	return result;
}

CGFloat get_main_screen_rotation(void)
{
	if (is_ipad()) {
		CFNumberRef mainScreenOrientationNum = MGCopyAnswer(CFSTR("main-screen-orientation"));
		if (mainScreenOrientationNum) {
			unsigned long long mainScreenOrientation = [(__bridge NSNumber *)mainScreenOrientationNum unsignedLongLongValue];
			if (mainScreenOrientation == 0) { // iPads that have a non landscape base orientation...
				CFNumberRef displayBootRotationNum = MGCopyAnswer(CFSTR("DisplayBootRotation"));
				unsigned long long displayBootRotation = [(__bridge NSNumber *)displayBootRotationNum unsignedLongLongValue]; // ...need to take the displayBootRotation as the image rotation

				switch (displayBootRotation) {
					case 0:
					return 0;
					case 90:
					return 270;
					case 180:
					return 180;
					case 270:
					return 90;
				}
			}
			else { // iPads that DO have a lanscape base orientation...
				CFNumberRef displayBootRotationNum = MGCopyAnswer(CFSTR("DisplayBootRotation"));
				unsigned long long displayBootRotation = [(__bridge NSNumber *)displayBootRotationNum unsignedLongLongValue];
				switch (displayBootRotation) {
					case 0:
					return 90;
					case 90:
					return 0;
					case 180:
					return 270;
					case 270:
					return 180;
				}
			}
		}
	}

	return 0;
}

int draw_image_to_buf_for_main_screen(CGImageRef image, void **bufOut, size_t *bufSizeOut)
{
	return draw_image_to_buf(image, find_display_size(), get_main_screen_rotation(), bufOut, bufSizeOut);
}

int display_draw_raw_path(const char *path)
{
	int retval = display_init();
	if (retval) return retval;

	bool worked = false;
	int fd = open(path, O_RDONLY);
	if (fd >= 0) {
		struct stat s;
		if (fstat(fd, &s) == 0) {
			size_t displayBufSize = gDisplay.size.height * gDisplay.bytesPerRow;
			if (displayBufSize == s.st_size) {
				worked = true;
				read(fd, gDisplay.base, s.st_size);
			}
		}
		close(fd);
	}

	if (!worked) return -1;

	return display_update();
}

static CGImageRef load_image(const char *image_path)
{
	CFURLRef imageURL = NULL;
	CGImageSourceRef cgImageSource = NULL;
	CGImageRef cgImage = NULL;
	CFStringRef bootImageCfString = NULL;

	bootImageCfString = CFStringCreateWithCString(kCFAllocatorDefault, image_path, kCFStringEncodingUTF8);
	if (!bootImageCfString) goto finish;
	imageURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, bootImageCfString, kCFURLPOSIXPathStyle, false);
	if (!imageURL) goto finish;
	cgImageSource = CGImageSourceCreateWithURL(imageURL, NULL);
	if (!cgImageSource) goto finish;
	cgImage = CGImageSourceCreateImageAtIndex(cgImageSource, 0, NULL);
	if (!cgImage) goto finish;

finish:
	if (bootImageCfString) CFRelease(bootImageCfString);
	if (imageURL) CFRelease(imageURL);
	if (cgImageSource) CFRelease(cgImageSource);

	return cgImage;
}

int save_image_bitmap_to_plist(CGImageRef imageRef, const char *outPath)
{
	if (!imageRef) return -1;

	CGDataProviderRef dataProvider = CGImageGetDataProvider(imageRef);
	if (!dataProvider) return -1;
	CFDataRef data = CGDataProviderCopyData(dataProvider);
	if (!data) return -1;
	
	NSDictionary *imagePlist = @{
		@"width" : @(CGImageGetWidth(imageRef)),
		@"height" : @(CGImageGetHeight(imageRef)),
		@"bitsPerComponent" : @(CGImageGetBitsPerComponent(imageRef)),
		@"bitsPerPixel" : @(CGImageGetBitsPerPixel(imageRef)),
		@"bytesPerRow" : @(CGImageGetBytesPerRow(imageRef)),
		@"bitmapData" : (__bridge id)data,
	};

	CFRelease(data);

	return [imagePlist writeToURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:outPath]] error:nil] != true;
}

CGImageRef load_image_from_bitmap_plist(const char *bitmapPlistPath)
{
	NSDictionary *imagePlist = [NSDictionary dictionaryWithContentsOfURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:bitmapPlistPath]] error:nil];
	if (!imagePlist) return NULL;

	size_t width = ((NSNumber *)imagePlist[@"width"]).unsignedLongLongValue;
	size_t height = ((NSNumber *)imagePlist[@"height"]).unsignedLongLongValue;
	size_t bitsPerComponent = ((NSNumber *)imagePlist[@"bitsPerComponent"]).unsignedLongLongValue;
	size_t bitsPerPixel = ((NSNumber *)imagePlist[@"bitsPerPixel"]).unsignedLongLongValue;
	size_t bytesPerRow = ((NSNumber *)imagePlist[@"bytesPerRow"]).unsignedLongLongValue;
	NSData *bitmapData = imagePlist[@"bitmapData"];
	const void *bitmapBuffer = bitmapData.bytes;

	if ((height * bytesPerRow) != bitmapData.length) {
		return NULL;
	}

	CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, bitmapBuffer, height * bytesPerRow, NULL);

	CGColorSpaceRef colorSpaceRef = CGColorSpaceCreateDeviceRGB();
	CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault;
	CGColorRenderingIntent renderingIntent = kCGRenderingIntentDefault;

	CGImageRef imageRef = CGImageCreate(width,
		height,
		bitsPerComponent,
		bitsPerPixel,
		bytesPerRow,
		colorSpaceRef,
		bitmapInfo,
		provider,
		NULL,
		NO,
		renderingIntent);

	CGDataProviderRelease(provider);
	CGColorSpaceRelease(colorSpaceRef);
	
	return imageRef;
}

int draw_image_path_to_buf(const char* image_path, IOMobileFramebufferDisplaySize size, CGFloat rotation, void **bufOut, size_t *bufSizeOut)
{
	CGImageRef cgImage = load_image(image_path);
	if (!cgImage) return -1;
	int r = draw_image_to_buf(cgImage, size, rotation, bufOut, bufSizeOut);
	CGImageRelease(cgImage);
	return r;
}

int draw_image_path_to_buf_for_main_screen(const char* image_path, void **bufOut, size_t *bufSizeOut)
{
	CGImageRef cgImage = load_image(image_path);
	if (!cgImage) return -1;
	int r = draw_image_to_buf_for_main_screen(cgImage, bufOut, bufSizeOut);
	CGImageRelease(cgImage);
	return r;
}

int display_draw_raw(void *rawBuf, size_t rawBufSize)
{
	int retval = display_init();
	if (retval) return retval;
	size_t displayBufSize = gDisplay.size.height * gDisplay.bytesPerRow;
	if (rawBufSize != displayBufSize) {
		return -1;
	}
	memcpy(gDisplay.base, rawBuf, rawBufSize);
	return display_update();
}

int display_draw_image_path(const char* image_path)
{
	int retval = -1;

	void *buf = NULL;
	size_t bufSize = 0;
	retval = draw_image_path_to_buf_for_main_screen(image_path, &buf, &bufSize);
	if (retval) return retval;
	retval = display_draw_raw(buf, bufSize);
    free(buf);
	return retval;
}

int display_draw_image(CGImageRef cgImage)
{
	int retval = -1;

	void *buf = NULL;
	size_t bufSize = 0;
	retval = draw_image_to_buf_for_main_screen(cgImage, &buf, &bufSize);
	if (retval) return retval;
	retval = display_draw_raw(buf, bufSize);
    free(buf);
	return retval;
}