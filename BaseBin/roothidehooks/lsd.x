#include <Foundation/Foundation.h>

#include <spawn.h>
#include <roothide.h>

#include "common.h"

extern char **environ;

#pragma GCC diagnostic ignored "-Wobjc-method-access"
#pragma GCC diagnostic ignored "-Wunused-variable"

/*lsd can only get path for normal app via proc_pidpath, or we can use
  xpc_connection_get_audit_token([connection _xpcConnection], &token) //_LSCopyExecutableURLForXPCConnection
  proc_pidpath_audittoken(tokenarg, buffer, size) //_LSCopyExecutableURLForAuditToken 
  */

@interface LSApplicationProxy : NSObject
+ (id)applicationProxyForIdentifier:(id)arg1;
- (NSURL*)bundleURL;
@end

@interface LSApplicationWorkspace : NSObject
+ (LSApplicationWorkspace*)defaultWorkspace;
- (NSArray*)applicationsAvailableForHandlingURLScheme:(NSString*)scheme;
- (NSArray*)applicationsAvailableForOpeningURL:(NSURL*)url legacySPI:(BOOL)legacySPI;
- (NSArray*)applicationsAvailableForOpeningURL:(NSURL*)url;
@end

BOOL isJailbreakURLScheme(NSString* scheme)
{
	NSArray* apps = [[NSClassFromString(@"LSApplicationWorkspace") defaultWorkspace] applicationsAvailableForHandlingURLScheme:scheme];
	for(id app in apps) //LSApplicationProxy
	{
		NSURL* bundleURL = [app performSelector:@selector(bundleURL)];
		if(!bundleURL) continue;

		if(isJailbreakBundlePath(bundleURL.path.fileSystemRepresentation)) {
			return YES;
		}
	}
	return NO;
}

static const void *kBlockSchemeTagKey = &kBlockSchemeTagKey;

%hook _LSURLOverride
-(id)initWithOriginalURL:(NSURL*)url
{
	NSNumber* tag = objc_getAssociatedObject(url, kBlockSchemeTagKey);
	if(tag && tag.boolValue) {
		NSLog(@"block -[LSURLOverride initWithOriginalURL:] %@", url);
		return nil;
	}
	return %orig;
}
%end

%hook _LSCanOpenURLManager

-(void*)getIsURL:(NSURL*)url alwaysCheckable:(BOOL*)pCheckable hasHandler:(BOOL*)pHasHandler
{
	BOOL _checkable = NO;
	BOOL _hasHandler = NO;
	void* result = %orig(url, &_checkable, &_hasHandler);
	NSLog(@"getIsURL:%@ alwaysCheckable:%d hasHandler:%d", url, _checkable, _hasHandler);

	if(_checkable || _hasHandler)
	{
		NSNumber* tag = objc_getAssociatedObject(url, kBlockSchemeTagKey);
		if(tag && tag.boolValue) {
			NSLog(@"block -[_LSCanOpenURLManager getIsURL:alwaysCheckable:hasHandler:] %@", url);
			_hasHandler = NO;
			_checkable = NO;
		}
	}

	if(pCheckable) *pCheckable = _checkable;
	if(pHasHandler) *pHasHandler = _hasHandler;
	return result;
}

