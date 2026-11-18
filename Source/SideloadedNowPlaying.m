// Adapted from dayanch96/YTMusicUltimate PR #465 by saichowdary007
// (dde981ec37a775b460df69eb1059f5817ad9a18b), under GPL-3.0.
// Publishes system Now Playing metadata; it grants no CarPlay entitlement.
#import <MediaPlayer/MediaPlayer.h>
#import <UIKit/UIKit.h>
#import <math.h>
#import "SideloadedNowPlaying.h"
#import "Utils/YTMUKVC.h"
#import "Utils/YTMUSettings.h"

static NSString *YTMUCurrentNowPlayingVideoID;
static NSTimeInterval YTMULastNowPlayingUpdate;
static NSCache<NSString *, MPMediaItemArtwork *> *YTMUNowPlayingArtworkCache;

static NSString *YTMUNowPlayingString(id value) {
    return [value isKindOfClass:NSString.class] ? value : @"";
}

static double YTMUNowPlayingNumber(id value) {
    return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : NAN;
}

static void YTMUSetNowPlayingArtwork(MPMediaItemArtwork *artwork, NSString *videoID) {
    if (!YTMU(@"YTMUltimateIsEnabled") || !artwork ||
        ![YTMUCurrentNowPlayingVideoID isEqualToString:videoID]) return;
    MPNowPlayingInfoCenter *center = MPNowPlayingInfoCenter.defaultCenter;
    // The app may have switched tracks while the image was downloading.
    NSString *publishedID = center.nowPlayingInfo[MPNowPlayingInfoPropertyExternalContentIdentifier];
    if (![publishedID isEqualToString:videoID]) return;
    NSMutableDictionary *info = [center.nowPlayingInfo mutableCopy];
    info[MPMediaItemPropertyArtwork] = artwork;
    center.nowPlayingInfo = info;
}

static void YTMULoadNowPlayingArtwork(id details, NSString *videoID) {
    MPMediaItemArtwork *cached = [YTMUNowPlayingArtworkCache objectForKey:videoID];
    if (cached) {
        YTMUSetNowPlayingArtwork(cached, videoID);
        return;
    }
    id thumbnails = YTMUSafeValueForKeyPath(details, @"thumbnail.thumbnailsArray");
    if (![thumbnails isKindOfClass:NSArray.class]) return;
    NSString *urlString = YTMUNowPlayingString(YTMUSafeValueForKey([thumbnails lastObject], @"URL"));
    NSURL *url = urlString.length ? [NSURL URLWithString:urlString] : nil;
    if (![url.scheme.lowercaseString isEqualToString:@"https"]) return;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 8;
    [[[NSURLSession sharedSession] dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error || !data.length) return;
        if ([response isKindOfClass:NSHTTPURLResponse.class] &&
            ((NSHTTPURLResponse *)response).statusCode != 200) return;
        UIImage *image = [UIImage imageWithData:data];
        if (!image) return;
        MPMediaItemArtwork *artwork = [[MPMediaItemArtwork alloc]
            initWithBoundsSize:image.size requestHandler:^UIImage *(CGSize size) { return image; }];
        [YTMUNowPlayingArtworkCache setObject:artwork forKey:videoID];
        dispatch_async(dispatch_get_main_queue(), ^{ YTMUSetNowPlayingArtwork(artwork, videoID); });
    }] resume];
}

void YTMUSideloadedNowPlayingUpdate(id player, BOOL trackChanged) {
    if (!YTMU(@"YTMUltimateIsEnabled") || !player) return;
    void (^update)(void) = ^{
        if (!YTMU(@"YTMUltimateIsEnabled")) return;
        NSString *videoID = YTMUNowPlayingString(YTMUSafeValueForKey(player, @"currentVideoID"));
        if (!videoID.length) videoID = YTMUNowPlayingString(YTMUSafeValueForKey(player, @"contentVideoID"));
        if (!videoID.length) return;
        BOOL changed = ![YTMUCurrentNowPlayingVideoID isEqualToString:videoID];
        NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
        if (!trackChanged && !changed && now - YTMULastNowPlayingUpdate < 1.0) return;
        YTMULastNowPlayingUpdate = now;

        id response = YTMUSafeValueForKey(player, @"playerResponse");
        if (!response) response = YTMUSafeValueForKey(player, @"contentPlayerResponse");
        id details = YTMUSafeValueForKeyPath(response, @"playerData.videoDetails");
        if (!details) return;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            YTMUNowPlayingArtworkCache = [NSCache new];
            YTMUNowPlayingArtworkCache.countLimit = 20;
        });
        MPNowPlayingInfoCenter *center = MPNowPlayingInfoCenter.defaultCenter;
        NSMutableDictionary *info = [center.nowPlayingInfo mutableCopy] ?: [NSMutableDictionary dictionary];
        if (changed) {
            // Never retain the preceding song's metadata if the next one lacks a field.
            [info removeObjectsForKeys:@[MPMediaItemPropertyTitle, MPMediaItemPropertyArtist,
                MPMediaItemPropertyPlaybackDuration, MPNowPlayingInfoPropertyElapsedPlaybackTime,
                MPMediaItemPropertyArtwork]];
        }
        NSString *title = YTMUNowPlayingString(YTMUSafeValueForKey(details, @"title"));
        NSString *artist = YTMUNowPlayingString(YTMUSafeValueForKey(details, @"author"));
        if (title.length) info[MPMediaItemPropertyTitle] = title;
        if (artist.length) info[MPMediaItemPropertyArtist] = artist;
        double duration = YTMUNowPlayingNumber(YTMUSafeValueForKey(player, @"currentVideoTotalMediaTime"));
        double elapsed = YTMUNowPlayingNumber(YTMUSafeValueForKey(player, @"currentVideoMediaTime"));
        if (isfinite(duration) && duration > 0) info[MPMediaItemPropertyPlaybackDuration] = @(duration);
        if (isfinite(elapsed) && elapsed >= 0) info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(elapsed);
        info[MPNowPlayingInfoPropertyMediaType] = @(MPNowPlayingInfoMediaTypeAudio);
        info[MPNowPlayingInfoPropertyExternalContentIdentifier] = videoID;
        // Preserve the app's playback rate/live flags so pause and live streams stay correct.
        YTMUCurrentNowPlayingVideoID = [videoID copy];
        center.nowPlayingInfo = info;
        if (changed) YTMULoadNowPlayingArtwork(details, videoID);
    };
    if (NSThread.isMainThread) update();
    else dispatch_async(dispatch_get_main_queue(), update);
}
