#ifndef CMULTITOUCH_H
#define CMULTITOUCH_H

// A small, stable C surface over Apple's private MultitouchSupport framework.
//
// The framework is loaded with dlopen at runtime, never linked, so a future macOS
// that renames or removes a symbol makes these functions report "unavailable"
// instead of crashing the app at launch.

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Touch path stages reported by the trackpad firmware.
typedef enum {
    HPTouchStateNotTracking = 0,
    HPTouchStateStartInRange = 1,
    HPTouchStateHoverInRange = 2,
    HPTouchStateMakeTouch = 3,
    HPTouchStateTouching = 4,
    HPTouchStateBreakTouch = 5,
    HPTouchStateLingerInRange = 6,
    HPTouchStateOutOfRange = 7,
} HPTouchState;

/// One finger in a contact frame. Positions are normalized (0...1, origin bottom-left).
typedef struct {
    int32_t identifier;
    int32_t state;
    float x;
    float y;
    float size;
} HPTouch;

/// Static description of a multitouch surface that can play haptics.
typedef struct {
    uint64_t deviceID;
    bool builtIn;
    /// Physical surface size in millimetres (0 when unknown).
    float widthMM;
    float heightMM;
} HPDeviceInfo;

/// Called on a framework-owned thread for every contact frame of every started device.
/// It runs with the stream locked, so it must return quickly and must not call
/// hp_multitouch_start or hp_multitouch_stop.
typedef void (*HPFrameHandler)(uint64_t deviceID,
                               const HPTouch *touches,
                               int32_t count,
                               double timestamp,
                               void *context);

/// True when the private framework and every symbol we need could be resolved.
bool hp_multitouch_available(void);

/// Starts delivering contact frames from every surface that supports actuation,
/// replacing any stream already running. Returns the number of devices started
/// (0 when none or unavailable).
int32_t hp_multitouch_start(HPFrameHandler handler, void *context);

/// Stops every device started by hp_multitouch_start. Safe to call repeatedly.
/// Once it returns (or a new start returns), the previous handler and context are
/// never used again, so the caller may release the context.
void hp_multitouch_stop(void);

/// Copies up to `capacity` actuation-capable devices into `out`. Returns the total found.
int32_t hp_multitouch_list_devices(HPDeviceInfo *out, int32_t capacity);

/// Opens the Taptic actuator of a device. Returns an opaque retained handle, or NULL.
void *hp_actuator_open(uint64_t deviceID);

/// Plays one predefined waveform. Returns false when the actuator rejected it.
bool hp_actuator_actuate(void *actuator, int32_t actuationID, float unknown2, float unknown3);

/// Closes and releases a handle returned by hp_actuator_open. NULL is ignored.
void hp_actuator_close(void *actuator);

#ifdef __cplusplus
}
#endif

#endif /* CMULTITOUCH_H */
