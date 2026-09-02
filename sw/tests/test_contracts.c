#include "dma_contract.h"
#include "mic_udp_protocol.h"

#include <assert.h>
#include <stdio.h>

int main(void)
{
    mic_dma_slot_t slots[MIC_SLOT_COUNT];
    int16_t samples[4] = {-32768, 32767, -1, 1};
    uint8_t packet[128];
    size_t bytes;
    assert(mic_frame_bytes(8U, 128U) == 2048U);
    assert(mic_btt_valid(MIC_FRAME_BYTES));
    assert(!mic_btt_valid(0U));
    assert(!mic_btt_valid(MIC_DMA_MAX_BTT + 1U));
    assert(mic_layout_slots(0x00100000U, 0x3FFFFFFFU, slots));
    assert((slots[0].base & 63U) == 0U);
    assert(slots[0].payload == slots[0].base + MIC_GUARD_BYTES);
    assert(slots[1].base - slots[0].base == MIC_SLOT_BYTES);
    bytes = mic_udp_build_packet(packet, sizeof(packet), samples, 2U, 2U,
        7U, 3U, 0U, MIC_UDP_FLAG_FRAME_START | MIC_UDP_FLAG_FRAME_END);
    assert(bytes == MIC_UDP_HEADER_BYTES + sizeof(samples));
    assert(packet[0] == 'M' && packet[4] == 1U && packet[20] == 2U);
    assert(mic_crc32(packet, 28U) ==
        ((uint32_t)packet[28] | (uint32_t)packet[29] << 8 |
        (uint32_t)packet[30] << 16 | (uint32_t)packet[31] << 24));
    puts("MIC_SW_HOST_BUILD_PASS");
    return 0;
}
