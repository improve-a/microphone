#include "dma_contract.h"
#include "mic_udp_protocol.h"

#include "xaxidma.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xstatus.h"
#include "lwip/init.h"
#include "lwip/ip_addr.h"
#include "lwip/pbuf.h"
#include "lwip/udp.h"
#include "netif/xadapter.h"
#include "platform.h"
#include "platform_config.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define FRONT_GUARD 0x13579BDFU
#define REAR_GUARD  0x2468ACE0U
#define POISON      0xDEADBEEFU
#define WAIT_LIMIT  40000000U
#define MIC_MAX_FRAMES 4096U
#define MIC_UDP_PORT 45123U

static XAxiDma dma;
static struct netif server_netif;
struct netif *echo_netif = &server_netif;
static struct udp_pcb *mic_udp;
static ip_addr_t host_ip;
static uint32_t packet_sequence;

extern volatile int TcpFastTmrFlag;
extern volatile int TcpSlowTmrFlag;
void tcp_fasttmr(void);
void tcp_slowtmr(void);
void lwip_init(void);

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

static void service_network(void)
{
    if (TcpFastTmrFlag) {
        tcp_fasttmr();
        TcpFastTmrFlag = 0;
    }
    if (TcpSlowTmrFlag) {
        tcp_slowtmr();
        TcpSlowTmrFlag = 0;
    }
    xemacif_input(echo_netif);
}

static int send_bytes(const uint8_t *bytes, uint16_t length)
{
    struct pbuf *p = pbuf_alloc(PBUF_TRANSPORT, length, PBUF_RAM);
    err_t error;
    if (p == NULL) return 0;
    memcpy(p->payload, bytes, length);
    error = udp_sendto(mic_udp, p, &host_ip, MIC_UDP_PORT);
    pbuf_free(p);
    return error == ERR_OK;
}

static int send_heartbeat(void)
{
    char text[64];
    int length = snprintf(text, sizeof(text), "MIC_HEARTBEAT seq=%lu\n",
        (unsigned long)packet_sequence++);
    if (length <= 0 || (size_t)length >= sizeof(text)) return 0;
    return send_bytes((const uint8_t *)text, (uint16_t)length);
}

static int network_init(void)
{
    ip_addr_t ipaddr, netmask, gateway;
    unsigned char mac[] = { 0x00, 0x0A, 0x35, 0x00, 0x01, 0x02 };
    IP4_ADDR(&ipaddr, 169, 254, 248, 10);
    IP4_ADDR(&netmask, 255, 255, 0, 0);
    IP4_ADDR(&gateway, 0, 0, 0, 0);
    IP4_ADDR(&host_ip, 169, 254, 248, 53);
    lwip_init();
    if (!xemac_add(echo_netif, &ipaddr, &netmask, &gateway, mac,
                   PLATFORM_EMAC_BASEADDR)) {
        xil_printf("MIC_GEM0_INIT_FAIL\r\n");
        return 0;
    }
    netif_set_default(echo_netif);
    netif_set_up(echo_netif);
    netif_set_link_up(echo_netif);
    platform_enable_interrupts();
    mic_udp = udp_new();
    if (mic_udp == NULL) {
        xil_printf("MIC_UDP_PCB_FAIL\r\n");
        return 0;
    }
    xil_printf("MIC_GEM0_IP=169.254.248.10 HOST=169.254.248.53 PORT=45123\r\n");
    xil_printf("MIC_LWIP_GEM0_READY\r\n");
    return 1;
}

static int verify_slot(const mic_dma_slot_t *slot)
{
    volatile uint32_t *front = (volatile uint32_t *)slot->base;
    volatile uint32_t *rear = (volatile uint32_t *)(slot->payload + MIC_FRAME_BYTES);
    uint32_t index;
    Xil_DCacheInvalidateRange((INTPTR)slot->base, MIC_SLOT_BYTES);
    for (index = 0; index < MIC_GUARD_BYTES / 4U; ++index)
        if (front[index] != (FRONT_GUARD ^ index) || rear[index] != (REAR_GUARD ^ index)) return 0;
    return 1;
}

