# TERecord

Clojure inspired records for Objective-C. Fully KVO-compliant.

    git submodule init
    git submodule update

## Step 1: Instead of a class, create a protocol

```objc
@protocol Folder <TERecord>
@property (nonatomic, strong) NSString *uuid;
@property (nonatomic, strong) id<Storage> storage;
@property (nonatomic, strong) id<DiskInfo> diskinfo;
@property (nonatomic, strong) NSURL *mountpoint;
@property (nonatomic, strong) NSNumber *autounlock;
@property (nonatomic, strong) NSNumber *encrypted;
@property (nonatomic, strong) NSNumber *autolock;
@property (nonatomic, strong) NSMutableArray *lockActions;
@property (nonatomic, strong) NSMutableArray *unlockActions;
@end
```

## Step 2: Call `TERecordCreate` to create instances

```objc
id<Folder> TEFolderCreate(id<Storage> storage, NSURL *mountpoint)
{
    id<Folder> f = TERecordCreate(@protocol(Folder));
    f.uuid = [NSString UUID];
    f.storage = storage;
    f.mountpoint = mountpoint;
    f.autolock = @0;
    f.autounlock = @NO;
    f.encrypted = @NO;
    f.unlockActions = [[NSMutableArray alloc] init];
    f.lockActions = [[NSMutableArray alloc] init];
    return f;
}
```

## Step 3: There is no step 3!

That's it! You can now use these instances just as you would regular instances of Objective-C classes, except there's no need to create any accessors for them! They can even be serialized to disk and loaded back!

## Updating serialized records with new properties from the protocol

Simply call `TERecordUpdateProtocol` on the instance, like so:

```objc
TERecordUpdateProtocol(folder, @protocol(Folder));
```

Please see [this blog post for original (outdated) explanation](https://www.taoeffect.com/blog/2011/05/better-objective-c-through-clojure-philosophy/).

# License

Simplified BSD:

    Copyright 2011 Tao Effect LLC. All rights reserved.
    
    Redistribution and use in source and binary forms, with or without modification, are
    permitted provided that the following conditions are met:
    
       1. Redistributions of source code must retain the above copyright notice, this list of
          conditions and the following disclaimer.
    
       2. Redistributions in binary form must reproduce the above copyright notice, this list
          of conditions and the following disclaimer in the documentation and/or other materials
          provided with the distribution.
    
    THIS SOFTWARE IS PROVIDED BY TAO EFFECT LLC ``AS IS'' AND ANY EXPRESS OR IMPLIED
    WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
    FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> OR
    CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
    CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
    SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
    ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
    NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
    ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
    
    The views and conclusions contained in the software and documentation are those of the
    authors and should not be interpreted as representing official policies, either expressed
    or implied, of Tao Effect LLC.
