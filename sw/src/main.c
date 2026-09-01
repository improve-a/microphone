#include "dma_contract.h"

#include "xaxidma.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xstatus.h"

#include <stdint.h>

#define FRONT_GUARD 0x13579BDFU
#define REAR_GUARD  0x2468ACE0U
#define POISON      0xDEADBEEFU
#define WAIT_LIMIT  40000000U

static XAxiDma dma;

static int16_t sine_q15(uint32_t phase)
{
    static const int16_t table[32] = {
        0,6393,12539,18204,23170,27245,30273,32137,
        32767,32137,30273,27245,23170,18204,12539,6393,
        0,-6393,-12539,-18204,-23170,-27245,-30273,-32137,
        -32768,-32137,-30273,-27245,-23170,-18204,-12539,-6393
    };
    return table[phase & 31U];
}

static int16_t expected_sample(uint32_t sample, uint32_t channel)
{
    if (sample < channel)
        return 0;
    return (int16_t)(sine_q15(sample - channel) >> (channel > 15U ? 15U : channel));
}

static void prepare_slot(const mic_dma_slot_t *slot)
{
    volatile uint32_t *front = (volatile uint32_t *)slot->base;
    volatile uint32_t *payload = (volatile uint32_t *)slot->payload;
    volatile uint32_t *rear = (volatile uint32_t *)(slot->payload + MIC_FRAME_BYTES);
    uint32_t index;
    for (index = 0; index < MIC_GUARD_BYTES / 4U; ++index) front[index] = FRONT_GUARD ^ index;
    for (index = 0; index < MIC_FRAME_BYTES / 4U; ++index) payload[index] = POISON;
    for (index = 0; index < MIC_GUARD_BYTES / 4U; ++index) rear[index] = REAR_GUARD ^ index;
    Xil_DCacheFlushRange((INTPTR)slot->base, MIC_SLOT_BYTES);
}

static int verify_slot(const mic_dma_slot_t *slot)
{
    volatile uint32_t *front = (volatile uint32_t *)slot->base;
    volatile int16_t *payload = (volatile int16_t *)slot->payload;
    volatile uint32_t *rear = (volatile uint32_t *)(slot->payload + MIC_FRAME_BYTES);
    uint32_t sample, channel, index;
    Xil_DCacheInvalidateRange((INTPTR)slot->base, MIC_SLOT_BYTES);
    for (index = 0; index < MIC_GUARD_BYTES / 4U; ++index)
        if (front[index] != (FRONT_GUARD ^ index) || rear[index] != (REAR_GUARD ^ index)) return 0;
    for (sample = 0; sample < MIC_SAMPLES_PER_FRAME; ++sample)
        for (channel = 0; channel < MIC_CHANNELS; ++channel)
            if (payload[sample * MIC_CHANNELS + channel] != expected_sample(sample, channel)) return 0;
    return 1;
}

static int recover_dma(void)
{
    uint32_t timeout;
    XAxiDma_Reset(&dma);
    for (timeout = 0; timeout < WAIT_LIMIT && !XAxiDma_ResetIsDone(&dma); ++timeout) {}
    return timeout != WAIT_LIMIT;
}

int main(void)
{
    XAxiDma_Config *config;
    mic_dma_slot_t slots[MIC_SLOT_COUNT];
    uint32_t timeout, status;
    xil_printf("MIC_DMA_SW_BOOT\r\n");
    if (!mic_layout_slots(XPAR_PS7_DDR_0_S_AXI_BASEADDR,
            XPAR_PS7_DDR_0_S_AXI_HIGHADDR, slots)) return XST_FAILURE;
    config = XAxiDma_LookupConfig(XPAR_AXIDMA_0_DEVICE_ID);
    if (config == NULL || XAxiDma_CfgInitialize(&dma, config) != XST_SUCCESS || XAxiDma_HasSg(&dma))
        return XST_FAILURE;
    prepare_slot(&slots[0]);
    if (XAxiDma_SimpleTransfer(&dma, (UINTPTR)slots[0].payload,
            MIC_FRAME_BYTES, XAXIDMA_DEVICE_TO_DMA) != XST_SUCCESS) return XST_FAILURE;
    for (timeout = 0; timeout < WAIT_LIMIT && XAxiDma_Busy(&dma, XAXIDMA_DEVICE_TO_DMA); ++timeout) {}
    status = XAxiDma_ReadReg(dma.RegBase, XAXIDMA_RX_OFFSET + XAXIDMA_SR_OFFSET);
    if (timeout == WAIT_LIMIT || (status & XAXIDMA_ERR_ALL_MASK) != 0U) {
        (void)recover_dma();
        return XST_FAILURE;
    }
    if (!verify_slot(&slots[0])) return XST_FAILURE;
    xil_printf("MIC_DMA_CAPTURE_COMPLETE_NEEDS_PHYSICAL_ACCEPTANCE\r\n");
    return XST_SUCCESS;
}

