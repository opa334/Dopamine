/*
     File:       FSEvents/FSEvents.h
 
     Contains:   FSEventStream API
 
     Copyright:  © 2006-2014 by Apple Inc. All rights reserved.
 
     Bugs?:      For bug reports, consult the following page on
                 the World Wide Web:
 
                     http://developer.apple.com/bugreporter/
 
*/
#ifndef __FSEVENTS__
#define __FSEVENTS__

#ifndef __CFRUNLOOP__
#include <CoreFoundation/CFRunLoop.h>
#endif

#ifndef __CFUUID__
#include <CoreFoundation/CFUUID.h>
#endif


#include <Block.h>
#include <dispatch/dispatch.h>
#include <sys/types.h>


#include <Availability.h>

#if PRAGMA_ONCE
#pragma once
#endif

#ifdef __cplusplus
extern "C" {
#endif

CF_ASSUME_NONNULL_BEGIN

#pragma pack(push, 2)

#if PRAGMA_ENUM_ALWAYSINT
    #pragma enumsalwaysint on
#endif


/*
 *  
 *  
 *  Discussion:
 *    This header describes the FSEvents API.  This API provides a
 *    mechanism to notify clients about directories they ought to
 *    re-scan in order to keep their internal data structures
 *    up-to-date with respect to the true state of the file system.
 *    (For example, when files or directories are created, modified, or
 *    removed.) It sends these notifications "in bulk", possibly
 *    notifying the client of changes to several directories in a
 *    single callback. By using the API, clients can notice such
 *    changes quickly, without needing to resort to recursive
 *    polling/scanning of the file system. 
 *    
 *    Much like kqueues, the FSEvents API allows an application to find
 *    near-immediately when the contents of a particular directory has
 *    changed.  However, unlike kqueues, the FSEvents API allows the
 *    application to monitor the whole file system hierarchy rooted at
 *    a specified directory (and still get precise per-directory
 *    notifications) -- to do this with the kqueues API would require
 *    the client to monitor each directory individually. 
 *    
 *    Clients can register interest in a chunk of the filesystem
 *    hierarchy and will receive callbacks from their runloop whenever
 *    an event occurs that modifies the filesystem therein.  The
 *    callback will indicate the exact directory in which the event
 *    occurred, so the client only has to scan that directory for
 *    updated info, not all its children.  Clients can supply a
 *    "latency" parameter that tells how long to wait after an event
 *    occurs before forwarding it; this reduces the volume of events
 *    and reduces the chance that the client will see an "intermediate"
 *    state, like those that arise when doing a "safe save" of a file,
 *    creating a package, or downloading a file via Safari. 
 *    
 *    
 *    
 *    The lifecycle of an FSEventStream consists of these stages:
 *    
 *    
 *    1. FSEventStreamCreate() / FSEventStreamCreateRelativeToDevice()
 *    -> Creates an FSEventStream. 
 *    
 *    2. FSEventStreamScheduleWithRunLoop() -> Schedules an
 *    FSEventStream on a runloop, like CFRunLoopAddSource() does for a
 *    CFRunLoopSourceRef. 
 *    
 *    3. FSEventStreamStart() -> Starts receiving events and servicing
 *    them from the client's runloop(s) using the callback supplied by
 *    the client when the stream was created. If a value was supplied
 *    for the sinceWhen parameter then "historical" events will be sent
 *    via your callback first, then a HistoryDone event, then
 *    "contemporary" events will be sent on an ongoing basis (as though
 *    you had supplied kFSEventStreamEventIdSinceNow for sinceWhen).
 *    
 *    
 *    4. FSEventStreamStop()  -> Stops the stream, ensuring the
 *    client's callback will not be called again for this stream.   
 *    After stopping the stream, it can be restarted seamlessly via
 *    FSEventStreamStart() without missing any events. 
 *    
 *    5. FSEventStreamInvalidate() -> Invalidates the stream, like
 *    CFRunLoopSourceInvalidate() does for a CFRunLoopSourcRef.
 *    
 *    
 *    6. FSEventStreamRelease() -> Decrements the refcount on the
 *    stream (initially one and incremented via FSEventStreamRetain()).
 *     If the refcount reaches zero, the stream is deallocated.
 *    
 *    
 *    Once the event stream has been started, the following calls can
 *    be used: 
 *    
 *    FSEventStreamGetLatestEventId() -> Initially, this returns the
 *    sinceWhen value supplied when the stream was created; thereafter,
 *    it is updated with the highest-numbered event ID mentioned in the
 *    current batch of events just before invoking the client's
 *    callback. Clients can store this value persistently as long as
 *    they also store the UUID for the device (obtained via
 *    FSEventsCopyUUIDForDevice()).  Clients can then later supply this
 *    event ID as the sinceWhen parameter to
 *    FSEventStreamCreateRelativeToDevice(), as long as its UUID
 *    matches what you stored.  This works because the FSEvents service
 *    stores events in a persistent, per-volume database.  In this
 *    regard,the stream of event IDs acts like a global, system-wide
 *    clock, but bears no relation to any particular timebase. 
 *    
 *    FSEventStreamFlushAsync() -> Requests that the fseventsd daemon
 *    send any events it has already buffered (via the latency
 *    parameter to one of the FSEventStreamCreate...() functions). This
 *    occurs asynchronously; clients will not have received all the
 *    callbacks by the time this call returns to them. 
 *    
 *    FSEventStreamFlushSync() -> Requests that the fseventsd daemon
 *    send any events it has already buffered (via the latency
 *    parameter to one of the FSEventStreamCreate...() functions). Then
 *    runs the runloop in its private mode till all events that have
 *    occurred have been reported (via the clients callback).  This
 *    occurs synchronously; clients will have received all the
 *    callbacks by the time this call returns to them. 
 *    
 *    FSEventStreamGetDeviceBeingWatched() -> Gets the dev_t value
 *    supplied when the stream was created with
 *    FSEventStreamCreateRelativeToDevice(), otherwise 0. 
 *    
 *    FSEventStreamCopyPathsBeingWatched() -> Gets the paths supplied
 *    when the stream was created with one of the
 *    FSEventStreamCreate...() functions. 
 *    
 *    Calls that can be made without a stream: 
 *    
 *    FSEventsCopyUUIDForDevice() -> Gets a UUID that uniquely
 *    identifies the FSEvents database for that volume. If the database
 *    gets discarded then its replacement will have a different UUID so
 *    that clients will be able to detect this situation and avoid
 *    trying to use event IDs that they stored as the sinceWhen
 *    parameter to the FSEventStreamCreate...() functions. 
 *    
 *    FSEventsGetCurrentEventId() -> Gets the most recently generated
 *    event ID, system-wide (not just for one stream). 
 *    
 *    FSEventsGetLastEventIdForDeviceBeforeTime() -> Gets the last
 *    event ID for the given device that was returned before the given
 *    time.  This is conservative in the sense that if you then use the
 *    returned event ID as the sinceWhen parameter of
 *    FSEventStreamCreateRelativeToDevice() that you will not miss any
 *    events that happened since that time.  On the other hand, you
 *    might receive some (harmless) extra events. 
 *    
 *    FSEventsPurgeEventsForDeviceUpToEventId() -> Purges old events
 *    from the persistent per-volume database maintained by the
 *    service.  You can combine this with
 *    FSEventsGetLastEventIdForDeviceBeforeTime(). Can only be called
 *    by the root user.
 */
/*
 * Types and Constants
 */

/*
 *  FSEventStreamCreateFlags
 *  
 *  Discussion:
 *    Flags that can be passed to the FSEventStreamCreate...()
 *    functions to modify the behavior of the stream being created.
 */
typedef UInt32                          FSEventStreamCreateFlags;

/*
 *  FSEventStreamCreateFlags
 *  
 *  Discussion:
 *    Flags that can be passed to the FSEventStreamCreate...()
 *    functions to modify the behavior of the stream being created.
 */
enum {

  /*
   * The default.
   */
  kFSEventStreamCreateFlagNone  = 0x00000000,

  /*
   * The framework will invoke your callback function with CF types
   * rather than raw C types (i.e., a CFArrayRef of CFStringRefs,
   * rather than a raw C array of raw C string pointers). See
   * FSEventStreamCallback.
   */
  kFSEventStreamCreateFlagUseCFTypes = 0x00000001,

  /*
   * Affects the meaning of the latency parameter. If you specify this
   * flag and more than latency seconds have elapsed since the last
   * event, your app will receive the event immediately. The delivery
   * of the event resets the latency timer and any further events will
   * be delivered after latency seconds have elapsed. This flag is
   * useful for apps that are interactive and want to react immediately
   * to changes but avoid getting swamped by notifications when changes
   * are occurringin rapid succession. If you do not specify this flag,
   * then when an event occurs after a period of no events, the latency
   * timer is started. Any events that occur during the next latency
   * seconds will be delivered as one group (including that first
   * event). The delivery of the group of events resets the latency
   * timer and any further events will be delivered after latency
   * seconds. This is the default behavior and is more appropriate for
   * background, daemon or batch processing apps.
   */
  kFSEventStreamCreateFlagNoDefer = 0x00000002,

  /*
   * Request notifications of changes along the path to the path(s)
   * you're watching. For example, with this flag, if you watch
   * "/foo/bar" and it is renamed to "/foo/bar.old", you would receive
   * a RootChanged event. The same is true if the directory "/foo" were
   * renamed. The event you receive is a special event: the path for
   * the event is the original path you specified, the flag
   * kFSEventStreamEventFlagRootChanged is set and event ID is zero.
   * RootChanged events are useful to indicate that you should rescan a
   * particular hierarchy because it changed completely (as opposed to
   * the things inside of it changing). If you want to track the
   * current location of a directory, it is best to open the directory
   * before creating the stream so that you have a file descriptor for
   * it and can issue an F_GETPATH fcntl() to find the current path.
   */
  kFSEventStreamCreateFlagWatchRoot = 0x00000004,

  /*
   * Don't send events that were triggered by the current process. This
   * is useful for reducing the volume of events that are sent. It is
   * only useful if your process might modify the file system hierarchy
   * beneath the path(s) being monitored. Note: this has no effect on
   * historical events, i.e., those delivered before the HistoryDone
   * sentinel event.  Also, this does not apply to RootChanged events
   * because the WatchRoot feature uses a separate mechanism that is
   * unable to provide information about the responsible process.
   */
  kFSEventStreamCreateFlagIgnoreSelf __OSX_AVAILABLE_STARTING(__MAC_10_6, __IPHONE_6_0) = 0x00000008,

  /*
   * Request file-level notifications.  Your stream will receive events
   * about individual files in the hierarchy you're watching instead of
   * only receiving directory level notifications.  Use this flag with
   * care as it will generate significantly more events than without it.
   */
  kFSEventStreamCreateFlagFileEvents __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_6_0) = 0x00000010,

  /*
   * Tag events that were triggered by the current process with the "OwnEvent" flag.
   * This is only useful if your process might modify the file system hierarchy
   * beneath the path(s) being monitored and you wish to know which events were
   * triggered by your process. Note: this has no effect on historical events, i.e.,
   * those delivered before the HistoryDone sentinel event.
   */
  kFSEventStreamCreateFlagMarkSelf __OSX_AVAILABLE_STARTING(__MAC_10_9, __IPHONE_7_0) = 0x00000020,

  /*
   * Requires kFSEventStreamCreateFlagUseCFTypes and instructs the
   * framework to invoke your callback function with CF types but,
   * instead of passing it a CFArrayRef of CFStringRefs, a CFArrayRef of
   * CFDictionaryRefs is passed.  Each dictionary will contain the event
   * path and possibly other "extended data" about the event.  See the
   * kFSEventStreamEventExtendedData*Key definitions for the set of keys
   * that may be set in the dictionary.  (See also FSEventStreamCallback.)
   */
  kFSEventStreamCreateFlagUseExtendedData __OSX_AVAILABLE_STARTING(__MAC_10_13, __IPHONE_11_0) = 0x00000040,

  /*
   * When requesting historical events it is possible that some events
   * may get skipped due to the way they are stored.  With this flag
   * all historical events in a given chunk are returned even if their
   * event-id is less than the sinceWhen id.  Put another way, deliver
   * all the events in the first chunk of historical events that contains
   * the sinceWhen id so that none are skipped even if their id is less
   * than the sinceWhen id.  This overlap avoids any issue with missing
   * events that happened at/near the time of an unclean restart of the
   * client process.
   */
  kFSEventStreamCreateFlagFullHistory __OSX_AVAILABLE_STARTING(__MAC_10_15, __IPHONE_13_0) = 0x00000080,
};

