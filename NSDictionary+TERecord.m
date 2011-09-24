//
//  NSDictionary+TERecord.m
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
#import "NSDictionary+TERecord.h"
#import "Common.h"

// many thanks go to this blog post for some of the code here:
// http://blog.lhunath.com/2010/01/clean-up-your-configuration.html

@interface TERecordValue : NSObject <NSCoding, NSCopying> {
    NSRecursiveLock *lock;
}
@property (nonatomic, retain) id obj;
@property (nonatomic) BOOL atomic;
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
    if ( self = [super init] ) {
        obj = [aDecoder decodeObjectForKey:@"obj"];
        atomic = [aDecoder decodeBoolForKey:@"atomic"];
        lock = [NSRecursiveLock new];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)aCoder
{
    [aCoder encodeObject:obj forKey:@"obj"];
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
    [aCoder encodeObject:dict forKey:@"dict"];
}
- (id)initWithCoder:(NSCoder *)aDecoder
{
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
    if ( rVal.atomic ) [rVal lock];
    [self willChangeValueForKey:key];
    rVal.obj = value;
    [self didChangeValueForKey:key];
    if ( rVal.atomic ) [rVal unlock];
}
- (void)setNilValueForKey:(NSString *)key
{
    [self setValue:nil forKey:key];
}
- (id)valueForKey:(NSString *)key
{
    TERecordValue *rVal = [dict objectForKey:key];
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
// TODO: implement setValue:forKeyPath:
- (NSUInteger)hash
{
    return [dict hash];
}
- (BOOL)isEqual:(id)object
{
    return [dict isEqual:object];
}
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

id TERecordCreate(Protocol *proto)
{
    // return a dictionary and for propertyInfo use property_getAttributes to find out if atomic or not
    // see Objective-C Runtime Programming Guide for more info on the possible attributes
    unsigned int count, i;
    objc_property_t *properties = protocol_copyPropertyList(proto, &count);
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:count];
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
        TERecordValue *value = [TERecordValue new];
        value.atomic = isAtomic;
        [dict setObject:value forKey:name];
    }
    free(properties);
    return [[TERecord alloc] initWithDict:dict];
}
#if 0
@implementation NSDictionary (TERecord)
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel
{
	return [NSMethodSignature signatureWithObjCTypes:"@@:"];
}
- (void)forwardInvocation:(NSInvocation *)anInvocation
{
	TERecordValue *value = [self objectForKey:NSStringFromSelector([anInvocation selector])];
    __unsafe_unretained id obj = value.obj;
    [anInvocation setReturnValue:&obj];
}
@end

@implementation NSMutableDictionary (TERecord)
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel
{
	if ( [NSStringFromSelector(sel) hasPrefix:@"set"] )
		return [NSMethodSignature signatureWithObjCTypes:"v@:@"];
	else
		return [super methodSignatureForSelector:sel];
}
- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSString *selector = NSStringFromSelector([anInvocation selector]);
	if ( [selector hasPrefix:@"set"] )
	{
		NSRange firstChar = NSMakeRange(3,1);
		NSRange rest = NSMakeRange(4, [selector length] - 5);
		__unsafe_unretained id value;
		selector = [[[selector substringWithRange:firstChar] lowercaseString] stringByAppendingString:[selector substringWithRange:rest]];
		[anInvocation getArgument:&value atIndex:2];
        TERecordValue *rValue = [self objectForKey:selector];
        if ( __unlikely(rValue.atomic) )
            @synchronized (rValue) {
//                [self willChangeValueForKey:selector];
                rValue.obj = value;
                [self setValue:rValue forKey:selector];
//                [self didChangeValueForKey:selector];
            }
        else {
//            [self willChangeValueForKey:selector];
            rValue.obj = value;
//            [self didChangeValueForKey:selector];
            [self setValue:rValue forKey:selector];
        }
	}
	else
    {
        TERecordValue *rValue = [self objectForKey:selector];
        if ( __unlikely(rValue.atomic) )
            @synchronized (rValue) { [super forwardInvocation:anInvocation]; }
        else
            [super forwardInvocation:anInvocation];
    }
}
@end
#endif
