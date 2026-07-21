#ifndef IOMOBILEFRAMEBUFFER_IOMOBILEFRAMEBUFFER_H
#define IOMOBILEFRAMEBUFFER_IOMOBILEFRAMEBUFFER_H

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOTypes.h>
#include <CoreGraphics/CoreGraphics.h>

typedef IOReturn IOMobileFramebufferReturn;
typedef struct __IOMobileFramebuffer *IOMobileFramebufferRef;
typedef CGSize IOMobileFramebufferDisplaySize;

__BEGIN_DECLS

IOMobileFramebufferReturn
IOMobileFramebufferGetMainDisplay(IOMobileFramebufferRef *pointer);

IOMobileFramebufferReturn
IOMobileFramebufferGetSecondaryDisplay(IOMobileFramebufferRef *pointer);

IOMobileFramebufferReturn
IOMobileFramebufferGetDisplaySize(IOMobileFramebufferRef pointer, IOMobileFramebufferDisplaySize *size);

IOMobileFramebufferReturn
IOMobileFramebufferGetLayerDefaultSurface(IOMobileFramebufferRef pointer, int surface, IOSurfaceRef *buffer);

IOMobileFramebufferReturn
IOMobileFramebufferSwapBegin(IOMobileFramebufferRef pointer, int *token);

IOMobileFramebufferReturn
IOMobileFramebufferSwapEnd(IOMobileFramebufferRef pointer);

IOMobileFramebufferReturn
IOMobileFramebufferSwapSetLayer(IOMobileFramebufferRef pointer, int layerid, IOSurfaceRef buffer, CGRect bounds, CGRect frame, int flags);

__END_DECLS

#endif