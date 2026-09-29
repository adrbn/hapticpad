#include "CMultitouch.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stddef.h>

// MARK: - Private framework types (reverse engineered, stable since macOS 10.x)

typedef struct {
    float x;
    float y;
} MTPoint;

typedef struct {
    MTPoint position;
    MTPoint velocity;
} MTVector;

typedef struct {
    int frame;
    double timestamp;
    int identifier;
    int state;
    int fingerID;
    int handID;
    MTVector normalized;
    float size;
    int unknown1;
    float angle;
    float majorAxis;
    float minorAxis;
    MTVector absolute;
    int unknown2;
    int unknown3;
    float density;
} MTTouch;

typedef void *MTDeviceRef;
typedef void (*MTFrameCallback)(MTDeviceRef device, MTTouch *touches, int count, double timestamp, int frame);

typedef CFArrayRef (*MTDeviceCreateListFn)(void);
typedef OSStatus (*MTDeviceGetDeviceIDFn)(MTDeviceRef, uint64_t *);
typedef bool (*MTDeviceBoolFn)(MTDeviceRef);
typedef OSStatus (*MTDeviceGetDimensionsFn)(MTDeviceRef, int *, int *);
typedef void (*MTRegisterFrameCallbackFn)(MTDeviceRef, MTFrameCallback);
typedef OSStatus (*MTDeviceStartFn)(MTDeviceRef, int);
typedef OSStatus (*MTDeviceStopFn)(MTDeviceRef);
typedef CFTypeRef (*MTActuatorCreateFromDeviceIDFn)(uint64_t);
typedef IOReturn (*MTActuatorOpenFn)(CFTypeRef);
typedef IOReturn (*MTActuatorCloseFn)(CFTypeRef);
typedef IOReturn (*MTActuatorActuateFn)(CFTypeRef, int32_t, uint32_t, float, float);

static struct {
    bool loaded;
    bool available;
    MTDeviceCreateListFn createList;
    MTDeviceGetDeviceIDFn getDeviceID;
    MTDeviceBoolFn isBuiltIn;
    MTDeviceBoolFn supportsActuation;
    MTDeviceGetDimensionsFn getSurfaceDimensions;
    MTRegisterFrameCallbackFn registerFrameCallback;
    MTRegisterFrameCallbackFn unregisterFrameCallback;
    MTDeviceStartFn start;
    MTDeviceStopFn stop;
    MTActuatorCreateFromDeviceIDFn actuatorCreate;
    MTActuatorOpenFn actuatorOpen;
    MTActuatorCloseFn actuatorClose;
    MTActuatorActuateFn actuatorActuate;
} api;

static pthread_once_t load_once = PTHREAD_ONCE_INIT;

static void load_api(void) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW);
    api.loaded = true;
    if (handle == NULL) {
        return;
    }
    api.createList = (MTDeviceCreateListFn)dlsym(handle, "MTDeviceCreateList");
    api.getDeviceID = (MTDeviceGetDeviceIDFn)dlsym(handle, "MTDeviceGetDeviceID");
    api.isBuiltIn = (MTDeviceBoolFn)dlsym(handle, "MTDeviceIsBuiltIn");
    api.supportsActuation = (MTDeviceBoolFn)dlsym(handle, "MTDeviceSupportsActuation");
    api.getSurfaceDimensions = (MTDeviceGetDimensionsFn)dlsym(handle, "MTDeviceGetSensorSurfaceDimensions");
    api.registerFrameCallback = (MTRegisterFrameCallbackFn)dlsym(handle, "MTRegisterContactFrameCallback");
    api.unregisterFrameCallback = (MTRegisterFrameCallbackFn)dlsym(handle, "MTUnregisterContactFrameCallback");
    api.start = (MTDeviceStartFn)dlsym(handle, "MTDeviceStart");
    api.stop = (MTDeviceStopFn)dlsym(handle, "MTDeviceStop");
    api.actuatorCreate = (MTActuatorCreateFromDeviceIDFn)dlsym(handle, "MTActuatorCreateFromDeviceID");
    api.actuatorOpen = (MTActuatorOpenFn)dlsym(handle, "MTActuatorOpen");
    api.actuatorClose = (MTActuatorCloseFn)dlsym(handle, "MTActuatorClose");
    api.actuatorActuate = (MTActuatorActuateFn)dlsym(handle, "MTActuatorActuate");

    // MTDeviceIsBuiltIn and MTDeviceSupportsActuation are optional refinements.
    api.available = api.createList && api.getDeviceID && api.getSurfaceDimensions &&
                    api.registerFrameCallback && api.unregisterFrameCallback && api.start && api.stop &&
                    api.actuatorCreate && api.actuatorOpen && api.actuatorClose && api.actuatorActuate;
}

bool tx_multitouch_available(void) {
    pthread_once(&load_once, load_api);
    return api.available;
}

// MARK: - Device enumeration

static bool device_is_haptic(MTDeviceRef device) {
    if (api.supportsActuation != NULL) {
        return api.supportsActuation(device);
    }
    // Without the capability query, only trust the built-in trackpad.
    return api.isBuiltIn != NULL && api.isBuiltIn(device);
}

static TXDeviceInfo describe_device(MTDeviceRef device) {
    TXDeviceInfo info = {0};
    api.getDeviceID(device, &info.deviceID);
    info.builtIn = api.isBuiltIn != NULL && api.isBuiltIn(device);
    int width = 0;
    int height = 0;
    if (api.getSurfaceDimensions(device, &width, &height) == 0 && width > 0 && height > 0) {
        // Reported in hundredths of a millimetre.
        info.widthMM = (float)width / 100.0f;
        info.heightMM = (float)height / 100.0f;
    }
    return info;
}

