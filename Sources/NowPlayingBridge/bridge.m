#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#include <dlfcn.h>
#include <stdio.h>

typedef void (*MRGetNowPlayingInfo)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*MRGetIsPlaying)(dispatch_queue_t, void (^)(Boolean));
typedef void (*MRGetClient)(dispatch_queue_t, void (^)(id));
typedef CFStringRef (*MRClientBundleID)(id);
typedef void (*MRRegisterNotifications)(dispatch_queue_t);
typedef Boolean (*MRSendCommand)(uint32_t, CFDictionaryRef);
typedef void (*MRSetElapsedTime)(double);

enum { kMRPlay = 0, kMRPause = 1, kMRTogglePlayPause = 2, kMRNextTrack = 4, kMRPreviousTrack = 5 };

static MRGetNowPlayingInfo     gGetInfo;
static MRGetIsPlaying          gGetIsPlaying;
static MRGetClient             gGetClient;
static MRClientBundleID        gClientBundleID;
static MRSendCommand           gSendCommand;
static MRSetElapsedTime        gSetElapsedTime;

static dispatch_queue_t gQueue;
static NSData          *gLastArtwork;
static NSString        *gLastTitle;
static uint64_t         gGeneration;

static NSString *StringValue(CFDictionaryRef info, const char *key) {
    id value = (__bridge id)CFDictionaryGetValue(info, (__bridge CFStringRef)@(key));
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static NSNumber *NumberValue(CFDictionaryRef info, const char *key) {
    id value = (__bridge id)CFDictionaryGetValue(info, (__bridge CFStringRef)@(key));
    return [value isKindOfClass:NSNumber.class] ? value : nil;
}

static void EmitLine(NSDictionary *payload) {
    NSError *error = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&error];
    if (!json) return;
    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static void Publish(void) {
    gGetIsPlaying(gQueue, ^(Boolean isPlaying) {
        gGetInfo(gQueue, ^(CFDictionaryRef info) {
            NSMutableDictionary *out = [NSMutableDictionary dictionary];
            out[@"playing"] = @(isPlaying != 0);

            if (info) {
                NSString *title  = StringValue(info, "kMRMediaRemoteNowPlayingInfoTitle");
                NSString *artist = StringValue(info, "kMRMediaRemoteNowPlayingInfoArtist");
                NSString *album  = StringValue(info, "kMRMediaRemoteNowPlayingInfoAlbum");
                if (title)  out[@"title"]  = title;
                if (artist) out[@"artist"] = artist;
                if (album)  out[@"album"]  = album;

                NSNumber *duration = NumberValue(info, "kMRMediaRemoteNowPlayingInfoDuration");
                NSNumber *elapsed  = NumberValue(info, "kMRMediaRemoteNowPlayingInfoElapsedTime");
                if (duration) out[@"duration"] = duration;
                if (elapsed)  out[@"elapsed"]  = elapsed;

                NSNumber *rate = NumberValue(info, "kMRMediaRemoteNowPlayingInfoPlaybackRate");
                if (rate) out[@"rate"] = rate;
                id stamp = (__bridge id)CFDictionaryGetValue(
                    info, (__bridge CFStringRef)@"kMRMediaRemoteNowPlayingInfoTimestamp");
                if ([stamp isKindOfClass:NSDate.class]) {
                    out[@"timestamp"] = @([(NSDate *)stamp timeIntervalSince1970]);
                }

                id artwork = (__bridge id)CFDictionaryGetValue(
                    info, (__bridge CFStringRef)@"kMRMediaRemoteNowPlayingInfoArtworkData");
                NSData *artworkData = [artwork isKindOfClass:NSData.class] ? artwork : nil;

                if (artworkData.length > 0) {
                    if (![artworkData isEqualToData:gLastArtwork]) {
                        gLastArtwork = artworkData;
                        out[@"artwork"] = [artworkData base64EncodedStringWithOptions:0];
                    }
                } else if (gLastArtwork != nil && ![title isEqualToString:gLastTitle]) {
                    gLastArtwork = nil;
                    out[@"artwork"] = NSNull.null;
                }
                gLastTitle = title;
            } else if (gLastArtwork != nil && gLastTitle != nil) {
                gLastArtwork = nil;
                gLastTitle = nil;
                out[@"artwork"] = NSNull.null;
            }

            if (gGetClient && gClientBundleID) {
                gGetClient(gQueue, ^(id client) {
                    if (client) {
                        CFStringRef bundleID = gClientBundleID(client);
                        if (bundleID) out[@"app"] = (__bridge NSString *)bundleID;
                    }
                    EmitLine(out);
                });
            } else {
                EmitLine(out);
            }
        });
    });
}

static void PublishSoon(void) {
    uint64_t generation = ++gGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_MSEC), gQueue, ^{
        if (generation == gGeneration) Publish();
    });
}