static void print_capture_stats(const mic_dma_slot_t *slot)
{
    volatile int16_t *payload = (volatile int16_t *)slot->payload;
    int32_t minv[MIC_CHANNELS], maxv[MIC_CHANNELS];
    uint32_t sum_abs[MIC_CHANNELS] = {0};
    uint32_t sample, channel;
    for (channel = 0; channel < MIC_CHANNELS; ++channel) {
        minv[channel] = 32767;
        maxv[channel] = -32768;
    }
    for (sample = 0; sample < MIC_SAMPLES_PER_FRAME; ++sample) {
        for (channel = 0; channel < MIC_CHANNELS; ++channel) {
            int32_t value = payload[sample * MIC_CHANNELS + channel];
            uint32_t magnitude = (value < 0) ? (uint32_t)(-value) : (uint32_t)value;
            if (value < minv[channel]) minv[channel] = value;
            if (value > maxv[channel]) maxv[channel] = value;
            sum_abs[channel] += magnitude;
        }
    }
    xil_printf("MIC_PCM_STATS_SR_HZ=48828 CHANNELS=8 SAMPLES=128\r\n");
    for (channel = 0; channel < MIC_CHANNELS; ++channel)
        xil_printf("MIC_CH%u_MIN=%d_MAX=%d_MEAN_ABS=%u\r\n",
            channel, (int)minv[channel], (int)maxv[channel],
            (unsigned)(sum_abs[channel] / MIC_SAMPLES_PER_FRAME));
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
    xil_printf("MIC_SW_ENTRY\r\n");
    xil_printf("MIC_UART_READY\r\n");
    xil_printf("MIC_SOURCE=PHYSICAL_I2S_BCK_HZ=3125000_WS_HZ=48828\r\n");
    init_platform();
    if (!network_init()) return XST_FAILURE;
    if (!send_heartbeat()) return XST_FAILURE;
    xil_printf("MIC_UDP_HEARTBEAT_SENT\r\n");
    if (!mic_layout_slots(XPAR_PS7_DDR_0_S_AXI_BASEADDR,
            XPAR_PS7_DDR_0_S_AXI_HIGHADDR, slots)) return XST_FAILURE;
    xil_printf("MIC_BEFORE_DMA_LOOKUP\r\n");
    config = XAxiDma_LookupConfig(XPAR_AXIDMA_0_DEVICE_ID);
    xil_printf("MIC_AFTER_DMA_LOOKUP\r\n");
    xil_printf("MIC_BEFORE_DMA_CFG\r\n");
    if (config == NULL || XAxiDma_CfgInitialize(&dma, config) != XST_SUCCESS || XAxiDma_HasSg(&dma))
        return XST_FAILURE;
    xil_printf("MIC_AFTER_DMA_CFG\r\n");
    xil_printf("MIC_DMA_AXIL_PHYSICAL_PASS\r\n");
    xil_printf("MIC_DMA_DEVICE_ID=%u BASE=0x%08x\r\n",
        (unsigned)XPAR_AXIDMA_0_DEVICE_ID, (unsigned)dma.RegBase);
    xil_printf("MIC_CAPTURE_ARMED\r\n");
    for (uint32_t frame = 0; frame < MIC_MAX_FRAMES; ++frame) {
        uint8_t packet[MIC_UDP_MAX_DATAGRAM];
        size_t packet_bytes;
        mic_dma_slot_t *slot = &slots[frame % MIC_SLOT_COUNT];
        prepare_slot(slot);
        if (XAxiDma_SimpleTransfer(&dma, (UINTPTR)slot->payload,
                MIC_FRAME_BYTES, XAXIDMA_DEVICE_TO_DMA) != XST_SUCCESS) {
            xil_printf("MIC_DMA_CAPTURE_FAIL frame=%lu\r\n", (unsigned long)frame);
            return XST_FAILURE;
        }
        for (timeout = 0; timeout < WAIT_LIMIT &&
             XAxiDma_Busy(&dma, XAXIDMA_DEVICE_TO_DMA); ++timeout) {
            service_network();
        }
        status = XAxiDma_ReadReg(dma.RegBase, XAXIDMA_RX_OFFSET + XAXIDMA_SR_OFFSET);
        if (timeout == WAIT_LIMIT || (status & XAXIDMA_ERR_ALL_MASK) != 0U) {
            (void)recover_dma();
            xil_printf("MIC_DMA_CAPTURE_FAIL frame=%lu status=0x%08x\r\n",
                (unsigned long)frame, (unsigned)status);
            return XST_FAILURE;
        }
        if (!verify_slot(slot)) {
            xil_printf("MIC_DMA_GUARD_FAIL frame=%lu\r\n", (unsigned long)frame);
            return XST_FAILURE;
        }
        /* 1472-byte Ethernet UDP datagrams hold 90 samples/channel. */
        for (uint32_t part = 0; part < 2U; ++part) {
            uint32_t sample_start = (part == 0U) ? 0U : 90U;
            uint16_t sample_count = (part == 0U) ? 90U : 38U;
            uint8_t flags = (part == 0U ? MIC_UDP_FLAG_FRAME_START : 0U) |
                (part == 1U ? MIC_UDP_FLAG_FRAME_END : 0U);
            const int16_t *part_pcm = (const int16_t *)slot->payload +
                sample_start * MIC_CHANNELS;
            packet_bytes = mic_udp_build_packet(packet, sizeof(packet), part_pcm,
                MIC_CHANNELS, sample_count, packet_sequence++, frame,
                sample_start, flags);
            if (packet_bytes == 0U || !send_bytes(packet, (uint16_t)packet_bytes)) {
                xil_printf("MIC_UDP_SEND_FAIL frame=%lu part=%lu\r\n",
                    (unsigned long)frame, (unsigned long)part);
                return XST_FAILURE;
            }
        }
        if ((frame % 256U) == 0U) {
            xil_printf("MIC_UDP_PCM_SENT frame=%lu seq=%lu\r\n",
                (unsigned long)frame, (unsigned long)(packet_sequence - 1U));
        }
        service_network();
    }
    xil_printf("MIC_UDP_BOUNDED_COMPLETE frames=%u\r\n", MIC_MAX_FRAMES);
    print_capture_stats(&slots[0]);
    cleanup_platform();
    return XST_SUCCESS;
}