/*
 *  kFSEventStreamCreateFlagUseExtendedData
 *
 *  Discussion:
 *    Keys for extended data CFDictionary
 */

/*
 * Path to file system object.
 * Value of type CFStringRef (per CFStringCreateWithFileSystemRepresentation()).
 */
#define kFSEventStreamEventExtendedDataPathKey      CFSTR("path")

/*
 * File system object inode number.
 * Value of type CFNumberRef.
 * (Set only if you specified the FileEvents flag when creating the stream.)
 */
#define kFSEventStreamEventExtendedFileIDKey        CFSTR("fileID")

/*
 *  FSEventStreamEventFlags
 *  
 *  Discussion:
 *    Flags that can be passed to your FSEventStreamCallback function.
 */
typedef UInt32                          FSEventStreamEventFlags;

/*
 *  FSEventStreamEventFlags
 *  
 *  Discussion:
 *    Flags that can be passed to your FSEventStreamCallback function.
 *
 *    It is important to note that event flags are simply hints about the
 *    sort of operations that occurred at that path.
 *
 *    Furthermore, the FSEvent stream should NOT be treated as a form of
 *    historical log that could somehow be replayed to arrive at the
 *    current state of the file system.
 *
 *    The FSEvent stream simply indicates what paths changed; and clients
 *    need to reconcile what is really in the file system with their internal
 *    data model - and recognize that what is actually in the file system can
 *    change immediately after you check it.
 */
