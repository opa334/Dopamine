#ifndef LJB_DISPLAY_H
#define LJB_DISPLAY_H

#import <IOMobileFramebuffer/IOMobileFramebuffer.h>
#import <CoreGraphics/CoreGraphics.h>

CGSize find_display_size(void);

int draw_image_to_buf(CGImageRef cgImage, IOMobileFramebufferDisplaySize size, CGFloat rotation, void **bufOut, size_t *bufSizeOut);
int draw_image_to_buf_for_main_screen(CGImageRef image, void **bufOut, size_t *bufSizeOut);
int draw_image_path_to_buf(const char* image_path, IOMobileFramebufferDisplaySize size, CGFloat rotation, void **bufOut, size_t *bufSizeOut);
int draw_image_path_to_buf_for_main_screen(const char* image_path, void **bufOut, size_t *bufSizeOut);
int save_image_bitmap_to_plist(CGImageRef imageRef, const char *outPath);
CGImageRef load_image_from_bitmap_plist(const char *bitmapPlistPath);
int display_draw_raw_path(const char *path);
int display_draw_raw(void *rawBuf, size_t rawBufSize);
int display_draw_image_path(const char* image_path);
int display_draw_image(CGImageRef cgImage);

#endif