- (BOOL)canOpenURL:(NSURL*)url publicSchemes:(BOOL)ispublic privateSchemes:(BOOL)isprivate XPCConnection:(NSXPCConnection*)connection error:(NSError**)perror
{
	BOOL blocked = NO;
	
	if(connection) //connection=nil if comes from lsd server
	{
		pid_t pid = connection.processIdentifier;

		NSLog(@"canOpenURL:%@ publicSchemes:%d privateSchemes:%d XPCConnection:%@ proc:%d,%s", url, ispublic, isprivate, connection, pid, proc_get_path(pid,NULL));
		//if(connection) NSLog(@"canOpenURL connection=%@", connection);

		if(jbclient_blacklist_check_pid(pid)==true)
		{
			if(isJailbreakURLScheme(url.scheme))
			{
				NSLog(@"block canOpenURL:%@", url);

				objc_setAssociatedObject(url, kBlockSchemeTagKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

				blocked = YES;
			}
		}
	}

	BOOL ret = %orig;
	if(blocked) {
		assert(ret == NO);
	}
	return ret;
}

%end //%hook _LSCanOpenURLManager


@interface _LSDOpenClient : NSObject
@property(retain,readonly) NSXPCConnection* XPCConnection;
@end

%hook _LSDOpenClient

-(void)openApplicationWithIdentifier:(NSString*)identifier options:(id)options useClientProcessHandle:(BOOL)useClientProcessHandle completionHandler:(void(^)(BOOL,NSError*))completionHandler
{
	BOOL blocked = NO;

	if(self.XPCConnection)
	{
		pid_t pid = self.XPCConnection.processIdentifier;

		NSLog(@"_LSDOpenClient openApplicationWithIdentifier:%@ options:%@ useClientProcessHandle:%d completionHandler:%p XPCConnection=%p proc:%d,%s", identifier, options, useClientProcessHandle, completionHandler, self.XPCConnection, pid, proc_get_path(pid,NULL));

		if(jbclient_blacklist_check_pid(pid)==true)
		{
			LSApplicationProxy* appProxy = [NSClassFromString(@"LSApplicationProxy") applicationProxyForIdentifier:identifier];
			if(appProxy && isJailbreakBundlePath(appProxy.bundleURL.path.fileSystemRepresentation))
			{
				NSLog(@"_LSDOpenClient: block openApplicationWithIdentifier:%@", identifier);

				useClientProcessHandle = YES;

				blocked = YES;
			}
		}
	}

	id newcallback = ^(BOOL success, NSError* error) {
		NSLog(@"_LSDOpenClient completionHandler(%@) success:%d error:%@", identifier, success, error);

		if(blocked) {
			assert(success == NO);
		}

		return completionHandler(success, error);
	};

	%orig(identifier, options, useClientProcessHandle, newcallback);
}

//16.2(?)+
-(void)openURL:(NSURL*)url fileHandle:(id)fileHandle options:(id)options completionHandler:(void(^)(BOOL,NSError*))completionHandler
{
	BOOL blocked = NO;

	if(self.XPCConnection)
	{
		pid_t pid = self.XPCConnection.processIdentifier;

		NSLog(@"_LSDOpenClient openURL:%@ fileHandle:%@ options:%@ completionHandler:%p XPCConnection=%p proc:%d,%s", url, fileHandle, options, completionHandler, self.XPCConnection, pid, proc_get_path(pid,NULL));

		if(jbclient_blacklist_check_pid(pid)==true)
		{
			if(isJailbreakURLScheme(url.scheme))
			{
				NSLog(@"_LSDOpenClient: block openURL:%@", url);

				objc_setAssociatedObject(url, kBlockSchemeTagKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

				blocked = YES;
			}
		}
	}

	id newcallback = ^(BOOL success, NSError* error) {
		NSLog(@"_LSDOpenClient completionHandler(%@) success:%d result:%@", url, success, error);
		
		if(blocked) {
			assert(success == NO);
		}

		return completionHandler(success, error);
	};

	%orig(url, fileHandle, options, newcallback);
}

//15.0~16.0(?)
- (void)openURL:(NSURL*)url options:(id)options completionHandler:(void(^)(BOOL,NSError*))completionHandler
{
	BOOL blocked = NO;

	if(self.XPCConnection)
	{
		pid_t pid = self.XPCConnection.processIdentifier;

		NSLog(@"_LSDOpenClient openURL:%@ options:%@ completionHandler:%p XPCConnection=%p proc:%d,%s", url, options, completionHandler, self.XPCConnection, pid, proc_get_path(pid,NULL));

		if(jbclient_blacklist_check_pid(pid)==true)
		{
			if(isJailbreakURLScheme(url.scheme))
			{
				NSLog(@"_LSDOpenClient: block openURL:%@", url);

				objc_setAssociatedObject(url, kBlockSchemeTagKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

				blocked = YES;
			}
		}
	}

	id newcallback = ^(BOOL success, NSError* error) {
		NSLog(@"_LSDOpenClient completionHandler(%@) success:%d result:%@", url, success, error);
		
		if(blocked) {
			assert(success == NO);
		}

		return completionHandler(success, error);
	};

	%orig(url, options, newcallback);
}

%end //%hook _LSDOpenClient

%group UTTypeHooks

@interface UTTypeRecord : NSObject
+ (id)typeRecordWithIdentifier:(id)identifier;
- (unsigned int)tableID;
@end

@interface _UTDeclaredTypeRecord : NSObject
- (id)_initWithContext:(void*)ctx tableID:(unsigned int)tableID unitID:(unsigned int)unitID;
- (BOOL)isDeclared;
- (BOOL)isCoreType;
- (BOOL)isInPublicDomain;
- (id)identifier;
- (id)declaringBundleRecord;
- (unsigned int)unitID;
- (unsigned int)_rawFlags;
@end

@interface LSBundleRecord : NSObject
- (NSURL*)URL;
@end

@interface _LSDReadClient : NSObject
- (NSXPCConnection*)XPCConnection;
@end

static __thread BOOL g_utrHide = NO;   // raised by the _LSDReadClient hooks for blacklisted requests
static __thread int  g_utrBusy = 0;    // >0 while we ourselves touch the DB, to keep our access out of the filters

static BOOL utrFilterActive(void) { return g_utrHide && !g_utrBusy; }

static pid_t utrClientPid(_LSDReadClient* client)
{
	NSXPCConnection* conn = [client XPCConnection];
	return conn ? conn.processIdentifier : -1;
}

static BOOL utrHideClientBlacklisted(_LSDReadClient* client)
{
	pid_t pid = utrClientPid(client);
	if(pid>0 && jbclient_blacklist_check_pid(pid)) {
		return YES;
	}
	return NO;
}

// type-units table id; constant for the database. Read once, off the hot path, via a public accessor.
static unsigned int utrTypeTableID(void)
{
	static unsigned int tid = 0;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		// guard this probe's own nested lookup so it is never filtered, independent of the caller.
		// g_utrBusy is a counter, so this nests cleanly inside utrUnitIsJailbreak's busy region.
		g_utrBusy++;
		tid = (unsigned int)[[NSClassFromString(@"UTTypeRecord") typeRecordWithIdentifier:@"public.data"] tableID];
		g_utrBusy--;
	});
	return tid;
}

// YES only when `rec` is a *declared* type whose active declaring bundle is a jailbreak bundle,
// and which is not an Apple core / public-domain type (those are never touched -> #3).
static BOOL utrRecordIsFromJailbreakApp(_UTDeclaredTypeRecord* rec)
{
	if (![rec isDeclared]) return NO;                // dynamic/undeclared -> already the "absent" shape
	if ([rec isCoreType]) return NO;                 // Apple core type -> never touched (#3)
	if ([rec isInPublicDomain]) return NO;           // public.* -> never touched (#3)
	LSBundleRecord* bundleRec = [rec declaringBundleRecord];
	NSURL* url = [bundleRec URL];
	if (![url isKindOfClass:[NSURL class]] || !url.isFileURL) return NO;
	if (!isJailbreakBundlePath(url.path.fileSystemRepresentation)) return NO;

	NSLog(@"[UTType] hide type id=%@ bundle=%@", [rec identifier], url);
	return YES;
}

// build a record for an enumerated unitID and decide if it belongs to a jailbreak app.
static BOOL utrUnitIsJailbreak(void* db, intptr_t unitID)
{
	BOOL result = NO;
	g_utrBusy++; // keep our own nested DB access out of the filters
	unsigned int tid = utrTypeTableID();
	if (tid) {
		void* ctx = db; // _initWithContext: reads *(void**)ctx (offset 0) == db
		_UTDeclaredTypeRecord* rec = [[NSClassFromString(@"_UTDeclaredTypeRecord") alloc]
					_initWithContext:(void*)&ctx tableID:tid unitID:(unsigned int)unitID];
		result = utrRecordIsFromJailbreakApp(rec);
	}
	g_utrBusy--;
	return result;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////

typedef intptr_t (^UTREnumBlock)(intptr_t a2, intptr_t unitID, const void* unitBytes, void* a5);
%hookf(void, _UTEnumerateTypesForTag, void* db, void* tagClass, void* tag, id block)
{
	if (!utrFilterActive() || !block) { %orig; return; }

	UTREnumBlock orig = (UTREnumBlock)block;
	UTREnumBlock wrapper = ^intptr_t(intptr_t a2, intptr_t unitID, const void* unitBytes, void* a5) {
		if (utrUnitIsJailbreak(db, unitID)) return 0;        // drop -> continue enumeration, nothing recorded
		return orig(a2, unitID, unitBytes, a5);              // forward to the original callback
	};
	%orig(db, tagClass, tag, wrapper);
}

%hookf(void, _UTEnumerateTypesForIdentifier, void* db, long identStrId, id block)
{
	if (!utrFilterActive() || !block) { %orig; return; }

	UTREnumBlock orig = (UTREnumBlock)block;
	UTREnumBlock wrapper = ^intptr_t(intptr_t a2, intptr_t unitID, const void* unitBytes, void* a5) {
		if (utrUnitIsJailbreak(db, unitID)) return 0;
		return orig(a2, unitID, unitBytes, a5);
	};
	%orig(db, identStrId, wrapper);
}

typedef void (^UTRConformBlock)(intptr_t unitID, const void* unitBytes, intptr_t kind, unsigned char* outStop);
%hookf(void, _UTTypeSearchConformingTypesWithBlock, void* db, long unitID, long flags, long arg4, id block)
{
	if (!utrFilterActive() || !block) { %orig; return; }

	UTRConformBlock orig = (UTRConformBlock)block;
	UTRConformBlock wrapper = ^void(intptr_t uid, const void* unitBytes, intptr_t kind, unsigned char* outStop) {
		if (utrUnitIsJailbreak(db, uid)) return;             // drop conforming JB type -> outStop stays 0, keep enumerating
		orig(uid, unitBytes, kind, outStop);                 // forward to the original callback
	};
	%orig(db, unitID, flags, arg4, wrapper);
}

// parents/forward conformance: filters JB parent types out of related-types (degree>0)
// and out of a record's serialized parentTypeIdentifiers/conformsTo list.
// _UTTypeConformsTo's boolean verdict goes through ...Common (not WithBlock), so it is unaffected.
%hookf(void, _UTTypeSearchConformsToTypesWithBlock, void* db, long unitID, long flags, long arg4, id block)
{
	if (!utrFilterActive() || !block) { %orig; return; }

	UTRConformBlock orig = (UTRConformBlock)block;
	UTRConformBlock wrapper = ^void(intptr_t uid, const void* unitBytes, intptr_t kind, unsigned char* outStop) {
		if (utrUnitIsJailbreak(db, uid)) return;             // drop conforming-to (parent) JB type -> keep enumerating
		orig(uid, unitBytes, kind, outStop);                 // forward to the original callback
	};
	%orig(db, unitID, flags, arg4, wrapper);
}


%hookf(void, _LSSchemaCacheRead, void* a1, id block)
{
	if (utrFilterActive()) return; // force cache miss -> recompute (filtered)
	%orig(a1, block);
}

%hookf(void, _LSSchemaCacheWrite, void* a1, id block)
{
	if (utrFilterActive()) return; // don't cache the hidden result
	%orig(a1, block);
}

%hook _LSDReadClient
- (void)getTypeRecordWithTag:(id)tag ofClass:(id)_class conformingToIdentifier:(id)identifier completionHandler:(void(^)(id))handler
{
	if (!utrHideClientBlacklisted(self)) { %orig; return; }
	NSLog(@"[UTType] getTypeRecordWithTag:%@ ofClass:%@ conforming:%@ pid=%d", tag, _class, identifier, utrClientPid(self));
	g_utrHide = YES;
	%orig;
	g_utrHide = NO;
}

- (void)getTypeRecordsWithTag:(id)tag ofClass:(id)_class conformingToIdentifier:(id)identifier completionHandler:(void(^)(id))handler
{
	if (!utrHideClientBlacklisted(self)) { %orig; return; }
	NSLog(@"[UTType] getTypeRecordsWithTag:%@ ofClass:%@ conforming:%@ pid=%d", tag, _class, identifier, utrClientPid(self));
	g_utrHide = YES;
	%orig;
	g_utrHide = NO;
}

- (void)getTypeRecordWithIdentifier:(id)identifier allowUndeclared:(BOOL)allowUndeclared completionHandler:(void(^)(id))handler
{
	if (!utrHideClientBlacklisted(self)) { %orig; return; }
	NSLog(@"[UTType] getTypeRecordWithIdentifier:%@ allowUndeclared:%d pid=%d", identifier, allowUndeclared, utrClientPid(self));
	g_utrHide = YES;
	%orig;
	g_utrHide = NO;
}

- (void)getTypeRecordsWithIdentifiers:(id)identifiers completionHandler:(void(^)(id))handler
{
	if (!utrHideClientBlacklisted(self)) { %orig; return; }
	NSLog(@"[UTType] getTypeRecordsWithIdentifiers:%@ pid=%d", identifiers, utrClientPid(self));
	g_utrHide = YES;
	%orig;
	g_utrHide = NO;
}

- (void)getTypeRecordForImportedTypeWithIdentifier:(id)identifier conformingToIdentifier:(id)conforming completionHandler:(void(^)(id))handler
{
	if (!utrHideClientBlacklisted(self)) { %orig; return; }
	NSLog(@"[UTType] getTypeRecordForImportedTypeWithIdentifier:%@ conforming:%@ pid=%d", identifier, conforming, utrClientPid(self));
	g_utrHide = YES;
	%orig;
	g_utrHide = NO;
}

- (void)getRelatedTypesOfTypeWithIdentifier:(id)identifier maximumDegreeOfSeparation:(NSInteger)degree completionHandler:(void(^)(id, id))handler
{
	if (!utrHideClientBlacklisted(self)) { %orig; return; }
	NSLog(@"[UTType] getRelatedTypesOfTypeWithIdentifier:%@ degree:%ld pid=%d", identifier, (long)degree, utrClientPid(self));
	g_utrHide = YES;
	%orig;
	g_utrHide = NO;
}

- (void)getWhetherTypeIdentifier:(id)identifier conformsToTypeIdentifier:(id)other completionHandler:(void(^)(id))handler
{
	if (!utrHideClientBlacklisted(self)) { %orig; return; }
	NSLog(@"[UTType] getWhetherTypeIdentifier:%@ conformsToTypeIdentifier:%@ pid=%d", identifier, other, utrClientPid(self));
	g_utrHide = YES;
	%orig;
	g_utrHide = NO;
}

- (void)getResourceValuesForKeys:(id)keys URL:(id)url preferredLocalizations:(id)locs completionHandler:(void(^)(id, id, id))handler
{
	if (!utrHideClientBlacklisted(self)) { %orig; return; }
	NSLog(@"[UTType] getResourceValuesForKeys:%@ URL:%@ pid=%d", keys, url, utrClientPid(self));
	g_utrHide = YES;
	%orig;
	g_utrHide = NO;
}

- (void)getBoundIconInfoForDocumentProxy:(id)documentProxy completionHandler:(void(^)(id, id))handler
{
	if (!utrHideClientBlacklisted(self)) { %orig; return; }
	NSLog(@"[UTType] getBoundIconInfoForDocumentProxy:%@ pid=%d", documentProxy, utrClientPid(self));
	g_utrHide = YES;
	%orig;
	g_utrHide = NO;
}
%end //%hook _LSDReadClient

%end // %group UTTypeHooks

%hook _LSQueryContext

@interface LSPlugInQueryWithUnits : NSObject
-(id)initWithPlugInUnits:(id)units forDatabaseWithUUID:(id)dbUUID;
@end

@interface _LSQueryContext : NSObject
-(NSMutableDictionary*)_resolveQueries:(NSMutableSet*)queries XPCConnection:(NSXPCConnection*)connection error:(NSError**)perror;
@end

-(NSMutableDictionary*)_resolveQueries:(NSMutableSet*)queries XPCConnection:(NSXPCConnection*)connection error:(NSError**)perror 
{
	NSMutableDictionary* result = %orig;
	/*
	result: @{
		queries[0]: @[data1, data2, ...],
		queries[1]: @[data1, data2, ...],
	}
	*/

	if(!result || !connection) {
		return result;
	}

	pid_t pid = connection.processIdentifier;

	if(jbclient_blacklist_check_pid(pid)==false) {
		return result;
	}

	NSLog(@"_resolveQueries:%@:%@ XPCConnection:%@ result=%@/%ld proc:%d,%s", [queries class], queries, connection, result.class, result.count, pid, proc_get_path(pid,NULL));
	//NSLog(@"result=%@, %@", result.allKeys, result.allValues);
	for(id key in result)
	{
		NSLog(@"key type: %@, value type: %@", [key class], [result[key] class]);
		if([key isKindOfClass:NSClassFromString(@"LSPlugInQueryWithUnits")]
			|| [key isKindOfClass:NSClassFromString(@"LSPlugInQueryWithIdentifier")]
			|| [key isKindOfClass:NSClassFromString(@"LSPlugInQueryWithQueryDictionary")])
		{
			NSMutableArray* plugins = result[key];
			NSLog(@"plugins bundle count=%ld", plugins.count);

			NSMutableIndexSet* removed = [[NSMutableIndexSet alloc] init];
			for (int i=0; i<[plugins count]; i++) 
			{
				id plugin = plugins[i]; //LSPlugInKitProxy
				id appbundle = [plugin performSelector:@selector(containingBundle)];
				// NSLog(@"plugin=%@, %@", plugin, appbundle);
				if(!appbundle) continue;

				NSURL* bundleURL = [appbundle performSelector:@selector(bundleURL)];
				if(isJailbreakBundlePath(bundleURL.path.fileSystemRepresentation)) {
					NSLog(@"remove plugin %@ (%@)", plugin, bundleURL);
					[removed addIndex:i];
				}
			}

			[plugins removeObjectsAtIndexes:removed];
			NSLog(@"new plugins bundle count=%ld", plugins.count);

			if([key isKindOfClass:NSClassFromString(@"LSPlugInQueryWithUnits")])
			{
				//NSLog(@"_pluginUnits=%@", [key valueForKey:@"_pluginUnits"]);
				NSLog(@"LSPlugInQueryWithUnits: _pluginUnits count=%ld", [[key valueForKey:@"_pluginUnits"] count]);

				NSMutableArray* units = [[key valueForKey:@"_pluginUnits"] mutableCopy];
				[units removeObjectsAtIndexes:removed];
				[key setValue:[units copy] forKey:@"_pluginUnits"];

				NSLog(@"LSPlugInQueryWithUnits: new _pluginUnits count=%ld", [[key valueForKey:@"_pluginUnits"] count]);
			}
			else if([key isKindOfClass:NSClassFromString(@"LSPlugInQueryWithQueryDictionary")])
			{
				NSLog(@"LSPlugInQueryWithQueryDictionary: _queryDict=%@", [key valueForKey:@"_queryDict"]);
				NSLog(@"LSPlugInQueryWithQueryDictionary: _extensionIdentifiers=%@", [key valueForKey:@"_extensionIdentifiers"]);
				NSLog(@"LSPlugInQueryWithQueryDictionary: _extensionPointIdentifiers=%@", [key valueForKey:@"_extensionPointIdentifiers"]);
			}
			else if([key isKindOfClass:NSClassFromString(@"LSPlugInQueryWithIdentifier")])
			{
				NSLog(@"LSPlugInQueryWithIdentifier: _identifier=%@", [key valueForKey:@"_identifier"]);
			}
		}
		else if([key isKindOfClass:NSClassFromString(@"LSPlugInQueryAllUnits")])
		{
			NSMutableArray* unitsArray = result[key];
			for (int i=0; i<[unitsArray count]; i++)
			{
				id unitsResult = unitsArray[i]; //LSPlugInQueryAllUnitsResult

				NSUUID* _dbUUID = [unitsResult valueForKey:@"_dbUUID"];
				NSArray* _pluginUnits = [unitsResult valueForKey:@"_pluginUnits"];
				NSLog(@"LSPlugInQueryAllUnits: _dbUUID=%@, _pluginUnits count=%ld", _dbUUID, _pluginUnits.count);
				id unitQuery = [[NSClassFromString(@"LSPlugInQueryWithUnits") alloc] initWithPlugInUnits:_pluginUnits forDatabaseWithUUID:_dbUUID];
				NSMutableDictionary* queriesResult = [self _resolveQueries:[NSSet setWithObject:unitQuery].mutableCopy XPCConnection:connection error:perror];
				if(queriesResult)
				{
					for(id queryKey in queriesResult)
					{
						NSArray* new_pluginUnits = [queryKey valueForKey:@"_pluginUnits"];
						[unitsResult setValue:new_pluginUnits forKey:@"_pluginUnits"];
						NSLog(@"LSPlugInQueryAllUnits: new _pluginUnits count=%ld", new_pluginUnits.count);
					}
				}
			}
		}
	}

	return result;
}

%end //%hook _LSQueryContext


//or -[Copier initWithSourceURL:uniqueIdentifier:destURL:callbackTarget:selector:options:] in transitd
NSURL* (*orig_LSGetInboxURLForBundleIdentifier)(NSString* bundleIdentifier)=NULL;
NSURL* new_LSGetInboxURLForBundleIdentifier(NSString* bundleIdentifier)
{
	NSURL* pathURL = orig_LSGetInboxURLForBundleIdentifier(bundleIdentifier);

	if( ![bundleIdentifier hasPrefix:@"com.apple."] 
			&& [pathURL.path hasPrefix:@"/var/mobile/Library/Application Support/Containers/"])
	{
		NSLog(@"redirect Inbox %@ : %@", bundleIdentifier, pathURL);
		pathURL = [NSURL fileURLWithPath:jbroot(pathURL.path)]; //require unsandboxing file-write-read for jbroot:/var/
	}

	return pathURL;
}

int (*orig_LSServer_RebuildApplicationDatabases)()=NULL;
int new_LSServer_RebuildApplicationDatabases()
{
	int r = orig_LSServer_RebuildApplicationDatabases();

	if(access(jbroot("/.disable_auto_uicache"), F_OK) == 0) return r;

	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		// Ensure jailbreak apps are readded to icon cache after the system reloads it
		// A bit hacky, but works
		char* const args[] = {"/usr/bin/uicache", "-a", NULL};
		const char *uicachePath = jbroot(args[0]);
		if (access(uicachePath, F_OK) == 0) {
			pid_t pid=0;
			int spawnerr = posix_spawn(&pid, uicachePath, NULL, NULL, args, environ);
			if(spawnerr==0) {
				wait_for_exit(pid);
			}
		}
	});

	return r;
}

