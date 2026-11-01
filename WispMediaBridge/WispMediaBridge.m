// Wisp media bridge.
//
// macOS only answers system-wide Now Playing queries (MediaRemote) for Apple-signed
// processes. Wisp loads this library into /usr/bin/perl, which qualifies, and the
// library streams Now Playing as JSON lines on stdout. Commands arrive on stdin, one
// per line: "toggle", "next", "previous", "seek <seconds>". The process exits when
// stdin closes, so it never outlives Wisp.
//
// Entry point: wisp_media_bridge_run, installed as a Perl XSUB by the loader.

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdio.h>
#include <unistd.h>

typedef void (*MRGetNowPlayingInfo)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*MRGetIsPlaying)(dispatch_queue_t, void (^)(BOOL));
typedef void (*MRGetApplicationPID)(dispatch_queue_t, void (^)(int));
typedef void (*MRRegisterForNotifications)(dispatch_queue_t);
typedef Boolean (*MRSendCommand)(int, NSDictionary *);
typedef void (*MRSetElapsedTime)(double);

// MRMediaRemoteCommand values.
enum { WispTogglePlayPause = 2, WispNextTrack = 4, WispPreviousTrack = 5 };

static MRGetNowPlayingInfo getInfo;
static MRGetIsPlaying getIsPlaying;
static MRGetApplicationPID getPID;
static MRSendCommand sendCommand;
static MRSetElapsedTime setElapsed;
static NSData *lastArtwork;
static NSString *lastArtworkTrack;
static BOOL refreshQueued;

