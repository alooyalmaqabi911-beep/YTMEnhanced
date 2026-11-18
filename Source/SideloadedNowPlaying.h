#import <Foundation/Foundation.h>

// Keep the existing player hooks in SyncedLyrics.x as the single entry point.
#if defined(YTMU_SIDELOADING) || defined(YTMU_HOST_TESTS)
#ifdef __cplusplus
extern "C" {
#endif
void YTMUSideloadedNowPlayingUpdate(id player, BOOL trackChanged);
#ifdef __cplusplus
}
#endif
#else
static inline void YTMUSideloadedNowPlayingUpdate(id player, BOOL trackChanged) {}
#endif
