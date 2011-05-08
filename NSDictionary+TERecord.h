//
//  NSDictionary+TERecord.h
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

#import <Foundation/Foundation.h>

#define _MD(...)  [NSMutableDictionary dictionaryWithKeysAndObjects:__VA_ARGS__, nil]
#define _D(...)   [NSDictionary dictionaryWithKeysAndObjects:__VA_ARGS__, nil]
// these allow a way to use values not defined in a protocol w/o triggering compiler warnings
#define _dg(_d, _s) objc_msgSend(_d, @selector(_s))
#define _ds(_d, _s, _v) objc_msgSend(_d, @selector(set##_s:), _v)

@interface NSDictionary (TERecord)
+ (id)dictionaryWithKeysAndObjects:(id)firstKey, ... NS_REQUIRES_NIL_TERMINATION;
@end