void lsdInit(void)
{
	NSLog(@"lsdInit...");

	MSImageRef coreServicesImage = MSGetImageByName("/System/Library/Frameworks/CoreServices.framework/CoreServices");

	void* _LSGetInboxURLForBundleIdentifier = MSFindSymbol(coreServicesImage, "__LSGetInboxURLForBundleIdentifier");
	NSLog(@"coreServicesImage=%p, _LSGetInboxURLForBundleIdentifier=%p", coreServicesImage, _LSGetInboxURLForBundleIdentifier);
	if(_LSGetInboxURLForBundleIdentifier)
	{
		MSHookFunction(_LSGetInboxURLForBundleIdentifier, (void *)&new_LSGetInboxURLForBundleIdentifier, (void **)&orig_LSGetInboxURLForBundleIdentifier);
	}
	
	void* _LSServer_RebuildApplicationDatabases = MSFindSymbol(coreServicesImage, "__LSServer_RebuildApplicationDatabases");
	NSLog(@"coreServicesImage=%p, _LSServer_RebuildApplicationDatabases=%p", coreServicesImage, _LSServer_RebuildApplicationDatabases);
	if(_LSServer_RebuildApplicationDatabases)
	{
		MSHookFunction(_LSServer_RebuildApplicationDatabases, (void *)&new_LSServer_RebuildApplicationDatabases, (void **)&orig_LSServer_RebuildApplicationDatabases);
	}

	void* _LSSchemaCacheRead = MSFindSymbol(coreServicesImage, "__LSSchemaCacheRead");
	void* _LSSchemaCacheWrite = MSFindSymbol(coreServicesImage, "__LSSchemaCacheWrite");
	void* _UTEnumerateTypesForTag = MSFindSymbol(coreServicesImage, "__UTEnumerateTypesForTag");
	void* _UTEnumerateTypesForIdentifier = MSFindSymbol(coreServicesImage, "__UTEnumerateTypesForIdentifier");
	void* _UTTypeSearchConformingTypesWithBlock = MSFindSymbol(coreServicesImage, "__UTTypeSearchConformingTypesWithBlock");
	void* _UTTypeSearchConformsToTypesWithBlock = MSFindSymbol(coreServicesImage, "__UTTypeSearchConformsToTypesWithBlock");
	if(_LSSchemaCacheRead && _LSSchemaCacheWrite && _UTEnumerateTypesForTag && _UTEnumerateTypesForIdentifier && _UTTypeSearchConformingTypesWithBlock && _UTTypeSearchConformsToTypesWithBlock)
	{
		NSLog(@"UTTypeHooks: installing");
		%init(UTTypeHooks, _LSSchemaCacheRead=_LSSchemaCacheRead, _LSSchemaCacheWrite=_LSSchemaCacheWrite, _UTEnumerateTypesForTag=_UTEnumerateTypesForTag, _UTEnumerateTypesForIdentifier=_UTEnumerateTypesForIdentifier, _UTTypeSearchConformingTypesWithBlock=_UTTypeSearchConformingTypesWithBlock, _UTTypeSearchConformsToTypesWithBlock=_UTTypeSearchConformsToTypesWithBlock);
	}

	%init();
}
