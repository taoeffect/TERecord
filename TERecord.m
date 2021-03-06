//
//  TERecord.m
//
//  Created by Greg Slepak on 5/8/11.

// Copyright 2011 Tao Effect LLC. All rights reserved.
// 
// Redistribution and use in source and binary forms, with or without modification, are
// permitted provided that the following conditions are met:
// 
//    1. Redistributions of source code must retain the above copyright notice, this list of
//       conditions and the following disclaimer.
// 
//    2. Redistributions in binary form must reproduce the above copyright notice, this list
//       of conditions and the following disclaimer in the documentation and/or other materials
//       provided with the distribution.
// 
// THIS SOFTWARE IS PROVIDED BY TAO EFFECT LLC ``AS IS'' AND ANY EXPRESS OR IMPLIED
// WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
// FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> OR
// CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
// ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
// NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
// ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
// 
// The views and conclusions contained in the software and documentation are those of the
// authors and should not be interpreted as representing official policies, either expressed
// or implied, of Tao Effect LLC.

#import <objc/objc-runtime.h>
#import "TERecord.h"
#import "NSFileManager+TEAdditions.h"
#import "Common.h"

@interface TERecordValue : NSObject <NSCoding, NSCopying> {
    NSRecursiveLock *lock;
}
@property (nonatomic, retain) id obj;
@property (nonatomic) BOOL atomic;
//@property (nonatomic) BOOL bookmark; // indicates we represent an NSURL that must be restored via bookmark data
- (void)lock;
- (void)unlock;
@end
@implementation TERecordValue
@synthesize obj, atomic;
- (id)init
{
    if ( self = [super init] )
        lock = [NSRecursiveLock new];
    return self;
}
- (id)initWithCoder:(NSCoder *)aDecoder
{
//    log_debug("%s", __func__);
    if ( self = [super init] ) {
        obj = [aDecoder decodeObjectForKey:@"obj"];
        atomic = [aDecoder decodeBoolForKey:@"atomic"];
        lock = [NSRecursiveLock new];
        
        // NOTE: see note below in -encodeWithCoder
//        bookmark = [aDecoder decodeBoolForKey:@"bookmark"];        
//        if ( bookmark ) {
//            NSError *error;
//            obj = [NSURL URLByResolvingBookmarkData:obj
//                                            options:0
//                                      relativeToURL:nil
//                                bookmarkDataIsStale:NULL
//                                              error:&error];
//            if ( error ) {
//                log_err("%s: %@: '%@'", __func__, error, obj);
//                obj = nil;
//            } else if ( ![obj isFileReferenceURL] ) {
//                log_warn("%s: not a fileReference: %@", __func__, obj);
//                obj = [obj fileReferenceURL];
//            }
//            log_debug("%s: resolved bookmark: '%@'", __func__, obj);
//        }
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)aCoder
{
//    log_debug("%s", __func__);
    if ( [obj isMemberOfClass:[NSURL class]] && [obj isFileReferenceURL] ) {
        // save fileReferenceURLs as filePathURLs because reference URLs aren't persistent
        [aCoder encodeObject:[obj filePathURL] forKey:@"obj"];
        // NOTE: saving bookmark data doesn't help us if the folder is unlocked (mounted)
        //       and then we relaunch Espionage, as it tries to resolve against the mountpoint
        //       and fails, returning NULL when calling +URLByResolvingBookmarkData from -initWithCoder 
//        log_debug("%s: saving bookmark for '%@'", __func__, [obj path]);
//        NSData *data = [obj bookmarkDataWithOptions:(NSURLBookmarkCreationSuitableForBookmarkFile|NSURLBookmarkCreationPreferFileIDResolution)
//                     includingResourceValuesForKeys:$a(NSURLFileResourceIdentifierKey)
//                                      relativeToURL:nil
//                                              error:nil];
//        if ( !data ) {
//            // save as regular filePathURL instead
//            log_warn("%s: couldn't create bookmark for '%@'!", __func__, [obj path]);
//            [aCoder encodeObject:[obj filePathURL] forKey:@"obj"];
//        } else {
//            [aCoder encodeBool:YES forKey:@"bookmark"];
//            [aCoder encodeObject:data forKey:@"obj"];
//        }
    } else {
        // just encode the object directly
        [aCoder encodeObject:obj forKey:@"obj"];
    }
    [aCoder encodeBool:atomic forKey:@"atomic"];
}
- (id)copyWithZone:(NSZone *)zone
{
    TERecordValue *val = [TERecordValue new];
    if ( atomic ) [lock lock];
    val.obj = [obj copy];
    if ( atomic ) [lock unlock];
    val.atomic = atomic;
    return val;
}
- (NSUInteger)hash
{
    return [obj hash];
}
- (BOOL)isEqual:(id)object
{
    return [obj isEqual:object];
}
- (NSString*)description
{
    return [obj description];
}
- (void)lock
{
    [lock lock];
}
- (void)unlock
{
    [lock unlock];
}
@end

@interface TERecord : NSObject <TERecord> {
    NSMutableDictionary *dict;
}
- (id)initWithDict:(NSMutableDictionary*)aDict;
- (void)setValue:(id)value forKey:(NSString *)key;
- (id)valueForKey:(NSString *)key;
- (id)valueForKeyPath:(NSString *)keyPath;
@end

@implementation TERecord
- (id)initWithDict:(NSMutableDictionary *)aDict
{
    if ( self = [super init] )
        dict = aDict;
    return self;
}
- (void)encodeWithCoder:(NSCoder *)aCoder
{
//    log_debug("%s", __func__);
    [aCoder encodeObject:dict forKey:@"dict"];
}
- (id)initWithCoder:(NSCoder *)aDecoder
{
//    log_debug("%s", __func__);
    if ( self = [super init] )
        dict = [aDecoder decodeObjectForKey:@"dict"];
    return self;
}
- (NSMutableDictionary *)dictCopy
{
    NSMutableDictionary *aDict = [NSMutableDictionary dictionaryWithCapacity:[dict count]];
    for ( NSString *key in dict ) {
        [aDict setObject:[self valueForKey:key] forKey:key];
    }
    return aDict;
}
- (id)copyWithZone:(NSZone *)zone
{
    return [[TERecord alloc] initWithDict:dict];
}
- (void)setValue:(id)value forKey:(NSString *)key
{
    TERecordValue *rVal = [dict objectForKey:key];
    // NOTE: 
    // we *don't* do this because we don't know what the value for rVal.atomic is
    // instead users of TERecord should make sure that whatever class they store
    // as a property of a TERecord supports the NSCoding protocol, *even* if all
    // it does in encodeWithCoder is encode a [NSNull null] value. Basically we
    // want to make sure that TERecordValues are created by the TERecordCreate function.
    // If you need to update the record with new properties, call TERecordUpdateProtocol
//    if ( !rVal ) {
//        rVal = [TERecordValue new];
//        [dict setObject:rVal forKey:key];
//    }
    [self willChangeValueForKey:key];
    if ( rVal.atomic ) [rVal lock];
    rVal.obj = value;
    if ( rVal.atomic ) [rVal unlock];
    [self didChangeValueForKey:key];
//    log_debug("%s: %@ %@", __func__, key, rVal ? rVal.obj : @"NULL");
}
- (void)setNilValueForKey:(NSString *)key
{
    [self setValue:nil forKey:key];
}
- (id)valueForKey:(NSString *)key
{
    TERecordValue *rVal = [dict objectForKey:key];
//    log_debug("%s: %@ %@", __func__, key, rVal ? rVal.obj : @"NULL");
    id obj;
    if ( rVal.atomic ) [rVal lock];
    obj = rVal.obj;
    if ( rVal.atomic ) [rVal unlock];
    return obj;
}
- (id)valueForKeyPath:(NSString *)keyPath
{
    NSArray *comps = [keyPath componentsSeparatedByString:@"."];
    TERecordValue *rVal = [dict objectForKey:[comps objectAtIndex:0]];
    id obj;
    NSUInteger i, count = [comps count];
    if ( rVal.atomic ) [rVal lock];
    obj = rVal.obj;
    for ( i=1; i < count; ++i )
        obj = [obj valueForKey:[comps objectAtIndex:i]];
    if ( rVal.atomic ) [rVal unlock];
    return obj;
}
- (void)setValue:(id)value forKeyPath:(NSString *)keyPath
{
    NSArray *comps = [keyPath componentsSeparatedByString:@"."];
    TERecordValue *rVal = [dict objectForKey:[comps objectAtIndex:0]];
    id obj;
    NSUInteger i, count = [comps count];
    if ( rVal.atomic ) [rVal lock];
    if ( count > 1 ) {
        obj = rVal.obj;
        for ( i=1; i < count-1; ++i )
            obj = [obj valueForKey:[comps objectAtIndex:i]];
        [obj setValue:value forKey:[comps lastObject]];
    } else
        rVal.obj = value;
    if ( rVal.atomic ) [rVal unlock];
}
- (NSUInteger)hash
{
    return [dict hash];
}
- (BOOL)isEqual:(id)object
{
    return [dict isEqual:object];
}
- (NSString*)description
{
    return [dict description];
}

- (NSMutableDictionary*)dict
{
    return dict;
}

// many thanks go to this blog post for some of the code here:
// http://blog.lhunath.com/2010/01/clean-up-your-configuration.html

- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel
{
//    log_debug("%s: %@", __func__, NSStringFromSelector(sel));
	if ( [NSStringFromSelector(sel) hasPrefix:@"set"] )
		return [NSMethodSignature signatureWithObjCTypes:"v@:@"];
	else
		return [NSMethodSignature signatureWithObjCTypes:"@@:"];
}
- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSString *selector = NSStringFromSelector([anInvocation selector]);
//    log_debug("%s: %@", __func__, selector);
	if ( [selector hasPrefix:@"set"] )
	{
		NSRange firstChar = NSMakeRange(3,1);
		NSRange rest = NSMakeRange(4, [selector length] - 5);
		__unsafe_unretained id value;
		selector = [[[selector substringWithRange:firstChar] lowercaseString] stringByAppendingString:[selector substringWithRange:rest]];
		[anInvocation getArgument:&value atIndex:2];
        [self setValue:value forKey:selector];
	}
	else
    {
        __unsafe_unretained id value = [self valueForKey:selector];
        [anInvocation setReturnValue:&value];
    }
}
@end