enum {

  /*
   * There was some change in the directory at the specific path
   * supplied in this event.
   */
  kFSEventStreamEventFlagNone   = 0x00000000,

  /*
   * Your application must rescan not just the directory given in the
   * event, but all its children, recursively. This can happen if there
   * was a problem whereby events were coalesced hierarchically. For
   * example, an event in /Users/jsmith/Music and an event in
   * /Users/jsmith/Pictures might be coalesced into an event with this
   * flag set and path=/Users/jsmith. If this flag is set you may be
   * able to get an idea of whether the bottleneck happened in the
   * kernel (less likely) or in your client (more likely) by checking
   * for the presence of the informational flags
   * kFSEventStreamEventFlagUserDropped or
   * kFSEventStreamEventFlagKernelDropped.
   */
  kFSEventStreamEventFlagMustScanSubDirs = 0x00000001,

  /*
   * The kFSEventStreamEventFlagUserDropped or
   * kFSEventStreamEventFlagKernelDropped flags may be set in addition
   * to the kFSEventStreamEventFlagMustScanSubDirs flag to indicate
   * that a problem occurred in buffering the events (the particular
   * flag set indicates where the problem occurred) and that the client
   * must do a full scan of any directories (and their subdirectories,
   * recursively) being monitored by this stream. If you asked to
   * monitor multiple paths with this stream then you will be notified
   * about all of them. Your code need only check for the
   * kFSEventStreamEventFlagMustScanSubDirs flag; these flags (if
   * present) only provide information to help you diagnose the problem.
   */
  kFSEventStreamEventFlagUserDropped = 0x00000002,
  kFSEventStreamEventFlagKernelDropped = 0x00000004,

  /*
   * If kFSEventStreamEventFlagEventIdsWrapped is set, it means the
   * 64-bit event ID counter wrapped around. As a result,
   * previously-issued event ID's are no longer valid arguments for the
   * sinceWhen parameter of the FSEventStreamCreate...() functions.
   */
  kFSEventStreamEventFlagEventIdsWrapped = 0x00000008,

  /*
   * Denotes a sentinel event sent to mark the end of the "historical"
   * events sent as a result of specifying a sinceWhen value in the
   * FSEventStreamCreate...() call that created this event stream. (It
   * will not be sent if kFSEventStreamEventIdSinceNow was passed for
   * sinceWhen.) After invoking the client's callback with all the
   * "historical" events that occurred before now, the client's
   * callback will be invoked with an event where the
   * kFSEventStreamEventFlagHistoryDone flag is set. The client should
   * ignore the path supplied in this callback.
   */
  kFSEventStreamEventFlagHistoryDone = 0x00000010,

  /*
   * Denotes a special event sent when there is a change to one of the
   * directories along the path to one of the directories you asked to
   * watch. When this flag is set, the event ID is zero and the path
   * corresponds to one of the paths you asked to watch (specifically,
   * the one that changed). The path may no longer exist because it or
   * one of its parents was deleted or renamed. Events with this flag
   * set will only be sent if you passed the flag
   * kFSEventStreamCreateFlagWatchRoot to FSEventStreamCreate...() when
   * you created the stream.
   */
  kFSEventStreamEventFlagRootChanged = 0x00000020,

  /*
   * Denotes a special event sent when a volume is mounted underneath
   * one of the paths being monitored. The path in the event is the
   * path to the newly-mounted volume. You will receive one of these
   * notifications for every volume mount event inside the kernel
   * (independent of DiskArbitration). Beware that a newly-mounted
   * volume could contain an arbitrarily large directory hierarchy.
   * Avoid pitfalls like triggering a recursive scan of a non-local
   * filesystem, which you can detect by checking for the absence of
   * the MNT_LOCAL flag in the f_flags returned by statfs(). Also be
   * aware of the MNT_DONTBROWSE flag that is set for volumes which
   * should not be displayed by user interface elements.
   */
  kFSEventStreamEventFlagMount  = 0x00000040,

  /*
   * Denotes a special event sent when a volume is unmounted underneath
   * one of the paths being monitored. The path in the event is the
   * path to the directory from which the volume was unmounted. You
   * will receive one of these notifications for every volume unmount
   * event inside the kernel. This is not a substitute for the
   * notifications provided by the DiskArbitration framework; you only
   * get notified after the unmount has occurred. Beware that
   * unmounting a volume could uncover an arbitrarily large directory
   * hierarchy, although Mac OS X never does that.
   */
  kFSEventStreamEventFlagUnmount = 0x00000080,

