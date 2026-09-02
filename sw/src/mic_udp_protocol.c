#include "mic_udp_protocol.h"

#include <string.h>

static void write_u16_le(uint8_t *out, uint16_t value)
{
    out[0] = (uint8_t)value;
    out[1] = (uint8_t)(value >> 8);
}

static void write_u32_le(uint8_t *out, uint32_t value)
{
    out[0] = (uint8_t)value;
    out[1] = (uint8_t)(value >> 8);
    out[2] = (uint8_t)(value >> 16);
    out[3] = (uint8_t)(value >> 24);
}

uint32_t mic_crc32(const uint8_t *data, size_t length)
{
    uint32_t crc = 0xFFFFFFFFU;
    size_t index;
    unsigned bit;
    for (index = 0; index < length; ++index) {
        crc ^= data[index];
        for (bit = 0; bit < 8U; ++bit)
            crc = (crc >> 1) ^ ((0U - (crc & 1U)) & 0xEDB88320U);
    }
    return ~crc;
}

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
)
{
    size_t payload = (size_t)channels * samples_per_channel * 2U;
    size_t total = MIC_UDP_HEADER_BYTES + payload;
    uint32_t crc;
    if (destination == NULL || sample_major_pcm == NULL || channels == 0U ||
        samples_per_channel == 0U || total > capacity || total > MIC_UDP_MAX_DATAGRAM ||
        payload > UINT16_MAX)
        return 0U;
    memset(destination, 0, MIC_UDP_HEADER_BYTES);
    memcpy(destination, "MIC0", 4U);
    destination[4] = 1U;
    destination[5] = MIC_UDP_HEADER_BYTES;
    destination[6] = 1U;
    destination[7] = flags;
    write_u32_le(destination + 8, packet_sequence);
    write_u32_le(destination + 12, frame_index);
    write_u32_le(destination + 16, sample_start);
    write_u16_le(destination + 20, channels);
    write_u16_le(destination + 22, samples_per_channel);
    write_u16_le(destination + 24, (uint16_t)payload);
    crc = mic_crc32(destination, 28U);
    write_u32_le(destination + 28, crc);
    memcpy(destination + MIC_UDP_HEADER_BYTES, sample_major_pcm, payload);
    return total;
}

