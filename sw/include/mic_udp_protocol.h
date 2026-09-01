#ifndef MIC_UDP_PROTOCOL_H
#define MIC_UDP_PROTOCOL_H

#include <stddef.h>
#include <stdint.h>

#define MIC_UDP_HEADER_BYTES 32U
#define MIC_UDP_MAX_DATAGRAM 1472U
#define MIC_UDP_FLAG_FRAME_START 0x01U
#define MIC_UDP_FLAG_FRAME_END 0x02U

uint32_t mic_crc32(const uint8_t *data, size_t length);
size_t mic_udp_build_packet(
    uint8_t *destination,
    size_t capacity,
    const int16_t *sample_major_pcm,
    uint16_t channels,
    uint16_t samples_per_channel,
    uint32_t packet_sequence,
    uint32_t frame_index,
    uint32_t sample_start,
    uint8_t flags
);

#endif