  /*
   * A file system object was created at the specific path supplied in this event.
   * (This flag is only ever set if you specified the FileEvents flag when creating the stream.)
   */
  kFSEventStreamEventFlagItemCreated __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_6_0) = 0x00000100,

  /*
   * A file system object was removed at the specific path supplied in this event.
   * (This flag is only ever set if you specified the FileEvents flag when creating the stream.)
   */
  kFSEventStreamEventFlagItemRemoved __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_6_0) = 0x00000200,

  /*
   * A file system object at the specific path supplied in this event had its metadata modified.
   * (This flag is only ever set if you specified the FileEvents flag when creating the stream.)
   */
  kFSEventStreamEventFlagItemInodeMetaMod __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_6_0) = 0x00000400,

  /*
   * A file system object was renamed at the specific path supplied in this event.
   * (This flag is only ever set if you specified the FileEvents flag when creating the stream.)
   */
  kFSEventStreamEventFlagItemRenamed __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_6_0) = 0x00000800,

  /*
   * A file system object at the specific path supplied in this event had its data modified.
   * (This flag is only ever set if you specified the FileEvents flag when creating the stream.)
   */
  kFSEventStreamEventFlagItemModified __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_6_0) = 0x00001000,

  /*
   * A file system object at the specific path supplied in this event had its FinderInfo data modified.
   * (This flag is only ever set if you specified the FileEvents flag when creating the stream.)
   */
  kFSEventStreamEventFlagItemFinderInfoMod __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_6_0) = 0x00002000,

  /*
   * A file system object at the specific path supplied in this event had its ownership changed.
   * (This flag is only ever set if you specified the FileEvents flag when creating the stream.)
   */
  kFSEventStreamEventFlagItemChangeOwner __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_6_0) = 0x00004000,

  /*
   * A file system object at the specific path supplied in this event had its extended attributes modified.
   * (This flag is only ever set if you specified the FileEvents flag when creating the stream.)
   */
  kFSEventStreamEventFlagItemXattrMod __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_6_0) = 0x00008000,

  /*
   * The file system object at the specific path supplied in this event is a regular file.
   * (This flag is only ever set if you specified the FileEvents flag when creating the stream.)
   */
  kFSEventStreamEventFlagItemIsFile __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_6_0) = 0x00010000,

  /*
   * The file system object at the specific path supplied in this event is a directory.
   * (This flag is only ever set if you specified the FileEvents flag when creating the stream.)
   */
  kFSEventStreamEventFlagItemIsDir __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_6_0) = 0x00020000,

  /*
   * The file system object at the specific path supplied in this event is a symbolic link.
   * (This flag is only ever set if you specified the FileEvents flag when creating the stream.)
   */
  kFSEventStreamEventFlagItemIsSymlink __OSX_AVAILABLE_STARTING(__MAC_10_7, __IPHONE_6_0) = 0x00040000,

  /*
   * Indicates the event was triggered by the current process.
   * (This flag is only ever set if you specified the MarkSelf flag when creating the stream.)
   */
  kFSEventStreamEventFlagOwnEvent __OSX_AVAILABLE_STARTING(__MAC_10_9, __IPHONE_7_0) = 0x00080000,

  /* 
   * Indicates the object at the specified path supplied in this event is a hard link.
   * (This flag is only ever set if you specified the FileEvents flag when creating the stream.)
   */
  kFSEventStreamEventFlagItemIsHardlink __OSX_AVAILABLE_STARTING(__MAC_10_10, __IPHONE_9_0) = 0x00100000,

  /* Indicates the object at the specific path supplied in this event was the last hard link.
   * (This flag is only ever set if you specified the FileEvents flag when creating the stream.)
   */
  kFSEventStreamEventFlagItemIsLastHardlink __OSX_AVAILABLE_STARTING(__MAC_10_10, __IPHONE_9_0) = 0x00200000,

  /*
   * The file system object at the specific path supplied in this event is a clone or was cloned.
   * (This flag is only ever set if you specified the FileEvents flag when creating the stream.)
   */
  kFSEventStreamEventFlagItemCloned __OSX_AVAILABLE_STARTING(__MAC_10_13, __IPHONE_11_0) = 0x00400000

};


/*
 *  FSEventStreamEventId
 *  
 *  Discussion:
 *    Event IDs that can be passed to the FSEventStreamCreate...()
 *    functions and FSEventStreamCallback(). They are monotonically
 *    increasing per system, even across reboots and drives coming and
 *    going. They bear no relation to any particular clock or timebase.
 */
typedef UInt64                          FSEventStreamEventId;

enum {
    kFSEventStreamEventIdSinceNow = 0xFFFFFFFFFFFFFFFFULL
};


/*
 *  FSEventStreamRef
 *  
 *  Discussion:
 *    This is the type of a reference to an FSEventStream.
 */
typedef struct __FSEventStream*         FSEventStreamRef;

/*
 *  ConstFSEventStreamRef
 *  
 *  Discussion:
 *    This is the type of a reference to a constant FSEventStream.
 */
typedef const struct __FSEventStream*   ConstFSEventStreamRef;

/*
 *  FSEventStreamContext
 *  
 *  Discussion:
 *    Structure containing client-supplied data (and callbacks to
 *    manage it) that should be associated with a newly-created stream.
 */
struct FSEventStreamContext {

  /*
   * Currently the only valid value is zero.
   */
  CFIndex             version;

  /*
   * An arbitrary client-defined value (for instance, a pointer) to be
   * associated with the stream and passed to the callback when it is
   * invoked.  If a non-NULL value is supplied for the retain callback
   * the framework will use it to retain this value.  If a non-NULL
   * value is supplied for the release callback then when the stream is
   * deallocated it will be used to release this value.  This can be
   * NULL.
   */
  void * __nullable   info;

  /*
   * The callback used retain the info pointer.  This can be NULL.
   */
  CFAllocatorRetainCallBack __nullable  retain;

  /*
   * The callback used release a retain on the info pointer.  This can
   * be NULL.
   */
  CFAllocatorReleaseCallBack __nullable  release;

  /*
   * The callback used to create a descriptive string representation of
   * the info pointer (or the data pointed to by the info pointer) for
   * debugging purposes.  This can be NULL.
   */
  CFAllocatorCopyDescriptionCallBack __nullable  copyDescription;
};
typedef struct FSEventStreamContext     FSEventStreamContext;

/*
 *  FSEventStreamCallback
 *  
 *  Discussion:
 *    This is the type of the callback function supplied by the client
 *    when creating a new stream.  This callback is invoked by the
 *    service from the client's runloop(s) when events occur, per the
 *    parameters specified when the stream was created.
 *  
 *  Parameters:
 *    
 *    streamRef:
 *      The stream for which event(s) occurred.
 *    
 *    clientCallBackInfo:
 *      The info field that was supplied in the context when this
 *      stream was created.
 *    
 *    numEvents:
 *      The number of events being reported in this callback. Each of
 *      the arrays (eventPaths, eventFlags, eventIds) will have this
 *      many elements.
 *    
 *    eventPaths:
 *      An array of paths to the directories in which event(s)
 *      occurred. The type of this parameter depends on the flags
 *      passed to FSEventStreamCreate...().
 *      * If kFSEventStreamCreateFlagUseCFTypes was not set, then the
 *      framework will pass your callback a raw C array of raw C
 *      strings that will be deallocated by the framework after your
 *      callback returns.
 *      * If both kFSEventStreamCreateFlagUseCFTypes and
 *      kFSEventStreamCreateFlagUseExtendedData are set, then this will be a
 *      CFArrayRef containing CFDictionaryRef objects (containing entries
 *      as described by the kFSEventStreamEventExtendedData*Key constants).
 *      Ownership follows the Get rule, and they will be released by the
 *      framework after your callback returns.
 *      * If kFSEventStreamCreateFlagUseCFTypes was set, then this will be a
 *      CFArrayRef containing CFStringRef objects (per
 *      CFStringCreateWithFileSystemRepresentation()). Ownership
 *      follows the Get rule, and they will be released by the
 *      framework after your callback returns.
 *
 *      A path might be "/" if ether of these flags is set for the event:
 *      kFSEventStreamEventFlagUserDropped,
 *      kFSEventStreamEventFlagKernelDropped.
 *    
 *    eventFlags:
 *      An array of flag words corresponding to the paths in the
 *      eventPaths parameter. If no flags are set, then there was some
 *      change in the directory at the specific path supplied in this
 *      event. See FSEventStreamEventFlags.
 *    
 *    eventIds:
 *      An array of FSEventStreamEventIds corresponding to the paths in
 *      the eventPaths parameter. Each event ID comes from the most
 *      recent event being reported in the corresponding directory
 *      named in the eventPaths parameter.  Event IDs all come from a
 *      single global source.  They are guaranteed to always be
 *      increasing, usually in leaps and bounds, even across system
 *      reboots and moving drives from one machine to another.  Just
 *      before invoking your callback your stream is updated so that
 *      calling the accessor FSEventStreamGetLatestEventId() will
 *      return the largest of the values passed in the eventIds
 *      parameter; if you were to stop processing events from this
 *      stream after this callback and resume processing them later
 *      from a newly-created FSEventStream, this is the value you would
 *      pass for the sinceWhen parameter to the
 *      FSEventStreamCreate...() function.
 */