static void ObserveNotification(void *handle, const char *symbol) {
    CFStringRef *name = (CFStringRef *)dlsym(handle, symbol);
    if (!name || !*name) return;
    [NSNotificationCenter.defaultCenter addObserverForName:(__bridge NSString *)*name
                                                   object:nil
                                                    queue:nil
                                               usingBlock:^(NSNotification *note) { PublishSoon(); }];
}

static void ReadCommands(void) {
    char line[256];
    while (fgets(line, sizeof(line), stdin)) {
        NSString *command = [[NSString stringWithUTF8String:line]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];

        if ([command hasPrefix:@"seek "] && gSetElapsedTime) {
            gSetElapsedTime([command substringFromIndex:5].doubleValue);
            PublishSoon();
            continue;
        }
        if (!gSendCommand) continue;
        if      ([command isEqualToString:@"play"])    gSendCommand(kMRPlay, NULL);
        else if ([command isEqualToString:@"pause"])   gSendCommand(kMRPause, NULL);
        else if ([command isEqualToString:@"toggle"])  gSendCommand(kMRTogglePlayPause, NULL);
        else if ([command isEqualToString:@"next"])    gSendCommand(kMRNextTrack, NULL);
        else if ([command isEqualToString:@"prev"])    gSendCommand(kMRPreviousTrack, NULL);
        else if ([command isEqualToString:@"refresh"]) dispatch_async(gQueue, ^{ Publish(); });
        if (![command isEqualToString:@"refresh"]) PublishSoon();
    }
    exit(0);
}

__attribute__((constructor))
static void BridgeMain(void) {
    @autoreleasepool {
        void *handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
                              RTLD_NOW);
        if (!handle) {
            EmitLine(@{@"error": @"MediaRemote.framework is unavailable"});
            exit(1);
        }

        gGetInfo        = (MRGetNowPlayingInfo)dlsym(handle, "MRMediaRemoteGetNowPlayingInfo");
        gGetIsPlaying   = (MRGetIsPlaying)dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
        gGetClient      = (MRGetClient)dlsym(handle, "MRMediaRemoteGetNowPlayingClient");
        gClientBundleID = (MRClientBundleID)dlsym(handle, "MRNowPlayingClientGetBundleIdentifier");
        gSendCommand    = (MRSendCommand)dlsym(handle, "MRMediaRemoteSendCommand");
        gSetElapsedTime = (MRSetElapsedTime)dlsym(handle, "MRMediaRemoteSetElapsedTime");
        MRRegisterNotifications registerNotifications =
            (MRRegisterNotifications)dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications");

        if (!gGetInfo || !gGetIsPlaying || !registerNotifications) {
            EmitLine(@{@"error": @"MediaRemote symbols are missing on this macOS build"});
            exit(1);
        }

        gQueue = dispatch_queue_create("dev.danil.vinyl.bridge", DISPATCH_QUEUE_SERIAL);
        registerNotifications(gQueue);

        ObserveNotification(handle, "kMRMediaRemoteNowPlayingInfoDidChangeNotification");
        ObserveNotification(handle, "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification");
        ObserveNotification(handle, "kMRMediaRemoteNowPlayingApplicationDidChangeNotification");

        dispatch_async(gQueue, ^{ Publish(); });

        dispatch_source_t poll = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, gQueue);
        dispatch_source_set_timer(poll, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                                  2 * NSEC_PER_SEC, 500 * NSEC_PER_MSEC);
        dispatch_source_set_event_handler(poll, ^{ Publish(); });
        dispatch_resume(poll);
        CFRetain((__bridge CFTypeRef)poll);

        [NSThread detachNewThreadWithBlock:^{ ReadCommands(); }];
    }
}
