#ifndef THERMAL_PULSE_SMC_H
#define THERMAL_PULSE_SMC_H

#include <stdint.h>

typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t build;
    uint8_t reserved;
    uint16_t release;
} TPSMCKeyVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} TPSMCKeyLimits;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
} TPSMCKeyInfoData;

typedef struct {
    uint32_t key;
    TPSMCKeyVersion vers;
    TPSMCKeyLimits pLimitData;
    TPSMCKeyInfoData keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} TPSMCParamStruct;

_Static_assert(sizeof(TPSMCParamStruct) == 80, "AppleSMC parameter ABI must remain 80 bytes");

#endif