typedef CALLBACK_API_C( void , FSEventStreamCallback )(ConstFSEventStreamRef streamRef, void * __nullable clientCallBackInfo, size_t numEvents, void *eventPaths,  const FSEventStreamEventFlags  * _Nonnull eventFlags, const FSEventStreamEventId * _Nonnull eventIds);
/*
 *  Create
 */
/*
 *  FSEventStreamCreate()
 *  
 *  Discussion:
 *    Creates a new FS event stream object with the given parameters.
 *    In order to start receiving callbacks you must also call
 *    FSEventStreamScheduleWithRunLoop() and FSEventStreamStart().
 *  
 *  Parameters:
 *    
 *    allocator:
 *      The CFAllocator to be used to allocate memory for the stream. 
 *      Pass NULL or kCFAllocatorDefault to use the current default
 *      allocator.
 *    
 *    callback:
 *      An FSEventStreamCallback which will be called when FS events
 *      occur.
 *    
 *    context:
 *      A pointer to the FSEventStreamContext structure the client
 *      wants to associate with this stream.  Its fields are copied out
 *      into the stream itself so its memory can be released after the
 *      stream is created.  Passing NULL is allowed and has the same
 *      effect as passing a structure whose fields are all set to zero.
 *    
 *    pathsToWatch:
 *      A CFArray of CFStringRefs, each specifying a path to a
 *      directory, signifying the root of a filesystem hierarchy to be
 *      watched for modifications.
 *    
 *    sinceWhen:
 *      The service will supply events that have happened after the
 *      given event ID. To ask for events "since now" pass the constant
 *      kFSEventStreamEventIdSinceNow. Often, clients will supply the
 *      highest-numbered FSEventStreamEventId they have received in a
 *      callback, which they can obtain via the
 *      FSEventStreamGetLatestEventId() accessor. Do not pass zero for
 *      sinceWhen, unless you want to receive events for every
 *      directory modified since "the beginning of time" -- an unlikely
 *      scenario.
 *    
 *    latency:
 *      The number of seconds the service should wait after hearing
 *      about an event from the kernel before passing it along to the
 *      client via its callback. Specifying a larger value may result
 *      in more effective temporal coalescing, resulting in fewer
 *      callbacks and greater overall efficiency.
 *    
 *    flags:
 *      Flags that modify the behavior of the stream being created. See
 *      FSEventStreamCreateFlags.
 *  
 *  Result:
 *    A valid FSEventStreamRef or NULL if there was a problem creating the object.
 *  
 *  Availability:
 *    Mac OS X:         in version 10.5 and later in CoreServices.framework
 *    CarbonLib:        not available
 *    Non-Carbon CFM:   not available
 */
extern FSEventStreamRef __nullable
FSEventStreamCreate(
  CFAllocatorRef __nullable  allocator,
  FSEventStreamCallback      callback,
  FSEventStreamContext * __nullable context,
  CFArrayRef                 pathsToWatch,
  FSEventStreamEventId       sinceWhen,
  CFTimeInterval             latency,
  FSEventStreamCreateFlags   flags)                           __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_6_0);


/*
 *  FSEventStreamCreateRelativeToDevice()
 *  
 *  Discussion:
 *    Creates a new FS event stream object for a particular device with
 *    the given parameters.  Note that only one path may be specified.
 *    In order to start receiving callbacks you must also call
 *    FSEventStreamScheduleWithRunLoop() and FSEventStreamStart().
 *  
 *  Parameters:
 *    
 *    allocator:
 *      The CFAllocator to be used to allocate memory for the stream. 
 *      Pass NULL or kCFAllocatorDefault to use the current default
 *      allocator.
 *    
 *    callback:
 *      An FSEventStreamCallback which will be called when FS events
 *      occur.
 *    
 *    context:
 *      A pointer to the FSEventStreamContext structure the client
 *      wants to associate with this stream.  Its fields are copied out
 *      into the stream itself so its memory can be released after the
 *      stream is created.
 *    
 *    deviceToWatch:
 *      A dev_t corresponding to the device which you want to receive
 *      notifications from.  The dev_t is the same as the st_dev field
 *      from a stat structure of a file on that device or the f_fsid[0]
 *      field of a statfs structure.  If the value of dev is zero, it
 *      is ignored.
 *    
 *    pathsToWatchRelativeToDevice:
 *      A CFArray of CFStringRefs, each specifying a relative path to a
 *      directory on the device identified by the dev parameter.  The
 *      paths should be relative to the root of the device.  For
 *      example, if a volume "MyData" is mounted at "/Volumes/MyData"
 *      and you want to watch "/Volumes/MyData/Pictures/July", specify
 *      a path string of "Pictures/July".  To watch the root of a
 *      volume pass a path of "" (the empty string).  Note that even
 *      though this is an array of paths, only one path may be specified.
 *    
 *    sinceWhen:
 *      The service will supply events that have happened after the
 *      given event ID. To ask for events "since now" pass the constant
 *      kFSEventStreamEventIdSinceNow. Often, clients will supply the
 *      highest-numbered FSEventStreamEventId they have received in a
 *      callback, which they can obtain via the
 *      FSEventStreamGetLatestEventId() accessor. Do not pass zero for
 *      sinceWhen, unless you want to receive events for every
 *      directory modified since "the beginning of time" -- an unlikely
 *      scenario.
 *    
 *    latency:
 *      The number of seconds the service should wait after hearing
 *      about an event from the kernel before passing it along to the
 *      client via its callback. Specifying a larger value may result
 *      in more effective temporal coalescing, resulting in fewer
 *      callbacks.
 *    
 *    flags:
 *      Flags that modify the behavior of the stream being created. See
 *      FSEventStreamCreateFlags.
 *  
 *  Result:
 *    A valid FSEventStreamRef.
 *  
 *  Availability:
 *    Mac OS X:         in version 10.5 and later in CoreServices.framework
 *    CarbonLib:        not available
 *    Non-Carbon CFM:   not available
 */
