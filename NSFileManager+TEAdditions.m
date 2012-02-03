//
//  NSFileManager+Trash.m
//  Espionage
//
//  Created by Greg Slepak on 6/2/08.
//  Copyright 2008 Tao Effect LLC. All rights reserved.
//
// see: http://www.cocoadev.com/index.pl?MoveToTrash

#import <objc/objc-runtime.h>
#import <Foundation/Foundation.h>
#import <CoreServices/CoreServices.h>
#import <unistd.h>
#import <stdio.h>
#import <sys/stat.h>
#import <sys/mount.h>
#import <sys/xattr.h>
#import "du_modified.h"
#import "NSFileManager+TEAdditions.h"
#import "Common.h"

#define SECTORS_TO_MEGS(_s) ( (_s * 512) / (1024 * 1024) )
#define MEGS_TO_SECTORS(_m) ( ((1024ULL * 1024ULL) * _m) / 512ULL )

@implementation NSFileManager (TEAdditions)

- (NSString*)moveFileUpADirectory:(NSString *)itemPath
{
	return [self moveFile:itemPath toDirectory:[[itemPath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent]];
}

- (NSString*)moveFile:(NSString *)itemPath toDirectory:(NSString *)dir
{
	NSString *itemName = [itemPath lastPathComponent];
	NSString *dest = [dir stringByAppendingPathComponent:itemName];
	OSStatus err = noErr;
	
	log_debug("moving item (%@) to: %@", itemPath, dest);
	
	FAIL_IF([self fileExistsAtPath:dest], err = fidExists; log_err("can't move, destination exists: %@", dest));
	
	DO_FAILABLE_SUB(err, errno, rename, [itemPath fileSystemRepresentation], [dest fileSystemRepresentation]);
	//	BOOL success = [self movePath:itemPath toPath:dest handler:nil];
	//	if ( !success ) log_err("couldn't move file up a directory: '%@'", itemPath);
	
fail_label:
	return err == noErr ? dest : nil;
}

- (NSString*)renameItemAtPath:(NSString *)path to:(NSString *)newName
{
	NSString *newPath = [[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:newName];
	log_debug("renaming '%@' to '%@'", path, newPath);
	
	if ( [self fileExistsAtPath:newPath] ) {
		log_err("file exists: %@", newPath);
		return nil;
	}
	if ( rename([path fileSystemRepresentation], [newPath fileSystemRepresentation]) != 0 ) {
		log_errp("couldn't rename '%@' to '%@'", path, newPath);
		return nil;
	}
	return newPath;
}

- (NSString*)forceRenameItemAtPath:(NSString *)path to:(NSString *)newName
{
	NSString *destination = [[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:newName];
	
	if ( [self fileExistsAtPath:destination] )
	{
		log_info("rename of '%@' to '%@' being forced because of existing file", path, destination);
		NSString *pathExtention = [destination pathExtension];
		NSString *pathWithoutExtention = [destination stringByDeletingPathExtension];
		NSString *now = [[NSCalendarDate calendarDate] descriptionWithCalendarFormat:@" %H-%M-%S"];
		
		destination = [pathWithoutExtention stringByAppendingString:now];
		
		if ( ! [pathExtention isEqualToString:@""] )
			destination = [destination stringByAppendingPathExtension:pathExtention];
		
		log_info("new destination: '%@'", destination);
	}
	if ( rename([path fileSystemRepresentation], [destination fileSystemRepresentation]) != 0 ) {
		log_errp("couldn't rename '%@' to '%@'", path, destination);
		return nil;
	}
	return destination;
}

// from: http://www.cocoadev.com/index.pl?FinderFlags
- (BOOL)modifyCatologInfoAtPath:(NSString *)filePath isVisible:(BOOL)isVisible
{
	return [self modifyCatalogFlag:kIsInvisible forPath:filePath enable:!isVisible];
}

- (BOOL)modifyCatologInfoAtPath:(NSString *)filePath hasCustomIcon:(BOOL)hasCustomIcon
{
	return [self modifyCatalogFlag:kHasCustomIcon forPath:filePath enable:hasCustomIcon];
}
- (BOOL)modifyCatologInfoAtURL:(NSURL *)fileURL hasCustomIcon:(BOOL)hasCustomIcon
{
    return [self modifyCatalogFlag:kHasCustomIcon forURL:fileURL enable:hasCustomIcon];
}
- (BOOL)modifyCatalogFlag:(NSInteger)flag forPath:(NSString*)filePath enable:(BOOL)enable;
{
    return [self modifyCatalogFlag:flag forURL:[NSURL fileURLWithPath:filePath] enable:enable];
}

- (BOOL)modifyCatalogFlag:(NSInteger)flag forURL:(NSURL*)fileURL enable:(BOOL)enable
{
    FSRef pathRef;
	FSCatalogInfo catalogInfo;
	FileInfo *fileInfo;
	OSErr err = noErr;
	
    FAIL_IF(!CFURLGetFSRef((__bridge CFURLRef)fileURL, &pathRef));
	DO_FAILABLE(err, FSGetCatalogInfo, &pathRef, kFSCatInfoFinderInfo, &catalogInfo, NULL, NULL, NULL);
	
	fileInfo = (FileInfo*)&catalogInfo.finderInfo;
	
	if ( !enable && (flag & fileInfo->finderFlags) == flag )
		fileInfo->finderFlags ^= flag;
	else if ( enable )
		fileInfo->finderFlags |= flag;
	
	DO_FAILABLE(err, FSSetCatalogInfo, &pathRef, kFSCatInfoFinderInfo, &catalogInfo);
	return YES;
fail_label:
	return NO;
}

- (BOOL)folderHasCustomIcon:(NSString *)folderPath
{
	FSRef pathRef;
	FSCatalogInfo catalogInfo;
	
	if (FSPathMakeRef((const UInt8 *)[folderPath fileSystemRepresentation], &pathRef, NULL) != 0)
		return NO;
	
	if (FSGetCatalogInfo(&pathRef, kFSCatInfoFinderInfo, &catalogInfo, NULL, NULL, NULL) != 0)
		return NO;
	
	return (((FileInfo*)&catalogInfo.finderInfo)->finderFlags & kHasCustomIcon) > 0;
}

- (BOOL)deleteIfEmpty:(NSString*)path
{
	BOOL isDir;
	if ( ![self fileExistsAtPath:path isDirectory:&isDir] || !isDir ) return NO;
	NSArray *contents = [self contentsOfDirectoryAtPath:path error:nil];
	if ( [contents count] > 1 ) return NO;
	if ( [contents count] == 1 && ![[contents objectAtIndex:0] isEqualToString:@".DS_Store"] ) return NO;
	return [self removeItemAtPath:path error:nil];
}

- (BOOL)isSymbolicLinkAtPath:(NSString *)path
{
	NSDictionary *fileAttrs = [self attributesOfItemAtPath:path error:nil];
	return [fileAttrs objectForKey:NSFileType] == NSFileTypeSymbolicLink;
}

- (BOOL)isAliasFolderAtPath:(NSString *)path
{
	FSRef fileRef;
	OSStatus err = noErr;
	Boolean aliasFileFlag, folderFlag;
	NSURL *fileURL = [NSURL fileURLWithPath:path];
	
	if (FALSE == CFURLGetFSRef((__bridge CFURLRef)fileURL, &fileRef))
		err = coreFoundationUnknownErr;
	
	if (noErr == err)
		err = FSIsAliasFile(&fileRef, &aliasFileFlag, &folderFlag);
	
	if (noErr == err)
		return (BOOL)(aliasFileFlag && folderFlag);
	else
		return NO;	
}

- (BOOL)isDirectoryAtPath:(NSString *)path
{
	BOOL isDir = NO;
	[self fileExistsAtPath:path isDirectory:&isDir];
	return isDir;
}

- (BOOL)isVolumeAtPath:(NSString *)from
{
	struct statfs sfs;
	char path[MAXPATHLEN];
	
	// Can't mv(1) a mount point.
	if (realpath([from fileSystemRepresentation], path) == NULL) {
		log_warn("cannot resolve %@: %s", from, path);
		return NO;
	}
	BOOL isVol = !statfs(path, &sfs) && !strcmp(path, sfs.f_mntonname);
    log_debug("%s: '%s': %u %u %u'", __func__, path, sfs.f_type, sfs.f_flags, sfs.f_fssubtype);
    return isVol;
}

- (BOOL)isVolumeAtURL:(NSURL*)url error:(NSError**)error;
{
    OSStatus err = noErr;
    FSRef fsRef;
    FSVolumeRefNum volRefNum;
    FSCatalogInfo catalogInfo;
    CFURLRef volURL;
    NSURL *nsvolURL;
    BOOL isVolume = NO;
    
    CFURLGetFSRef((__bridge CFURLRef)url, &fsRef);
    DO_FAILABLE(err, FSGetCatalogInfo, &fsRef, kFSCatInfoVolume, &catalogInfo, NULL, NULL, NULL);
    volRefNum = catalogInfo.volume;
    DO_FAILABLE(err, FSCopyURLForVolume, volRefNum, &volURL);
    
    // IMPORTANT! We might be dealing with fileReferenceURLs, and so we compare the -[path]'s!
    nsvolURL = (__bridge NSURL*)volURL;
    isVolume = [[url path] isEqual:[nsvolURL path]];
    log_debug("%s: '%@' == '%@': %s", __func__, [url path], [nsvolURL path], isVolume ? "YES" : "NO");
    CFRelease(volURL);
    
fail_label:
    if ( err != noErr && error )
        *error = $error(err, NSLocalizedString(@"isVolume failed with error %d for:\n\n%@", @""), err, url);
    return isVolume;
}

- (NSString *)fileSystemDescriptionAtMount:(NSString *)mountPoint
{
	struct statfs sfs;
	
	if ( statfs([mountPoint fileSystemRepresentation], &sfs) ) {
		log_errp("statfs failed for '%@'", mountPoint);
		return nil;
	}
	
	return [NSString stringWithUTF8String:sfs.f_mntfromname];
}

- (NSString *)volnameAtURL:(NSURL*)url
{
    OSStatus      err;
    FSRef         fsRef;
	FSCatalogInfo catalogInfo;
    HFSUniStr255  volName;
    NSString *volumeName = nil;
    
    FAIL_IF(!CFURLGetFSRef((__bridge CFURLRef)url, &fsRef));
	DO_FAILABLE(err, FSGetCatalogInfo, &fsRef, kFSCatInfoVolume, &catalogInfo, NULL, NULL, NULL);
    DO_FAILABLE(err, FSGetVolumeInfo, catalogInfo.volume, 0, NULL, kFSVolInfoNone, NULL, &volName, NULL);
    volumeName = [NSString stringWithCharacters:volName.unicode length:volName.length];
fail_label:
    return volumeName;
}

- (BOOL)isReadOnlyFSAtPath:(NSString *)path
{
	struct statfs sfs;
	statfs([path fileSystemRepresentation], &sfs);
	return (sfs.f_flags & MNT_RDONLY) > 0;
		
}

- (int64_t)approxSizeOfFolderAtPath:(NSString *)path
{
	int64_t sectorCount = num512BlocksInDir((char*)[path fileSystemRepresentation]);
	if ( sectorCount < 0 ) return sectorCount;
	return SECTORS_TO_MEGS(sectorCount);
}

// See: http://www.cocoabuilder.com/archive/cocoa/136498-obtain-directory-size.html#136503
// note: we currently do not add in the rsrcLogicalSize to the calculation...
//       and i'm not sure how to do it properly, as simply adding it doesn't give the right value
static NSUInteger _fastSize(FSRef *theFileRef, BOOL(^cancelBlock)(NSUInteger curSize), NSUInteger curSize)
{
    NSUInteger totalSize = 0;
	FSIterator thisDirEnum;
	if (FSOpenIterator(theFileRef, kFSIterateFlat, &thisDirEnum) == noErr)
	{
		const ItemCount kMaxEntriesPerFetch = 256;
		struct SFetchedInfo
		{
			FSRef		   fFSRefs[kMaxEntriesPerFetch];
			FSCatalogInfo  fInfos[kMaxEntriesPerFetch];
		};
		// allocate on heap as otherwise we might overflow the stack, these are large structures
        // and we might be recursing deeply
		struct SFetchedInfo *fetched = (struct SFetchedInfo*)malloc(sizeof(struct SFetchedInfo));
		if (fetched != NULL)
		{
			ItemCount  actualFetched;
            BOOL isCanceled = NO;
			OSErr	   fsErr = FSGetCatalogInfoBulk(thisDirEnum, kMaxEntriesPerFetch, &actualFetched,
													NULL, kFSCatInfoDataSizes | kFSCatInfoNodeFlags,
                                                    fetched->fInfos, fetched->fFSRefs, NULL, NULL);
            
			while (!isCanceled && ((fsErr == noErr) || (fsErr == errFSNoMoreItems)))
			{
				ItemCount thisIndex;
				for (thisIndex = 0; thisIndex < actualFetched; thisIndex++)
				{
                    if ( cancelBlock && (isCanceled = cancelBlock(curSize + totalSize)) )
                        break; // user canceled size calculation, get out of here
                    
					if (fetched->fInfos[thisIndex].nodeFlags & kFSNodeIsDirectoryMask) {
                        NSUInteger size = _fastSize(&(fetched->fFSRefs[thisIndex]), cancelBlock, curSize); // it's a folder, recurse
                        if ( size == NSUIntegerMax ) {
                            totalSize = size;
                            goto fail_label;
                        }
						totalSize += size;
					} else
						totalSize += fetched->fInfos[thisIndex].dataLogicalSize;
				}
                
				if (fsErr == errFSNoMoreItems)
					break;
                
                // get more items
                fsErr = FSGetCatalogInfoBulk(thisDirEnum, kMaxEntriesPerFetch, &actualFetched,
                                             NULL, kFSCatInfoDataSizes | kFSCatInfoNodeFlags,
                                             fetched->fInfos, fetched->fFSRefs, NULL, NULL);
			}
            
            if ( fsErr != noErr && fsErr != errFSNoMoreItems && !isCanceled ) {
                CFURLRef url = CFURLCreateFromFSRef(NULL, theFileRef);
                // if we got an access denied to the .Trashes folder we continue
                if ( fsErr != afpAccessDenied || ![[(__bridge NSURL*)url lastPathComponent] isEqualToString:@".Trashes"] ) {
                    log_err("error %d during size calc for: %@", fsErr, (__bridge NSURL*)url);
                    totalSize = NSUIntegerMax;
                }
                CFRelease(url);
            }
fail_label:
			free(fetched);
		}
		FSCloseIterator(thisDirEnum);
	}
	return totalSize;
}

- (NSUInteger)fastFolderSizeAtFSRef:(FSRef *)theFileRef cancelBlock:(BOOL(^)(NSUInteger curSize))cancelBlock
{
    return _fastSize(theFileRef, cancelBlock, 0);
}

struct MyFSStruct {
    void *info;
    BOOL canceled;
    BOOL finished;
};

static void MyFSFileOperationStatusProc(FSFileOperationRef fileOp,
                                        const FSRef *currentItem,
                                        FSFileOperationStage stage,
                                        OSStatus error,
                                        CFDictionaryRef statusDictionary,
                                        void *info)
{
    struct MyFSStruct *finisher = (struct MyFSStruct *)info;
    BOOL(^block)(OSStatus, NSDictionary *) = (__bridge BOOL(^)(OSStatus, NSDictionary *))finisher->info;
    // TODO: test and handle permissions related error
    if ( stage == kFSOperationStageComplete )
        finisher->finished = YES;
    else if ( block(error, (__bridge NSDictionary*)statusDictionary) ) {
        log_debug("%s: cancelling copy!", __func__);
        FSFileOperationCancel(fileOp);
        finisher->canceled = YES;
        finisher->finished = YES;
    }
}

// TODO: add an NSMutableDictionary parameter (optional) that will be filled
//       with files that failed to copy due to whatever. Save this to a text file on the Desktop.

- (BOOL)copyContentsFrom:(NSURL*)fromURL
          intoLocationAt:(NSURL*)toURL
                 options:(OptionBits)flags
             cancelBlock:(BOOL(^)(OSStatus, NSDictionary *))cancelBlock
                   error:(NSError**)error
{
    OSStatus err;
    NSError *ourErr;
    FSRef fromRef, toRef;
    NSURL *resultURL;
    FSFileOperationClientContext context;
    NSArray *blacklist = $a(@".DS_Store", @".Trashes", @".fseventsd", @".Spotlight-V100", @".com.apple.timemachine.supported", @".VolumeIcon.icns", @"Icon\r"), *subitems;
    BOOL success = YES;
    NSRunLoop *runLoop = [NSRunLoop currentRunLoop];//[NSRunLoop mainRunLoop];
    CFRunLoopRef runLoopRef = [runLoop getCFRunLoop];
    FSFileOperationRef fileOp = FSFileOperationCreate(NULL);
    CFURLGetFSRef((__bridge CFURLRef)fromURL, &fromRef);
    CFURLGetFSRef((__bridge CFURLRef)toURL, &toRef);
    
    resultURL = [toURL URLByAppendingPathComponent:[fromURL lastPathComponent] isDirectory:YES];
    
    struct MyFSStruct finisher;
    
    finisher.info = (__bridge void *)cancelBlock;
    finisher.canceled = NO;
    finisher.finished = NO;
    
    context.version = 0;
    context.info = (void*)&finisher;
    context.retain = NULL;
    context.release = NULL;
    context.copyDescription = NULL;
    
    DO_FAILABLE(err, FSFileOperationScheduleWithRunLoop,
                fileOp, runLoopRef, kCFRunLoopDefaultMode);
    
    DO_FAILABLE(err, FSCopyObjectAsync,
                fileOp, &fromRef, &toRef, NULL,
                flags, MyFSFileOperationStatusProc, 1, &context);
#if !defined(RUN_SHIT_ON_MAIN_RUNLOOP)
    while (!(finisher.finished) && [runLoop runMode:NSDefaultRunLoopMode
                                         beforeDate:[NSDate distantFuture]])
    {
        //log_debug("%s: running copy runloop...", __func__);
    }
#else
    while (! (finisher.finished) )
    {
        usleep(2000);//log_debug("%s: running copy runloop...", __func__);
    }
#endif
    
    FAIL_IFQ(finisher.canceled, err = errTEUserCanceled);
    
    // now we need to simply move all of the items up one directory
    subitems = [self contentsOfDirectoryAtURL:resultURL
                            includingPropertiesForKeys:$a(NSURLLocalizedNameKey)
                                               options:0
                                                 error:&ourErr];
    FAIL_IF(!subitems, err = (OSStatus)[ourErr code]);
    
    for ( NSURL *item in subitems ) {
        NSURL *newURL = [[resultURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:[item lastPathComponent]];
        if ( ![blacklist containsObject:[item lastPathComponent]] && ![self moveItemAtURL:item toURL:newURL error:&ourErr] ) {
            log_warn("failed to move: '%@' => '%@': %@", item, newURL, ourErr);
            success = NO;
        }
    }
    FAIL_IF(!success, err = errTECopySuccessMoveFail);
    
    [self removeItemAtURL:resultURL error:nil];

fail_label:
    FSFileOperationUnscheduleFromRunLoop(fileOp, runLoopRef, kCFRunLoopDefaultMode);
    CFRelease(fileOp);
    
    if ( err != noErr ) {
        log_err("error %d durng copy of: %@", err, fromURL);
        if ( error )
            *error = $error(err, NSLocalizedString(@"Error during copy: %@\n\nCould not copy all of: %@\n\nSee system log for more.", @""), ourErr ? [ourErr localizedDescription] : $num(err), [fromURL path]);
        return NO;
    }
    return YES;
}

- (BOOL)folderAtPath:(NSString *)path isAtLeast:(int32_t)megs
{
	return folderAtPathAtLeast((char*)[path fileSystemRepresentation], MEGS_TO_SECTORS(megs)) == 1;
}

- (uid_t)ownerForPath:(NSString*)path
{
	struct statfs sfs;
	if ( statfs([path fileSystemRepresentation], &sfs) ) {
		log_errp("couldn't stat: %@", path);
		return -1;
	}
	return sfs.f_owner;
}

- (OSStatus)ejectVolumeAtPath:(NSString *)path pid:(pid_t*)dissenter
{
	FSRef pathRef;
	FSCatalogInfo catalogInfo;
	OSStatus err = paramErr;
	
	FAIL_IF(dissenter == NULL, log_err("dissenter is null"));
	
	*dissenter = 0; // initialize it
	
	DO_FAILABLE(err, FSPathMakeRef, (const UInt8 *)[path fileSystemRepresentation], &pathRef, NULL);
	DO_FAILABLE(err, FSGetCatalogInfo, &pathRef, kFSCatInfoFinderInfo, &catalogInfo, NULL, NULL, NULL);
	DO_FAILABLE(err, FSEjectVolumeSync, catalogInfo.volume, 0, dissenter);
	
fail_label:
	return err;
}

- (void)notePathChanged:(NSString *)path
{
	[[NSWorkspace sharedWorkspace] noteFileSystemChanged:path];
	FNNotifyByPath((UInt8*)[path fileSystemRepresentation], kFNDirectoryModifiedMessage, kNilOptions);
}

- (OSStatus)removeACLsAtPath:(NSString *)path matchingPerm:(acl_perm_t)permFilter andTag:(acl_tag_t)tagFilter
{
	OSStatus err = noErr;
	acl_t acl = NULL;
	acl_entry_t entry = NULL;
	
	FAIL_IFQ(!(acl = [self aclsForFileAtPath:path]));
	
	DO_FAILABLE_SUB(err, errno, acl_valid, acl);
	
	// TODO: we don't check to see what the error value of this is because it's returning
	//       -1 when it shouldn't.  Seems to be either my poor understanding of how to use
	//       the API, or a bug...
	err = acl_get_entry(acl, ACL_FIRST_ENTRY, &entry);
	
	while ( err == 0 )
	{
		//log_debug("got ACL entry for: %@", path);
		acl_permset_t perms;
		acl_tag_t tag;
		
		DO_FAILABLE_SUB(err, errno, acl_get_permset, entry, &perms);
		DO_FAILABLE_SUB(err, errno, acl_get_tag_type, entry, &tag);
		
		if ( acl_get_perm_np(perms, permFilter) && tag == tagFilter ) {
			log_info("removing ACL (%d|%d) from: %@", permFilter, tagFilter, path);
			DO_FAILABLE_SUB(err, errno, acl_delete_entry, acl, entry);
			
			if ( ![self isSymbolicLinkAtPath:path] )
				DO_FAILABLE_SUB(err, errno, acl_set_file, [path fileSystemRepresentation], ACL_TYPE_EXTENDED, acl);
			else {
				// see: http://0xced.blogspot.com/2009/03/chmod-acl-and-symbolic-links_23.html
				int fd = open([path fileSystemRepresentation], O_SYMLINK);
				FAIL_IF(fd == -1, err = errno);
				err = acl_set_fd_np(fd, acl, ACL_TYPE_EXTENDED);
				close(fd);
				FAIL_IF(err, err = errno);
			}
		}
		
		err = acl_get_entry(acl, ACL_NEXT_ENTRY, &entry);
	}
	err = noErr; // clear out the return value of the last acl_get_entry
	
fail_label:
	if ( acl ) acl_free((void*)acl);
	if ( err ) log_errp("failed to remove ACL (%d|%d) from: %@", permFilter, tagFilter, path);
	return err;
}

- (BOOL)fileHasACLs:(NSString *)filePath matchingPerm:(acl_perm_t)permFilter andTag:(acl_tag_t)tagFilter
{
	OSStatus    err;
	acl_t       acl    = NULL;
	acl_entry_t entry  = NULL;
	BOOL        result = NO;
	
	FAIL_IFQ(!(acl = [self aclsForFileAtPath:filePath]));
	
	err = acl_get_entry(acl, ACL_FIRST_ENTRY, &entry);
	
	while ( err == 0 )
	{
		acl_permset_t perms;
		acl_tag_t tag;
		
		DO_FAILABLE_SUB(err, errno, acl_get_permset, entry, &perms);
		DO_FAILABLE_SUB(err, errno, acl_get_tag_type, entry, &tag);
		
		if ( acl_get_perm_np(perms, permFilter) && tag == tagFilter ) {
			log_debug("file matches ACL for (%d|%d): %@", permFilter, tagFilter, filePath);
			result = YES;
			break;
		}
		
		err = acl_get_entry(acl, ACL_NEXT_ENTRY, &entry);
	}
	
fail_label:
	if ( acl ) acl_free((void*)acl);
	return result;
}

- (OSStatus)removeACL:(const char *)aclText fromFile:(NSString *)filePath
{
	log_err("NOT IMPLEMENTED");
	return paramErr;
}

- (OSStatus)addACL:(const char *)aclText toFile:(NSString *)filePath
{
	OSStatus err = noErr;
	acl_t acl = NULL, fileACL = NULL, aclToSet = NULL;
	acl_entry_t newEntry;
	int fd;
	
	FAIL_IF(!(acl = acl_from_text(aclText)));
	
	aclToSet = acl;
	fileACL = [self aclsForFileAtPath:filePath];
	
	// the file may already contain ACLs
	if ( fileACL ) {
		DO_FAILABLE_SUB(err, errno, acl_get_entry, acl, ACL_FIRST_ENTRY, &newEntry);
		DO_FAILABLE_SUB(err, errno, acl_create_entry, &fileACL, &newEntry);
		aclToSet = fileACL;
	}
	
	if ( ![self isSymbolicLinkAtPath:filePath] )
		DO_FAILABLE_SUB(err, errno, acl_set_file, [filePath fileSystemRepresentation], ACL_TYPE_EXTENDED, aclToSet);
	else {
		// see: http://0xced.blogspot.com/2009/03/chmod-acl-and-symbolic-links_23.html
		fd = open([filePath fileSystemRepresentation], O_SYMLINK);
		FAIL_IF(fd == -1, err = errno);
		err = acl_set_fd_np(fd, aclToSet, ACL_TYPE_EXTENDED);
		close(fd);
		FAIL_IF(err, err = errno);
	}
	
fail_label:
	if ( acl ) acl_free((void*)acl);
	if ( fileACL ) acl_free((void*)fileACL);
	if ( err ) log_errp("failed to add ACL (%s) to: '%@'", aclText, filePath);
	return err;
}

- (BOOL)fileHasACLs:(NSString *)filePath
{
	acl_t acl = [self aclsForFileAtPath:filePath];
	if ( acl ) {
		acl_free((void*)acl);
		return YES;
	}
	return NO;
}

- (acl_t)aclsForFileAtPath:(NSString *)filePath
{
	int fd = open([filePath fileSystemRepresentation], [self isSymbolicLinkAtPath:filePath] ? O_SYMLINK : O_RDONLY);
	FAIL_IFQ(fd == -1, log_errp("failed to open: %@", filePath));
	acl_t acl = acl_get_fd_np(fd, ACL_TYPE_EXTENDED);
	close(fd);
	return acl;
fail_label:
	return NULL;
}

- (OSStatus)setACL:(acl_t)acl forFileAtPath:(NSString *)filePath
{
	return acl_set_file([filePath fileSystemRepresentation], ACL_TYPE_EXTENDED, acl) ? errno : 0;
}

// extended attributes
- (NSArray*)xattrNamesAtPath:(NSString*)path
{
	NSMutableArray *array = nil;
	size_t size = listxattr([path fileSystemRepresentation], NULL, 0, 0);
	if ( size == 0 ) return nil;
	FAIL_IFQ(size == -1, if ( errno != ENOTSUP ) log_errp("failed to get list of xattrs for: %@", path));
	char *xattrs = malloc(size);
	size = listxattr([path fileSystemRepresentation], xattrs, size, 0);
	size_t sLen = 0;
	array = [NSMutableArray arrayWithCapacity:size];
	for (char *xattr = xattrs; xattr < (xattrs + size); xattr += (1 + sLen)) {
		sLen = strlen(xattr);
		[array addObject:[NSString stringWithUTF8String:xattr]];
	}
	free(xattrs);
fail_label:
	return array;
}

- (NSData*)xattrDataForName:(NSString*)name atPath:(NSString*)path
{
	NSData *data = nil;
	ssize_t xattrBytes = getxattr([path fileSystemRepresentation], [name UTF8String], NULL, 0, 0, 0);
	if ( xattrBytes == 0 ) return nil;
	FAIL_IFQ(xattrBytes == -1, if ( errno != ENOATTR ) log_errp("error getting xattr '%@' for: '%@'", name, path));
	uint8_t *xattrBuff = malloc(xattrBytes+1);
	xattrBytes = getxattr([path fileSystemRepresentation], [name UTF8String], xattrBuff, xattrBytes, 0, 0);
	if ( xattrBytes != -1 && xattrBytes > 0 )
		data = [NSData dataWithBytes:xattrBuff length:xattrBytes];
	free(xattrBuff);
fail_label:
	return data;
}

- (OSStatus)setData:(NSData*)data forXattr:(NSString*)name atPath:(NSString*)path
{
	OSStatus err = noErr;
	FAIL_IFQ(![self fileExistsAtPath:path], log_warn("can't set xattr '%@'; file doesn't exist: '%@'", name, path); err = ENOENT);
	FAIL_IFQ(setxattr([path fileSystemRepresentation], [name UTF8String], [data bytes], [data length], 0, 0),
			 log_warn("failed to setxattr '%@' on: '%@', error: %s", name, path, strerror(errno)); err = errno);
fail_label:
	return err;
}

@end