int32_t tx_multitouch_list_devices(TXDeviceInfo *out, int32_t capacity) {
    if (!tx_multitouch_available()) {
        return 0;
    }
    CFArrayRef list = api.createList();
    if (list == NULL) {
        return 0;
    }
    int32_t found = 0;
    CFIndex total = CFArrayGetCount(list);
    for (CFIndex i = 0; i < total; i++) {
        MTDeviceRef device = (MTDeviceRef)CFArrayGetValueAtIndex(list, i);
        if (!device_is_haptic(device)) {
            continue;
        }
        if (out != NULL && found < capacity) {
            out[found] = describe_device(device);
        }
        found++;
    }
    CFRelease(list);
    return found;
}

// MARK: - Contact frames

enum { kMaxDevices = 8, kMaxTouches = 20 };

// MTDeviceStart run mode that keeps the framework from logging to stdout.
static const int kRunModeQuiet = 0x10000000;

// Start and stop take the write side. The frame callback only tries the read side:
// stopping a device may wait for the framework thread, so the callback must never block.
static pthread_rwlock_t state_lock = PTHREAD_RWLOCK_INITIALIZER;
static CFArrayRef running_list = NULL;
static MTDeviceRef running_devices[kMaxDevices];
static uint64_t running_ids[kMaxDevices];
static int32_t running_count = 0;
static TXFrameHandler frame_handler = NULL;
static void *frame_context = NULL;

static uint64_t id_for_device(MTDeviceRef device) {
    for (int32_t i = 0; i < running_count; i++) {
        if (running_devices[i] == device) {
            return running_ids[i];
        }
    }
    return 0;
}

static void on_contact_frame(MTDeviceRef device, MTTouch *touches, int count, double timestamp, int frame) {
    (void)frame;
    // A frame that lands while the stream is starting or stopping is dropped.
    if (pthread_rwlock_tryrdlock(&state_lock) != 0) {
        return;
    }
    if (frame_handler != NULL) {
        TXTouch converted[kMaxTouches];
        int32_t n = count < 0 ? 0 : (count < kMaxTouches ? count : kMaxTouches);
        for (int32_t i = 0; i < n; i++) {
            converted[i].identifier = touches[i].identifier;
            converted[i].state = touches[i].state;
            converted[i].x = touches[i].normalized.position.x;
            converted[i].y = touches[i].normalized.position.y;
            converted[i].size = touches[i].size;
        }
        frame_handler(id_for_device(device), converted, n, timestamp, frame_context);
    }
    pthread_rwlock_unlock(&state_lock);
}

static void stop_locked(void) {
    for (int32_t i = 0; i < running_count; i++) {
        api.unregisterFrameCallback(running_devices[i], on_contact_frame);
        api.stop(running_devices[i]);
    }
    running_count = 0;
    if (running_list != NULL) {
        CFRelease(running_list);
        running_list = NULL;
    }
    frame_handler = NULL;
    frame_context = NULL;
}

int32_t tx_multitouch_start(TXFrameHandler handler, void *context) {
    if (!tx_multitouch_available() || handler == NULL) {
        return 0;
    }
    pthread_rwlock_wrlock(&state_lock);
    stop_locked();

    CFArrayRef list = api.createList();
    if (list != NULL) {
        frame_handler = handler;
        frame_context = context;
        CFIndex total = CFArrayGetCount(list);
        for (CFIndex i = 0; i < total && running_count < kMaxDevices; i++) {
            MTDeviceRef device = (MTDeviceRef)CFArrayGetValueAtIndex(list, i);
            if (!device_is_haptic(device)) {
                continue;
            }
            running_devices[running_count] = device;
            api.getDeviceID(device, &running_ids[running_count]);
            running_count++;
            api.registerFrameCallback(device, on_contact_frame);
            api.start(device, kRunModeQuiet);
        }
        // The list owns the device objects; keep it alive while they run.
        running_list = list;
    }
    int32_t started = running_count;
    pthread_rwlock_unlock(&state_lock);
    return started;
}

void tx_multitouch_stop(void) {
    if (!tx_multitouch_available()) {
        return;
    }
    pthread_rwlock_wrlock(&state_lock);
    stop_locked();
    pthread_rwlock_unlock(&state_lock);
}

// MARK: - Actuator

void *tx_actuator_open(uint64_t deviceID) {
    if (!tx_multitouch_available() || deviceID == 0) {
        return NULL;
    }
    CFTypeRef actuator = api.actuatorCreate(deviceID);
    if (actuator == NULL) {
        return NULL;
    }
    if (api.actuatorOpen(actuator) != kIOReturnSuccess) {
        CFRelease(actuator);
        return NULL;
    }
    return (void *)actuator;
}

bool tx_actuator_actuate(void *actuator, int32_t actuationID, float unknown2, float unknown3) {
    if (actuator == NULL || !tx_multitouch_available()) {
        return false;
    }
    return api.actuatorActuate((CFTypeRef)actuator, actuationID, 0, unknown2, unknown3) == kIOReturnSuccess;
}

void tx_actuator_close(void *actuator) {
    if (actuator == NULL || !tx_multitouch_available()) {
        return;
    }
    api.actuatorClose((CFTypeRef)actuator);
    CFRelease((CFTypeRef)actuator);
}