extern FSEventStreamRef __nullable
FSEventStreamCreateRelativeToDevice(
  CFAllocatorRef __nullable  allocator,
  FSEventStreamCallback      callback,
  FSEventStreamContext * __nullable context,
  dev_t                      deviceToWatch,
  CFArrayRef                 pathsToWatchRelativeToDevice,
  FSEventStreamEventId       sinceWhen,
  CFTimeInterval             latency,
  FSEventStreamCreateFlags   flags)                           __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_6_0);


/*
 *  Accessors
 */
/*
 *  FSEventStreamGetLatestEventId()
 *  
 *  Discussion:
 *    Fetches the sinceWhen property of the stream.  Upon receiving an
 *    event (and just before invoking the client's callback) this
 *    attribute is updated to the highest-numbered event ID mentioned
 *    in the event.
 *  
 *  Parameters:
 *    
 *    streamRef:
 *      A valid stream.
 *  
 *  Result:
 *    The sinceWhen attribute of the stream.
 *  
 *  Availability:
 *    Mac OS X:         in version 10.5 and later in CoreServices.framework
 *    CarbonLib:        not available
 *    Non-Carbon CFM:   not available
 */
extern FSEventStreamEventId 
FSEventStreamGetLatestEventId(ConstFSEventStreamRef streamRef) __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_6_0);


/*
 *  FSEventStreamGetDeviceBeingWatched()
 *  
 *  Discussion:
 *    Fetches the dev_t supplied when the stream was created via
 *    FSEventStreamCreateRelativeToDevice(), otherwise 0.
 *  
 *  Parameters:
 *    
 *    streamRef:
 *      A valid stream.
 *  
 *  Result:
 *    The dev_t for a device-relative stream, otherwise 0.
 *  
 *  Availability:
 *    Mac OS X:         in version 10.5 and later in CoreServices.framework
 *    CarbonLib:        not available
 *    Non-Carbon CFM:   not available
 */
extern dev_t 
FSEventStreamGetDeviceBeingWatched(ConstFSEventStreamRef streamRef) __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_6_0);


/*
 *  FSEventStreamCopyPathsBeingWatched()
 *  
 *  Discussion:
 *    Fetches the paths supplied when the stream was created via one of
 *    the FSEventStreamCreate...() functions.
 *  
 *  Parameters:
 *    
 *    streamRef:
 *      A valid stream.
 *  
 *  Result:
 *    A CFArray of CFStringRefs corresponding to those supplied when
 *    the stream was created. Ownership follows the Copy rule.
 *  
 *  Availability:
 *    Mac OS X:         in version 10.5 and later in CoreServices.framework
 *    CarbonLib:        not available
 *    Non-Carbon CFM:   not available
 */
extern CF_RETURNS_RETAINED CFArrayRef 
FSEventStreamCopyPathsBeingWatched(ConstFSEventStreamRef streamRef) __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_6_0);


/*
 *  FSEventsGetCurrentEventId()
 *  
 *  Discussion:
 *    Fetches the most recently generated event ID, system-wide (not
 *    just for one stream). By thetime it is returned to your
 *    application even newer events may have already been generated.
 *  
 *  Result:
 *    The event ID of the most recent event generated by the system.
 *  
 *  Availability:
 *    Mac OS X:         in version 10.5 and later in CoreServices.framework
 *    CarbonLib:        not available
 *    Non-Carbon CFM:   not available
 */
extern FSEventStreamEventId 
FSEventsGetCurrentEventId(void)                               __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_6_0);


/*
 *  FSEventsCopyUUIDForDevice()
 *  
 *  Discussion:
 *    Gets the UUID associated with a device, or NULL if not possible
 *    (for example, on read-only device).  A (non-NULL) UUID uniquely
 *    identifies a given stream of FSEvents.  If this (non-NULL) UUID
 *    is different than one that you stored from a previous run then
 *    the event stream is different (for example, because FSEvents were
 *    purged, because the disk was erased, or because the event ID
 *    counter wrapped around back to zero). A NULL return value
 *    indicates that "historical" events are not available, i.e., you
 *    should not supply a "sinceWhen" value to FSEventStreamCreate...()
 *    other than kFSEventStreamEventIdSinceNow.
 *  
 *  Parameters:
 *    
 *    dev:
 *      The dev_t of the device that you want to get the UUID for.
 *  
 *  Result:
 *    The UUID associated with the stream of events on this device, or
 *    NULL if no UUID is available (for example, on a read-only
 *    device).  The UUID is stored on the device itself and travels
 *    with it even when the device is attached to different computers. 
 *    Ownership follows the Copy Rule.
 *  
 *  Availability:
 *    Mac OS X:         in version 10.5 and later in CoreServices.framework
 *    CarbonLib:        not available
 *    Non-Carbon CFM:   not available
 */
extern CF_RETURNS_RETAINED CFUUIDRef __nullable
FSEventsCopyUUIDForDevice(dev_t dev)                          __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_6_0);


/*
 *  FSEventsGetLastEventIdForDeviceBeforeTime()
 *  
 *  Discussion:
 *    Gets the last event ID for the given device that was returned
 *    before the given time.  This is conservative in the sense that if
 *    you then use the returned event ID as the sinceWhen parameter of
 *    FSEventStreamCreateRelativeToDevice() that you will not miss any
 *    events that happened since that time.  On the other hand, you
 *    might receive some (harmless) extra events. Beware: there are
 *    things that can cause this to fail to be accurate. For example,
 *    someone might change the system's clock (either backwards or
 *    forwards).  Or an external drive might be used on different
 *    systems without perfectly synchronized clocks.
 *  
 *  Parameters:
 *    
 *    dev:
 *      The dev_t of the device.
 *    
 *    time:
 *      The time as a CFAbsoluteTime whose value is the number of
 *      seconds since Jan 1, 1970 (i.e. a posix style time_t).
 *  
 *  Result:
 *    The last event ID for the given device that was returned before
 *    the given time.
 *  
 *  Availability:
 *    Mac OS X:         in version 10.5 and later in CoreServices.framework
 *    CarbonLib:        not available
 *    Non-Carbon CFM:   not available
 */
