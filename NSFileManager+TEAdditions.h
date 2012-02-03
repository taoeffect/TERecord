//
//  NSFileManager+TEAdditions.h
//  Espionage
//
//  Created by Greg Slepak on 6/2/08.
//  Copyright 2008 Tao Effect LLC. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <sys/types.h>
#import <sys/acl.h>

@interface NSFileManager (TEAdditions)

// these return the new path on success or nil on failure
- (NSString*)moveFileUpADirectory:(NSString *)itemPath;
- (NSString*)moveFile:(NSString *)itemPath toDirectory:(NSString *)dir;
- (NSString*)renameItemAtPath:(NSString *)path to:(NSString *)newName;
- (NSString*)forceRenameItemAtPath:(NSString *)path to:(NSString *)newName; // will append date if necessary
- (BOOL)deleteIfEmpty:(NSString*)path;

- (int64_t)approxSizeOfFolderAtPath:(NSString *)path; // quickly calculates a folder's size in MB (-1 on error)
- (NSUInteger)fastFolderSizeAtFSRef:(FSRef *)theFileRef cancelBlock:(BOOL(^)(NSUInteger curSize))cancelBlock;

// a bad-ass copy. synchronous.
- (BOOL)copyContentsFrom:(NSURL*)fromURL
          intoLocationAt:(NSURL*)toURL
                 options:(OptionBits)flags
             cancelBlock:(BOOL(^)(OSStatus err, NSDictionary *dict))cancelBlock
                   error:(NSError**)error;

- (BOOL)folderAtPath:(NSString *)path isAtLeast:(int32_t)megs; // quickly answers this question
- (uid_t)ownerForPath:(NSString*)path;
- (BOOL)modifyCatologInfoAtPath:(NSString *)filePath isVisible:(BOOL)val;
- (BOOL)modifyCatologInfoAtPath:(NSString *)filePath hasCustomIcon:(BOOL)val;
- (BOOL)modifyCatologInfoAtURL:(NSURL *)fileURL hasCustomIcon:(BOOL)val; // NSUIntegerMax = ERROR
- (BOOL)modifyCatalogFlag:(NSInteger)flag forPath:(NSString*)filePath enable:(BOOL)enable;
- (BOOL)modifyCatalogFlag:(NSInteger)flag forURL:(NSURL*)fileURL enable:(BOOL)enable;
- (BOOL)folderHasCustomIcon:(NSString *)folderPath;
- (BOOL)isSymbolicLinkAtPath:(NSString *)path;
- (BOOL)isAliasFolderAtPath:(NSString *)path;
- (BOOL)isDirectoryAtPath:(NSString *)path;
- (BOOL)isVolumeAtPath:(NSString *)path;
- (BOOL)isVolumeAtURL:(NSURL*)url error:(NSError**)error;
- (BOOL)isReadOnlyFSAtPath:(NSString *)path;
- (OSStatus)ejectVolumeAtPath:(NSString *)path pid:(pid_t*)dissenter;

- (NSString *)fileSystemDescriptionAtMount:(NSString *)mountPoint;
- (NSString *)volnameAtURL:(NSURL*)url;

// ACLs
- (OSStatus)removeACLsAtPath:(NSString *)path matchingPerm:(acl_perm_t)perm andTag:(acl_tag_t)tag;
- (OSStatus)removeACL:(const char *)aclText fromFile:(NSString *)filePath;
- (OSStatus)addACL:(const char *)aclText toFile:(NSString *)filePath;
- (BOOL)fileHasACLs:(NSString *)filePath;
- (BOOL)fileHasACLs:(NSString *)filePath matchingPerm:(acl_perm_t)perm andTag:(acl_tag_t)tag;

// NOTE: you must call acl_free((void*)acl); on the returned acl_t when you're done with it
- (acl_t)aclsForFileAtPath:(NSString *)filePath;
// pass NULL for acl if you want to remove them all
- (OSStatus)setACL:(acl_t)acl forFileAtPath:(NSString *)filePath;

- (void)notePathChanged:(NSString *)path;

// extended attributes
- (NSArray*)xattrNamesAtPath:(NSString*)path;
- (NSData*)xattrDataForName:(NSString*)name atPath:(NSString*)path;
- (OSStatus)setData:(NSData*)data forXattr:(NSString*)name atPath:(NSString*)path;

@end