static void emit(NSDictionary *message) {
    // dataWithJSONObject: throws (rather than failing) on NaN or infinity, which would kill the host.
    if (![NSJSONSerialization isValidJSONObject:message]) return;
    NSData *json = [NSJSONSerialization dataWithJSONObject:message options:0 error:nil];
    if (!json) return;
    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static NSString *stringValue(id value) {
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

// Live streams can report an infinite duration; JSON has no way to say that.
static double numberValue(id value) {
    double number = [value isKindOfClass:[NSNumber class]] ? [value doubleValue] : 0;
    return isfinite(number) ? number : 0;
}

static void refresh(void) {
    refreshQueued = NO;
    getInfo(dispatch_get_main_queue(), ^(NSDictionary *info) {
        NSString *title = stringValue(info[@"kMRMediaRemoteNowPlayingInfoTitle"]);
        if (title.length == 0) {
            lastArtwork = nil;
            lastArtworkTrack = nil;
            emit(@{@"type" : @"none"});
            return;
        }
        getIsPlaying(dispatch_get_main_queue(), ^(BOOL playing) {
            getPID(dispatch_get_main_queue(), ^(int pid) {
                double elapsed = numberValue(info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"]);
                double rate = numberValue(info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"]);
                id timestamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
                // Elapsed time is reported as of the timestamp; bring it up to now.
                if (playing && [timestamp isKindOfClass:[NSDate class]]) {
                    elapsed += -[timestamp timeIntervalSinceNow] * (rate > 0 ? rate : 1);
                }

                NSMutableDictionary *message = [@{
                    @"type" : @"now",
                    @"title" : title,
                    @"artist" : stringValue(info[@"kMRMediaRemoteNowPlayingInfoArtist"]),
                    @"album" : stringValue(info[@"kMRMediaRemoteNowPlayingInfoAlbum"]),
                    @"duration" : @(numberValue(info[@"kMRMediaRemoteNowPlayingInfoDuration"])),
                    @"elapsed" : @(elapsed),
                    @"playing" : @(playing),
                } mutableCopy];

                NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
                if (app.bundleIdentifier) message[@"bundle"] = app.bundleIdentifier;
                if (app.localizedName) message[@"app"] = app.localizedName;

                // Artwork is large; send it only when it or the track changes. Wisp clears the
                // cover on a new track (including the same song in another app), so tracks sharing
                // an album cover must still get it. The track is remembered even without artwork,
                // so going back to a previous song sends its cover again.
                // -isEqualToData: compares every byte; -hash only looks at the first 80.
                id artwork = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                NSString *track = [NSString stringWithFormat:@"%@\n%@\n%@\n%@", title, message[@"artist"],
                                                             message[@"album"], app.bundleIdentifier ?: @""];
                NSData *data = [artwork isKindOfClass:[NSData class]] ? artwork : nil;
                if (data && (![track isEqualToString:lastArtworkTrack] || ![data isEqualToData:lastArtwork])) {
                    message[@"artwork"] = [data base64EncodedStringWithOptions:0];
                }
                lastArtwork = data;
                lastArtworkTrack = track;
                emit(message);
            });
        });
    });
}

/// Coalesces bursts of change notifications into one read.
static void scheduleRefresh(void) {
    if (refreshQueued) return;
    refreshQueued = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 80 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        refresh();
    });
}

static void handleCommand(NSString *line) {
    NSString *command = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([command isEqualToString:@"toggle"]) {
        sendCommand(WispTogglePlayPause, nil);
    } else if ([command isEqualToString:@"next"]) {
        sendCommand(WispNextTrack, nil);
    } else if ([command isEqualToString:@"previous"]) {
        sendCommand(WispPreviousTrack, nil);
    } else if ([command hasPrefix:@"seek "] && setElapsed) {
        setElapsed([[command substringFromIndex:5] doubleValue]);
    }
    scheduleRefresh();
}

static void readCommands(void) {
    static NSMutableData *buffer;
    buffer = [NSMutableData data];
    dispatch_source_t source =
        dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(source, ^{
        char chunk[1024];
        ssize_t count = read(STDIN_FILENO, chunk, sizeof chunk);
        if (count <= 0) exit(0);  // Wisp went away.
        [buffer appendBytes:chunk length:(NSUInteger)count];
        NSData *newline = [@"\n" dataUsingEncoding:NSUTF8StringEncoding];
        NSRange found;
        while ((found = [buffer rangeOfData:newline options:0 range:NSMakeRange(0, buffer.length)]).location
               != NSNotFound) {
            NSData *lineData = [buffer subdataWithRange:NSMakeRange(0, found.location)];
            [buffer replaceBytesInRange:NSMakeRange(0, found.location + 1) withBytes:NULL length:0];
            handleCommand([[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding] ?: @"");
        }
    });
    dispatch_resume(source);
    // Keep the source alive for the life of the process.
    static dispatch_source_t retained;
    retained = source;
}

void wisp_media_bridge_run(void *perl, void *cv) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!handle) {
        emit(@{@"type" : @"error", @"message" : @"MediaRemote unavailable"});
        exit(2);
    }
    getInfo = (MRGetNowPlayingInfo)dlsym(handle, "MRMediaRemoteGetNowPlayingInfo");
    getIsPlaying = (MRGetIsPlaying)dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    getPID = (MRGetApplicationPID)dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID");
    sendCommand = (MRSendCommand)dlsym(handle, "MRMediaRemoteSendCommand");
    setElapsed = (MRSetElapsedTime)dlsym(handle, "MRMediaRemoteSetElapsedTime");
    MRRegisterForNotifications registerForNotifications =
        (MRRegisterForNotifications)dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications");
    if (!getInfo || !getIsPlaying || !getPID || !sendCommand || !registerForNotifications) {
        emit(@{@"type" : @"error", @"message" : @"MediaRemote symbols missing"});
        exit(3);
    }

    registerForNotifications(dispatch_get_main_queue());
    for (NSString *name in @[
             @"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
             @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
             @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
         ]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name
                                                        object:nil
                                                         queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(NSNotification *note) {
                                                        scheduleRefresh();
                                                    }];
    }
    readCommands();
    refresh();
    CFRunLoopRun();
}
