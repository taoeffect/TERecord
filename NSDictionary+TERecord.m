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

#import "NSDictionary+TERecord.h"

// many thanks go to this blog post for some of the code here:
// http://blog.lhunath.com/2010/01/clean-up-your-configuration.html

@implementation NSDictionary (TERecord)
+ (id)dictionaryWithKeysAndObjects:(id)key, ...
{
	NSMutableDictionary *dict = [NSMutableDictionary dictionary];
	va_list args;
	va_start(args, key);
	id value = va_arg(args, id);
	while (YES)
	{
		[dict setObject:value forKey:key];
		key = va_arg(args, id);
		if ( !key ) break;
		value = va_arg(args, id);
	}
	va_end(args);
	// enfoce mutable-ness
	return [self class] == [NSDictionary class] ? [NSDictionary dictionaryWithDictionary:dict] : dict;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel
{
	return [NSMethodSignature signatureWithObjCTypes:"@@:"];
}
- (void)forwardInvocation:(NSInvocation *)anInvocation
{
	id value = [self objectForKey:NSStringFromSelector([anInvocation selector])];
	[anInvocation setReturnValue:&value];
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
		id value;
		selector = [[[selector substringWithRange:firstChar] lowercaseString] stringByAppendingString:[selector substringWithRange:rest]];
		[anInvocation getArgument:&value atIndex:2];
		[self setObject:value forKey:selector];
	}
	else
		[super forwardInvocation:anInvocation];
}
@end
