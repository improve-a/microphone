#include "dma_contract.h"

size_t mic_frame_bytes(uint32_t channels, uint32_t samples_per_frame)
{
    if (channels == 0U || samples_per_frame == 0U)
        return 0U;
    if ((size_t)channels > SIZE_MAX / (size_t)samples_per_frame / MIC_BYTES_PER_SAMPLE)
        return 0U;
    return (size_t)channels * (size_t)samples_per_frame * MIC_BYTES_PER_SAMPLE;
}

int mic_btt_valid(size_t byte_count)
{
    return byte_count > 0U && byte_count <= MIC_DMA_MAX_BTT;
}

int mic_layout_slots(
    uintptr_t ddr_base,
    uintptr_t ddr_high,
    mic_dma_slot_t slots[MIC_SLOT_COUNT]
)
{
    uintptr_t end, required, first;
    uint32_t index;
    if (slots == NULL || ddr_high == UINTPTR_MAX || ddr_high < ddr_base)
        return 0;
    end = ddr_high + 1U;
    required = MIC_DDR_TOP_MARGIN + MIC_SLOT_COUNT * MIC_SLOT_BYTES;
    if (end - ddr_base <= required)
        return 0;
    first = (end - required) & ~(uintptr_t)(MIC_CACHE_ALIGNMENT - 1U);
    if (first < ddr_base || first + MIC_SLOT_COUNT * MIC_SLOT_BYTES > end)
        return 0;
    for (index = 0; index < MIC_SLOT_COUNT; ++index) {
        slots[index].base = first + index * MIC_SLOT_BYTES;
        slots[index].payload = slots[index].base + MIC_GUARD_BYTES;
        if ((slots[index].base & (MIC_CACHE_ALIGNMENT - 1U)) != 0U)
            return 0;
    }
    return 1;
}