extern FSEventStreamEventId 
FSEventsGetLastEventIdForDeviceBeforeTime(
  dev_t            dev,
  CFAbsoluteTime   time)                                      __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_6_0);


/*
 *  FSEventsPurgeEventsForDeviceUpToEventId()
 *  
 *  Discussion:
 *    Purges old events from the persistent per-volume database
 *    maintained by the service. Can only be called by the root user.
 *  
 *  Parameters:
 *    
 *    dev:
 *      The dev_t of the device.
 *    
 *    eventId:
 *      The event ID.
 *  
 *  Result:
 *    True if it succeeds, otherwise False if it fails.
 *  
 *  Availability:
 *    Mac OS X:         in version 10.5 and later in CoreServices.framework
 *    CarbonLib:        not available
 *    Non-Carbon CFM:   not available
 */
extern Boolean 
FSEventsPurgeEventsForDeviceUpToEventId(
  dev_t                  dev,
  FSEventStreamEventId   eventId)                             __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_6_0);


/*
 *  Retain, Release
 */
/*
 *    @function FSEventStreamRetain
 *    Increments the stream's refcount.  The refcount is initially one and is
 *    decremented via FSEventStreamRelease().
 *  
 *    @param streamRef
 *      A valid stream.
 *    
 */
/*
 *  FSEventStreamRetain()
 *  
 *  Availability:
 *    Mac OS X:         in version 10.5 and later in CoreServices.framework
 *    CarbonLib:        not available
 *    Non-Carbon CFM:   not available
 */
extern void 
FSEventStreamRetain(FSEventStreamRef streamRef)               __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_6_0);


/*
 *  FSEventStreamRelease()
 *  
 *  Discussion:
 *    Decrements the stream's refcount.  The refcount is initially one
 *    and is incremented via FSEventStreamRetain().  If the refcount
 *    reaches zero then the stream is deallocated.
 *  
 *  Parameters:
 *    
 *    streamRef:
 *      A valid stream.
 *  
 *  Availability:
 *    Mac OS X:         in version 10.5 and later in CoreServices.framework
 *    CarbonLib:        not available
 *    Non-Carbon CFM:   not available
 */
extern void 
FSEventStreamRelease(FSEventStreamRef streamRef)              __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_6_0);


/*
 *  ScheduleWithRunLoop, UnscheduleFromRunLoop, Invalidate
 */
/*
 *  FSEventStreamScheduleWithRunLoop()
 *  
 *  Discussion:
 *    This function schedules the stream on the specified run loop,
 *    like CFRunLoopAddSource() does for a CFRunLoopSourceRef.  The
 *    caller is responsible for ensuring that the stream is scheduled
 *    on at least one run loop and that at least one of the run loops
 *    on which the stream is scheduled is being run. To start receiving
 *    events on the stream, call FSEventStreamStart(). To remove the
 *    stream from the run loops upon which it has been scheduled, call
 *    FSEventStreamUnscheduleFromRunLoop() or FSEventStreamInvalidate().
 *  
 *  Parameters:
 *    
 *    streamRef:
 *      A valid stream.
 *    
 *    runLoop:
 *      The run loop on which to schedule the stream.
 *    
 *    runLoopMode:
 *      A run loop mode on which to schedule the stream.
 *  
 *  Availability:
 *    Mac OS X:         in version 10.5 and later in CoreServices.framework
 *    CarbonLib:        not available
 *    Non-Carbon CFM:   not available
 */
extern void 
FSEventStreamScheduleWithRunLoop(
  FSEventStreamRef   streamRef,
  CFRunLoopRef       runLoop,
  CFStringRef        runLoopMode) API_DEPRECATED("Use FSEventStreamSetDispatchQueue instead.", macos(10.5, 13.0), ios(6.0,16.0));


/*
 *  FSEventStreamUnscheduleFromRunLoop()
 *  
 *  Discussion:
 *    This function removes the stream from the specified run loop,
 *    like CFRunLoopRemoveSource() does for a CFRunLoopSourceRef.
 *  
 *  Parameters:
 *    
 *    streamRef:
 *      A valid stream.
 *    
 *    runLoop:
 *      The run loop from which to unschedule the stream.
 *    
 *    runLoopMode:
 *      The run loop mode from which to unschedule the stream.
 *  
 *  Availability:
 *    Mac OS X:         in version 10.5 and later in CoreServices.framework
 *    CarbonLib:        not available
 *    Non-Carbon CFM:   not available
 */
extern void 
FSEventStreamUnscheduleFromRunLoop(
  FSEventStreamRef   streamRef,
  CFRunLoopRef       runLoop,
  CFStringRef        runLoopMode) API_DEPRECATED("Use FSEventStreamSetDispatchQueue instead.", macos(10.5, 13.0), ios(6.0,16.0));



/*
 *  FSEventStreamSetDispatchQueue()
 *  
 *  Discussion:
 *    This function schedules the stream on the specified dispatch
 *    queue. The caller is responsible for ensuring that the stream is
 *    scheduled on a dispatch queue and that the queue is started. If
 *    there is a problem scheduling the stream on the queue an error
 *    will be returned when you try to Start the stream. To start
 *    receiving events on the stream, call FSEventStreamStart(). To
 *    remove the stream from the queue on which it was scheduled, call
 *    FSEventStreamSetDispatchQueue() with a NULL queue parameter or
 *    call FSEventStreamInvalidate() which will do the same thing. 
 *    Note: you must eventually call FSEventStreamInvalidate() and it
 *    is an error to call FSEventStreamInvalidate() without having the
 *    stream either scheduled on a runloop or a dispatch queue, so do
 *    not set the dispatch queue to NULL before calling
 *    FSEventStreamInvalidate().
 *  
 *  Parameters:
 *    
 *    streamRef:
 *      A valid stream.
 *    
 *    q:
 *      The dispatch queue to use to receive events (or NULL to to stop
 *      receiving events from the stream).
 *  
 *  Availability:
 *    Mac OS X:         in version 10.6 and later in CoreServices.framework
 *    CarbonLib:        not available
 *    Non-Carbon CFM:   not available
 */
extern void 
FSEventStreamSetDispatchQueue(
  FSEventStreamRef              streamRef,
  dispatch_queue_t __nullable   q)                                      __OSX_AVAILABLE_STARTING(__MAC_10_6, __IPHONE_6_0);


