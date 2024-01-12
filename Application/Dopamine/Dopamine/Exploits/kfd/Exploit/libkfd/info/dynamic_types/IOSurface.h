//
//  IOSurface.h
//  kfd
//
//  Created by Lars Fröder on 30.07.23.
//

#ifndef IOSurface_h
#define IOSurface_h

struct IOSurface {
    u64 isa;
    u64 PixelFormat;
    u64 AllocSize;
    u64 UseCountPtr;
    u64 IndexedTimestampPtr;
    
    u64 ReadDisplacement;
};

const struct IOSurface IOSurface_versions[] = {
    // iOS 16 is left to the educated reader to figure out (keep in mind it will only work on arm64)
    { },
    { },
    { },
    { },
    
    { .isa = 0x0, .PixelFormat = 0xA4, .AllocSize = 0xAC, .UseCountPtr = 0xC0, .IndexedTimestampPtr = 0x360, .ReadDisplacement = 0x14 }, // iOS 15.0 - 15.1.1 arm64
    { .isa = 0x0, .PixelFormat = 0xA4, .AllocSize = 0xAC, .UseCountPtr = 0xC0, .IndexedTimestampPtr = 0x360, .ReadDisplacement = 0x14 }, // iOS 15.0 - 15.1.1 arm64e
    
    { .isa = 0x0, .PixelFormat = 0xA4, .AllocSize = 0xAC, .UseCountPtr = 0xC0, .IndexedTimestampPtr = 0x360, .ReadDisplacement = 0x14 }, // iOS 15.2 - 15.3.1 arm64
    { .isa = 0x0, .PixelFormat = 0xA4, .AllocSize = 0xAC, .UseCountPtr = 0xC0, .IndexedTimestampPtr = 0x360, .ReadDisplacement = 0x14 }, // iOS 15.2 - 15.3.1 arm64e
    
    { .isa = 0x0, .PixelFormat = 0xA4, .AllocSize = 0xAC, .UseCountPtr = 0xC0, .IndexedTimestampPtr = 0x360, .ReadDisplacement = 0x14 }, // iOS 15.4 - 15.7.8 arm64
    { .isa = 0x0, .PixelFormat = 0xA4, .AllocSize = 0xAC, .UseCountPtr = 0xC0, .IndexedTimestampPtr = 0x360, .ReadDisplacement = 0x14 }, // iOS 15.4 - 15.7.2 arm64e
    
    { .isa = 0x0, .PixelFormat = 0xA4, .AllocSize = 0xAC, .UseCountPtr = 0xC0, .IndexedTimestampPtr = 0x360, .ReadDisplacement = 0x14 }, // iOS 14.0 - 14.4
    { .isa = 0x0, .PixelFormat = 0xA4, .AllocSize = 0xAC, .UseCountPtr = 0xC0, .IndexedTimestampPtr = 0x360, .ReadDisplacement = 0x14 }, // iOS 14.5 - 14.8.1
    
    
};

typedef u64 IOSurface_isa_t;
typedef u32 IOSurface_PixelFormat_t;
typedef u32 IOSurface_AllocSize_t;
typedef u64 IOSurface_UseCountPtr_t;
typedef u64 IOSurface_IndexedTimestampPtr_t;
typedef u32 IOSurface_ReadDisplacement_t;


#endif /* IOSurface_h */
