#ifndef MAC_SENSOR_LAB_C_NVME_SMART_H
#define MAC_SENSOR_LAB_C_NVME_SMART_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
  MSL_NVME_SMART_STATUS_SUCCESS = 0,
  MSL_NVME_SMART_STATUS_SYSTEM_VOLUME_UNAVAILABLE = 1,
  MSL_NVME_SMART_STATUS_SMART_UNAVAILABLE = 2,
  MSL_NVME_SMART_STATUS_INTERFACE_UNAVAILABLE = 3,
  MSL_NVME_SMART_STATUS_PERMISSION_DENIED = 4,
  MSL_NVME_SMART_STATUS_TEMPORARILY_UNAVAILABLE = 5,
  MSL_NVME_SMART_STATUS_READ_FAILED = 6,
  MSL_NVME_SMART_STATUS_INVALID_ARGUMENT = 7,
};

typedef struct {
  uint8_t critical_warning;
  uint16_t temperature_kelvin;
  uint8_t available_spare;
  uint8_t available_spare_threshold;
  uint8_t percentage_used;
} MSLNVMeSMARTScalarData;

/// Reads only the scalar SMART fields for the whole disk backing the current system volume.
///
/// The implementation does not read identify data, names, serial numbers, BSD paths, registry
/// paths, detailed error logs, or any other storage device. It performs no write operation.
int32_t MSLReadSystemNVMeSMARTScalars(MSLNVMeSMARTScalarData *output);

#ifdef __cplusplus
}
#endif

#endif
