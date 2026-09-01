#ifndef MIC_DMA_CONTRACT_H
#define MIC_DMA_CONTRACT_H

#include <stddef.h>
#include <stdint.h>

#define MIC_CHANNELS 8U
#define MIC_SAMPLES_PER_FRAME 128U
#define MIC_BYTES_PER_SAMPLE 2U
#define MIC_FRAME_BYTES (MIC_CHANNELS * MIC_SAMPLES_PER_FRAME * MIC_BYTES_PER_SAMPLE)
#define MIC_DMA_MAX_BTT ((1U << 23) - 1U)
#define MIC_CACHE_ALIGNMENT 64U
#define MIC_GUARD_BYTES 64U
#define MIC_SLOT_BYTES (MIC_GUARD_BYTES + MIC_FRAME_BYTES + MIC_GUARD_BYTES)
#define MIC_SLOT_COUNT 3U
#define MIC_DDR_TOP_MARGIN (1024U * 1024U)

typedef struct {
    uintptr_t base;
    uintptr_t payload;
} mic_dma_slot_t;

size_t mic_frame_bytes(uint32_t channels, uint32_t samples_per_frame);
int mic_btt_valid(size_t byte_count);
int mic_layout_slots(
    uintptr_t ddr_base,
    uintptr_t ddr_high,
    mic_dma_slot_t slots[MIC_SLOT_COUNT]
);

#endif