/*
 *  FSEventStreamInvalidate()
 *  
 *  Discussion:
 *    Invalidates the stream, like CFRunLoopSourceInvalidate() does for
 *    a CFRunLoopSourceRef.  It will be unscheduled from any runloops
 *    or dispatch queues upon which it had been scheduled.
 *    FSEventStreamInvalidate() can only be called on the stream after
 *    you have called FSEventStreamScheduleWithRunLoop() or
 *    FSEventStreamSetDispatchQueue().
 *  
 *  Parameters:
 *    
 *    streamRef:
 *      A valid stream.
 *  
 *  Availability:
 *    Mac OS X:         in version 10.5 and later in CoreServices.framework
 *    CarbonLib:        not available
 *    Non-Carbon CFM:   not available
 */
extern void 
FSEventStreamInvalidate(FSEventStreamRef streamRef)           __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_6_0);


/*
 *  Start, Flush, Stop
 */
/*
 *  FSEventStreamStart()
 *  
 *  Discussion:
 *    Attempts to register with the FS Events service to receive events
 *    per the parameters in the stream. FSEventStreamStart() can only
 *    be called once the stream has been scheduled on at least one
 *    runloop, via FSEventStreamScheduleWithRunLoop(). Once started,
 *    the stream can be stopped via FSEventStreamStop().
 *  
 *  Parameters:
 *    
 *    streamRef:
 *      A valid stream.
 *  
 *  Result:
 *    True if it succeeds, otherwise False if it fails.  It ought to
 *    always succeed, but in the event it does not then your code
 *    should fall back to performing recursive scans of the directories
 *    of interest as appropriate.
 *  
 *  Availability:
 *    Mac OS X:         in version 10.5 and later in CoreServices.framework
 *    CarbonLib:        not available
 *    Non-Carbon CFM:   not available
 */
extern Boolean 
FSEventStreamStart(FSEventStreamRef streamRef)                __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_6_0);


/*
 *  FSEventStreamFlushAsync()
 *  
 *  Discussion:
 *    Asks the FS Events service to flush out any events that have
 *    occurred but have not yet been delivered, due to the latency
 *    parameter that was supplied when the stream was created.  This
 *    flushing occurs asynchronously -- do not expect the events to
 *    have already been delivered by the time this call returns.
 *    FSEventStreamFlushAsync() can only be called after the stream has
 *    been started, via FSEventStreamStart().
 *  
 *  Parameters:
 *    
 *    streamRef:
 *      A valid stream.
 *  
 *  Result:
 *    The largest event id of any event ever queued for this stream,
 *    otherwise zero if no events have been queued for this stream.
 *  
 *  Availability:
 *    Mac OS X:         in version 10.5 and later in CoreServices.framework
 *    CarbonLib:        not available
 *    Non-Carbon CFM:   not available
 */
extern FSEventStreamEventId 
FSEventStreamFlushAsync(FSEventStreamRef streamRef)           __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_6_0);


/*
 *  FSEventStreamFlushSync()
 *  
 *  Discussion:
 *    Asks the FS Events service to flush out any events that have
 *    occurred but have not yet been delivered, due to the latency
 *    parameter that was supplied when the stream was created.  This
 *    flushing occurs synchronously -- by the time this call returns,
 *    your callback will have been invoked for every event that had
 *    already occurred at the time you made this call.
 *    FSEventStreamFlushSync() can only be called after the stream has
 *    been started, via FSEventStreamStart().
 *  
 *  Parameters:
 *    
 *    streamRef:
 *      A valid stream.
 *  
 *  Availability:
 *    Mac OS X:         in version 10.5 and later in CoreServices.framework
 *    CarbonLib:        not available
 *    Non-Carbon CFM:   not available
 */
extern void 
FSEventStreamFlushSync(FSEventStreamRef streamRef)            __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_6_0);


/*
 *  FSEventStreamStop()
 *  
 *  Discussion:
 *    Unregisters with the FS Events service.  The client callback will
 *    not be called for this stream while it is stopped.
 *    FSEventStreamStop() can only be called if the stream has been
 *    started, via FSEventStreamStart(). Once stopped, the stream can
 *    be restarted via FSEventStreamStart(), at which point it will
 *    resume receiving events from where it left off ("sinceWhen").
 *  
 *  Parameters:
 *    
 *    streamRef:
 *      A valid stream.
 *  
 *  Availability:
 *    Mac OS X:         in version 10.5 and later in CoreServices.framework
 *    CarbonLib:        not available
 *    Non-Carbon CFM:   not available
 */
extern void 
FSEventStreamStop(FSEventStreamRef streamRef)                 __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_6_0);


/*
 *  Debugging
 */
/*
 *  FSEventStreamShow()
 *  
 *  Discussion:
 *    Prints a description of the supplied stream to stderr. For
 *    debugging only.
 *  
 *  Parameters:
 *    
 *    streamRef:
 *      A valid stream.
 *  
 *  Availability:
 *    Mac OS X:         in version 10.5 and later in CoreServices.framework
 *    CarbonLib:        not available
 *    Non-Carbon CFM:   not available
 */
extern void 
FSEventStreamShow(ConstFSEventStreamRef streamRef)            __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_6_0);


/*
 *  FSEventStreamCopyDescription()
 *  
 *  Discussion:
 *    Returns a CFStringRef containing the description of the supplied
 *    stream. For debugging only.
 *  
 *  Result:
 *    A CFStringRef containing the description of the supplied stream.
 *    Ownership follows the Copy rule.
 *  
 *  Availability:
 *    Mac OS X:         in version 10.5 and later in CoreServices.framework
 *    CarbonLib:        not available
 *    Non-Carbon CFM:   not available
 */
extern CF_RETURNS_RETAINED CFStringRef 
FSEventStreamCopyDescription(ConstFSEventStreamRef streamRef) __OSX_AVAILABLE_STARTING(__MAC_10_5, __IPHONE_6_0);


/*
 * FSEventStreamSetExclusionPaths()
 *
 * Discussion: 
 *    Sets directories to be filtered from the EventStream.
 *    A maximum of 8 directories maybe specified.
 *
 * Result:
 *    True if it succeeds, otherwise False if it fails.
 *     
 * Availability:
 *    Mac OS X:         in version 10.9 and later in CoreServices.framework
 *    CarbonLib:        not available
 *    Non-Carbon CFM:   not available
 */
extern Boolean 
FSEventStreamSetExclusionPaths(FSEventStreamRef streamRef, CFArrayRef pathsToExclude) __OSX_AVAILABLE_STARTING(__MAC_10_9, __IPHONE_8_0);


#if PRAGMA_ENUM_ALWAYSINT
    #pragma enumsalwaysint reset
#endif

#pragma pack(pop)

CF_ASSUME_NONNULL_END

#ifdef __cplusplus
}
#endif

#endif /* __FSEVENTS__ */