// fill a dictionary with TERecordValues for each property in proto
static inline NSMutableDictionary* dictWithProperties(NSMutableDictionary *dict, Protocol *proto)
{
    // use property_getAttributes to find out if atomic or not
    // see Objective-C Runtime Programming Guide for more info on the possible attributes
    unsigned int count, i;
    objc_property_t *properties = protocol_copyPropertyList(proto, &count);
    if ( !dict ) dict = [NSMutableDictionary dictionaryWithCapacity:count];
    for ( i = 0; i < count; ++i ) {
        NSString *name = [NSString stringWithUTF8String:property_getName(properties[i])];
        NSString *attrs = [NSString stringWithUTF8String:property_getAttributes(properties[i])];
        NSArray *attrsAry = [attrs componentsSeparatedByString:@","];
        BOOL isAtomic = YES;
        for ( NSString *attr in attrsAry ) {
            if ( [attr isEqualToString:@"N"] ) {
                isAtomic = NO;
                break;
            }
        }
        //log_debug("%s: %@: %@ %@", __func__, NSStringFromProtocol(proto), attrs, name);
        // now we set defaults so that we can safely handle atomic properties by
        // creating the hash-tree map fully so that no more node manipulation happens
        if ( !dict || ![dict valueForKey:name] ) {
            TERecordValue *value = [TERecordValue new];
            value.atomic = isAtomic;
            [dict setObject:value forKey:name];
        }
    }
    free(properties);
    return dict;
}

id TERecordCreate(Protocol *proto)
{
    return [[TERecord alloc] initWithDict:dictWithProperties(NULL, proto)];
}

void TERecordUpdateProtocol(id<TERecord> r, Protocol *proto)
{
    dictWithProperties(r.dict, proto);
}
