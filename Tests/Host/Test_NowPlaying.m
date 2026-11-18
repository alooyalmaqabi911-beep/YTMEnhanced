#import "YTMUTestKit.h"
#import "YTMUTestSettings.h"
#import "SideloadedNowPlaying.h"
#import <MediaPlayer/MediaPlayer.h>
#import <math.h>

static NSDictionary *NowPlayingTestPlayer(NSString *videoID, NSDictionary *details,
                                          NSNumber *duration, NSNumber *elapsed) {
    return @{@"currentVideoID": videoID,
             @"playerResponse": @{@"playerData": @{@"videoDetails": details}},
             @"currentVideoTotalMediaTime": duration, @"currentVideoMediaTime": elapsed};
}

YTMU_TEST(NowPlaying_publishesMetadata_preservesPause) {
    YTMUTestSetSettings(@{@"YTMUltimateIsEnabled": @YES});
    MPNowPlayingInfoCenter *center = MPNowPlayingInfoCenter.defaultCenter;
    NSDictionary *saved = center.nowPlayingInfo;
    center.nowPlayingInfo = @{MPNowPlayingInfoPropertyPlaybackRate: @0};
    YTMUSideloadedNowPlayingUpdate(NowPlayingTestPlayer(@"now-playing-test-a",
        @{@"title": @"أغنية", @"author": @"Artist"}, @200, @12), YES);
    NSDictionary *info = center.nowPlayingInfo;
    YTMU_ASSERT_EQ_STR(info[MPMediaItemPropertyTitle], @"أغنية");
    YTMU_ASSERT_EQ_STR(info[MPMediaItemPropertyArtist], @"Artist");
    YTMU_ASSERT_EQ_INT([info[MPMediaItemPropertyPlaybackDuration] integerValue], 200);
    YTMU_ASSERT_EQ_INT([info[MPNowPlayingInfoPropertyElapsedPlaybackTime] integerValue], 12);
    YTMU_ASSERT_EQ_INT([info[MPNowPlayingInfoPropertyPlaybackRate] integerValue], 0);
    center.nowPlayingInfo = saved;
}

YTMU_TEST(NowPlaying_trackChange_dropsOldMetadata_andInvalidTimes) {
    YTMUTestSetSettings(@{@"YTMUltimateIsEnabled": @YES});
    MPNowPlayingInfoCenter *center = MPNowPlayingInfoCenter.defaultCenter;
    NSDictionary *saved = center.nowPlayingInfo;
    YTMUSideloadedNowPlayingUpdate(NowPlayingTestPlayer(@"now-playing-test-b",
        @{@"title": @"Old", @"author": @"Old Artist"}, @90, @5), YES);
    // A periodic callback must also detect a changed song if activation was missed.
    YTMUSideloadedNowPlayingUpdate(NowPlayingTestPlayer(@"now-playing-test-c", @{}, @(NAN), @(-1)), NO);
    NSDictionary *info = center.nowPlayingInfo;
    YTMU_ASSERT(info[MPMediaItemPropertyTitle] == nil, "old title must not survive");
    YTMU_ASSERT(info[MPMediaItemPropertyArtist] == nil, "old artist must not survive");
    YTMU_ASSERT(info[MPMediaItemPropertyPlaybackDuration] == nil, "invalid duration must be omitted");
    YTMU_ASSERT(info[MPNowPlayingInfoPropertyElapsedPlaybackTime] == nil, "invalid elapsed time must be omitted");
    YTMU_ASSERT_EQ_STR(info[MPNowPlayingInfoPropertyExternalContentIdentifier], @"now-playing-test-c");
    center.nowPlayingInfo = saved;
}

YTMU_TEST(NowPlaying_disabled_orMissingPrivateData_doesNotOverwrite) {
    MPNowPlayingInfoCenter *center = MPNowPlayingInfoCenter.defaultCenter;
    NSDictionary *saved = center.nowPlayingInfo;
    center.nowPlayingInfo = @{MPMediaItemPropertyTitle: @"Existing"};
    YTMUTestSetSettings(@{@"YTMUltimateIsEnabled": @NO});
    YTMUSideloadedNowPlayingUpdate(NowPlayingTestPlayer(@"disabled", @{@"title": @"No"}, @20, @1), YES);
    YTMU_ASSERT_EQ_STR(center.nowPlayingInfo[MPMediaItemPropertyTitle], @"Existing");
    YTMUTestSetSettings(@{@"YTMUltimateIsEnabled": @YES});
    YTMUSideloadedNowPlayingUpdate([NSObject new], YES);
    YTMU_ASSERT_EQ_STR(center.nowPlayingInfo[MPMediaItemPropertyTitle], @"Existing");
    center.nowPlayingInfo = saved;
}
