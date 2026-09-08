#include "CNVMeSMART.h"

#include <CoreFoundation/CoreFoundation.h>
#include <DiskArbitration/DiskArbitration.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/storage/nvme/NVMeSMARTLibExternal.h>
#include <stdbool.h>
#include <string.h>

static bool MSLRegistryEntryIsNVMeSMARTCapable(io_registry_entry_t entry) {
  CFTypeRef value = IORegistryEntryCreateCFProperty(
      entry, CFSTR(kIOPropertyNVMeSMARTCapableKey), kCFAllocatorDefault, 0);
  bool capable = value != NULL && CFGetTypeID(value) == CFBooleanGetTypeID() &&
                 CFBooleanGetValue((CFBooleanRef)value);
  if (value != NULL) CFRelease(value);
  return capable;
}

static int32_t MSLStatusForIOReturn(IOReturn result, bool creating_interface) {
  switch (result) {
    case kIOReturnNotPrivileged:
    case kIOReturnNotPermitted:
      return MSL_NVME_SMART_STATUS_PERMISSION_DENIED;
    case kIOReturnBusy:
    case kIOReturnExclusiveAccess:
    case kIOReturnNotReady:
    case kIOReturnOffline:
      return MSL_NVME_SMART_STATUS_TEMPORARILY_UNAVAILABLE;
    default:
      return creating_interface ? MSL_NVME_SMART_STATUS_INTERFACE_UNAVAILABLE
                                : MSL_NVME_SMART_STATUS_READ_FAILED;
  }
}

static int32_t MSLReadScalarsFromService(
    io_service_t service, MSLNVMeSMARTScalarData *output) {
  IOCFPlugInInterface **plugin = NULL;
  IONVMeSMARTInterface **smart = NULL;
  SInt32 score = 0;
  IOReturn create_result = IOCreatePlugInInterfaceForService(
      service, kIONVMeSMARTUserClientTypeID, kIOCFPlugInInterfaceID, &plugin, &score);
  if (create_result != kIOReturnSuccess || plugin == NULL) {
    return MSLStatusForIOReturn(create_result, true);
  }

  HRESULT query_result = (*plugin)->QueryInterface(
      plugin, CFUUIDGetUUIDBytes(kIONVMeSMARTInterfaceID), (LPVOID *)&smart);
  if (query_result != S_OK || smart == NULL) {
    IODestroyPlugInInterface(plugin);
    return MSL_NVME_SMART_STATUS_INTERFACE_UNAVAILABLE;
  }

  NVMeSMARTData data;
  memset(&data, 0, sizeof(data));
  IOReturn read_result = (*smart)->SMARTReadData(smart, &data);
  if (read_result == kIOReturnSuccess) {
    output->critical_warning = data.CRITICAL_WARNING;
    output->temperature_kelvin = data.TEMPERATURE;
    output->available_spare = data.AVAILABLE_SPARE;
    output->available_spare_threshold = data.AVAILABLE_SPARE_THRESHOLD;
    output->percentage_used = data.PERCENTAGE_USED;
  }

  (*smart)->Release(smart);
  IODestroyPlugInInterface(plugin);
  return read_result == kIOReturnSuccess
             ? MSL_NVME_SMART_STATUS_SUCCESS
             : MSLStatusForIOReturn(read_result, false);
}

int32_t MSLReadSystemNVMeSMARTScalars(MSLNVMeSMARTScalarData *output) {
  if (output == NULL) return MSL_NVME_SMART_STATUS_INVALID_ARGUMENT;
  memset(output, 0, sizeof(*output));

  DASessionRef session = DASessionCreate(kCFAllocatorDefault);
  CFURLRef root_url = CFURLCreateFromFileSystemRepresentation(
      kCFAllocatorDefault, (const UInt8 *)"/", 1, true);
  DADiskRef volume_disk = session != NULL && root_url != NULL
                              ? DADiskCreateFromVolumePath(
                                    kCFAllocatorDefault, session, root_url)
                              : NULL;
  DADiskRef whole_disk = volume_disk != NULL ? DADiskCopyWholeDisk(volume_disk) : NULL;
  io_registry_entry_t current =
      whole_disk != NULL ? DADiskCopyIOMedia(whole_disk) : IO_OBJECT_NULL;

  int32_t status = MSL_NVME_SMART_STATUS_SYSTEM_VOLUME_UNAVAILABLE;
  if (current != IO_OBJECT_NULL) {
    status = MSL_NVME_SMART_STATUS_SMART_UNAVAILABLE;
    for (unsigned depth = 0; depth < 32 && current != IO_OBJECT_NULL; depth++) {
      if (MSLRegistryEntryIsNVMeSMARTCapable(current)) {
        status = MSLReadScalarsFromService(current, output);
        break;
      }

      io_registry_entry_t parent = IO_OBJECT_NULL;
      kern_return_t parent_result =
          IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent);
      IOObjectRelease(current);
      current = parent_result == KERN_SUCCESS ? parent : IO_OBJECT_NULL;
    }
  }

  if (current != IO_OBJECT_NULL) IOObjectRelease(current);
  if (whole_disk != NULL) CFRelease(whole_disk);
  if (volume_disk != NULL) CFRelease(volume_disk);
  if (root_url != NULL) CFRelease(root_url);
  if (session != NULL) CFRelease(session);
  return status;
}
