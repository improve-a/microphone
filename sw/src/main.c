#include "dma_contract.h"
#include "mic_udp_protocol.h"

#include "xaxidma.h"
#include "xemacps.h"
#include "xemacps_hw.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xstatus.h"
#include "lwip/init.h"
#include "lwip/etharp.h"
#include "lwip/ip_addr.h"
#include "lwip/pbuf.h"
#include "lwip/udp.h"
#include "netif/xadapter.h"
#include "netif/xemacpsif.h"
#include "platform.h"
#include "platform_config.h"
#include "sleep.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define FRONT_GUARD 0x13579BDFU
#define REAR_GUARD  0x2468ACE0U
#define POISON      0xDEADBEEFU
#define WAIT_LIMIT  40000000U
/* The default is a short bounded run.  Long stability builds inject a larger
 * value through the SDK compiler flags; the value remains explicit in the
 * ELF build record and is printed by the completion marker. */
#ifndef MIC_MAX_FRAMES
#define MIC_MAX_FRAMES 24576U
#endif
#define MIC_UDP_PORT 45123U
#define MIC_GEM_BASE XPAR_XEMACPS_0_BASEADDR
#define MIC_PHY_ADDR 3U
#define MIC_HOST_MAC0 0x00U
#define MIC_HOST_MAC1 0xE0U
#define MIC_HOST_MAC2 0x4CU
#define MIC_HOST_MAC3 0x17U
#define MIC_HOST_MAC4 0x46U
#define MIC_HOST_MAC5 0x98U

/* KSZ9031RNX Clause-45 MMD 2 RGMII pad-skew registers. */
#define KSZ9031_MMD_CTRL 13U
#define KSZ9031_MMD_DATA 14U
#define KSZ9031_MMD_DEVAD 2U
#define KSZ9031_CONTROL_PAD_SKEW 4U
#define KSZ9031_RX_DATA_PAD_SKEW 5U
#define KSZ9031_TX_DATA_PAD_SKEW 6U
#define KSZ9031_CLK_PAD_SKEW 8U
#define IEEE_BMCR 0U
#define IEEE_BMCR_FULL_DUPLEX 0x0100U
#define IEEE_BMCR_SPEED100 0x2000U

static XAxiDma dma;
static struct netif server_netif;
struct netif *echo_netif = &server_netif;
static struct udp_pcb *mic_udp;
static ip_addr_t host_ip;
static uint32_t packet_sequence;
static uint32_t send_trace_count;
static uint32_t input_calls;
static uint32_t input_packets;
static uint32_t dma_submissions;
static uint32_t dma_completions;
static uint32_t dma_timeouts;
static uint32_t dma_errors;
static uint32_t udp_successes;
static uint32_t udp_failures;
static void service_network(void);
static int send_raw_broadcast(void);

static int ksz9031_mmd_read(XEmacPs *emacps, uint16_t reg, uint16_t *value)
{
    if (XEmacPs_PhyWrite(emacps, MIC_PHY_ADDR, KSZ9031_MMD_CTRL,
            KSZ9031_MMD_DEVAD) != XST_SUCCESS ||
        XEmacPs_PhyWrite(emacps, MIC_PHY_ADDR, KSZ9031_MMD_DATA, reg) != XST_SUCCESS ||
        XEmacPs_PhyWrite(emacps, MIC_PHY_ADDR, KSZ9031_MMD_CTRL,
            0x4000U | KSZ9031_MMD_DEVAD) != XST_SUCCESS ||
        XEmacPs_PhyRead(emacps, MIC_PHY_ADDR, KSZ9031_MMD_DATA, value) != XST_SUCCESS)
        return 0;
    return 1;
}

static int ksz9031_mmd_write(XEmacPs *emacps, uint16_t reg, uint16_t value)
{
    if (XEmacPs_PhyWrite(emacps, MIC_PHY_ADDR, KSZ9031_MMD_CTRL,
            KSZ9031_MMD_DEVAD) != XST_SUCCESS ||
        XEmacPs_PhyWrite(emacps, MIC_PHY_ADDR, KSZ9031_MMD_DATA, reg) != XST_SUCCESS ||
        XEmacPs_PhyWrite(emacps, MIC_PHY_ADDR, KSZ9031_MMD_CTRL,
            0x4000U | KSZ9031_MMD_DEVAD) != XST_SUCCESS ||
        XEmacPs_PhyWrite(emacps, MIC_PHY_ADDR, KSZ9031_MMD_DATA, value) != XST_SUCCESS)
        return 0;
    return 1;
}

static void ksz9031_configure_rgmii(XEmacPs *emacps)
{
    static const uint16_t regs[] = { KSZ9031_CONTROL_PAD_SKEW,
        KSZ9031_RX_DATA_PAD_SKEW, KSZ9031_TX_DATA_PAD_SKEW,
        KSZ9031_CLK_PAD_SKEW };
    /* Preserve the board's strap-calibrated RGMII delays and write them back
     * explicitly so the setting is deterministic after reset. */
    static const uint16_t values[] = { 0x0077U, 0x7777U, 0x7777U, 0x3DEFU };
    uint16_t value;
    uint32_t index;
    for (index = 0; index < (uint32_t)(sizeof(regs) / sizeof(regs[0])); ++index) {
        if (!ksz9031_mmd_read(emacps, regs[index], &value)) {
            xil_printf("MIC_PHY3_MMD2_REG%u=READ_FAIL\r\n", (unsigned)regs[index]);
            continue;
        }
        xil_printf("MIC_PHY3_MMD2_REG%u_BEFORE=0x%04x\r\n",
            (unsigned)regs[index], (unsigned)value);
        if (!ksz9031_mmd_write(emacps, regs[index], values[index]) ||
            !ksz9031_mmd_read(emacps, regs[index], &value)) {
            xil_printf("MIC_PHY3_MMD2_REG%u_WRITE_FAIL\r\n", (unsigned)regs[index]);
            continue;
        }
        xil_printf("MIC_PHY3_MMD2_REG%u_AFTER=0x%04x\r\n",
            (unsigned)regs[index], (unsigned)value);
    }
}

static void force_100m_full_duplex(XEmacPs *emacps)
{
    uint16_t bmcr = 0U;
    uint32_t nwcfg;
    if (XEmacPs_PhyWrite(emacps, MIC_PHY_ADDR, IEEE_BMCR,
            IEEE_BMCR_SPEED100 | IEEE_BMCR_FULL_DUPLEX) != XST_SUCCESS ||
        XEmacPs_PhyRead(emacps, MIC_PHY_ADDR, IEEE_BMCR, &bmcr) != XST_SUCCESS) {
        xil_printf("MIC_PHY3_FORCE_100M_FAIL\r\n");
    } else {
        xil_printf("MIC_PHY3_BMCR_100M=0x%04x\r\n", (unsigned)bmcr);
    }
    nwcfg = XEmacPs_ReadReg(MIC_GEM_BASE, XEMACPS_NWCFG_OFFSET);
    nwcfg &= ~XEMACPS_NWCFG_1000_MASK;
    nwcfg |= XEMACPS_NWCFG_100_MASK | XEMACPS_NWCFG_FDEN_MASK;
    XEmacPs_WriteReg(MIC_GEM_BASE, XEMACPS_NWCFG_OFFSET, nwcfg);
    xil_printf("MIC_GEM_FORCE_100M_NWCFG=0x%08x\r\n",
        (unsigned)XEmacPs_ReadReg(MIC_GEM_BASE, XEMACPS_NWCFG_OFFSET));
}

static void gem_tx_diag(const char *stage)
{
    UINTPTR base = MIC_GEM_BASE;
    uint32_t txqbase = XEmacPs_ReadReg(base, XEMACPS_TXQBASE_OFFSET);
    uint32_t txq1base = XEmacPs_ReadReg(base, XEMACPS_TXQ1BASE_OFFSET);
    uint32_t active_txq = (txq1base != 0U) ? txq1base : txqbase;
    uint32_t version = XEmacPs_ReadReg(base, 0xFCU);
    xil_printf("MIC_GEM_DIAG stage=%s VERSION=0x%08x NWCTRL=0x%08x NWCFG=0x%08x TXSR=0x%08x ISR=0x%08x TXQBASE=0x%08x TXQ1BASE=0x%08x INTQ1STS=0x%08x INTQ1IER=0x%08x INTQ1IMR=0x%08x OCTTXL=0x%08x TXCNT=0x%08x TXURUNCNT=0x%08x TXCSENSECNT=0x%08x\r\n",
        stage,
        (unsigned)version,
        (unsigned)XEmacPs_ReadReg(base, XEMACPS_NWCTRL_OFFSET),
        (unsigned)XEmacPs_ReadReg(base, XEMACPS_NWCFG_OFFSET),
        (unsigned)XEmacPs_ReadReg(base, XEMACPS_TXSR_OFFSET),
        (unsigned)XEmacPs_ReadReg(base, XEMACPS_ISR_OFFSET),
        (unsigned)txqbase,
        (unsigned)txq1base,
        (unsigned)XEmacPs_ReadReg(base, XEMACPS_INTQ1_STS_OFFSET),
        (unsigned)XEmacPs_ReadReg(base, XEMACPS_INTQ1_IER_OFFSET),
        (unsigned)XEmacPs_ReadReg(base, XEMACPS_INTQ1_IMR_OFFSET),
        (unsigned)XEmacPs_ReadReg(base, XEMACPS_OCTTXL_OFFSET),
        (unsigned)XEmacPs_ReadReg(base, XEMACPS_TXCNT_OFFSET),
        (unsigned)XEmacPs_ReadReg(base, XEMACPS_TXURUNCNT_OFFSET),
        (unsigned)XEmacPs_ReadReg(base, XEMACPS_TXCSENSECNT_OFFSET));
    if (active_txq != 0U) {
        uint32_t ring_base = active_txq & ~0xFFU;
        volatile uint32_t *ring = (volatile uint32_t *)(UINTPTR)ring_base;
        Xil_DCacheInvalidateRange((INTPTR)ring, 128U);
        xil_printf("MIC_GEM_TX_RING_BASE=0x%08x\r\n", (unsigned)ring_base);
        for (uint32_t index = 0; index < 8U; ++index) {
            xil_printf("MIC_GEM_TXRING index=%u WORD0=0x%08x WORD1=0x%08x\r\n",
                (unsigned)index, (unsigned)ring[index * 2U],
                (unsigned)ring[index * 2U + 1U]);
        }
        volatile uint32_t *descriptor = (volatile uint32_t *)(UINTPTR)active_txq;
        Xil_DCacheInvalidateRange((INTPTR)descriptor, 64U);
        for (uint32_t index = 0; index < 4U; ++index) {
            uint32_t word0 = descriptor[index * 2U];
            uint32_t word1 = descriptor[index * 2U + 1U];
            xil_printf("MIC_GEM_TXBD index=%u WORD0=0x%08x WORD1=0x%08x USED=%u WRAP=%u LAST=%u LEN=%u\r\n",
                (unsigned)index, (unsigned)word0, (unsigned)word1,
                (unsigned)((word1 & XEMACPS_TXBUF_USED_MASK) != 0U),
                (unsigned)((word1 & XEMACPS_TXBUF_WRAP_MASK) != 0U),
                (unsigned)((word1 & XEMACPS_TXBUF_LAST_MASK) != 0U),
                (unsigned)(word1 & XEMACPS_TXBUF_LEN_MASK));
        }
    }
}

static void gem_tx_ring_state(const char *stage)
{
    struct xemac_s *xemac = (struct xemac_s *)echo_netif->state;
    xemacpsif_s *xemacps = (xemacpsif_s *)xemac->state;
    XEmacPs_BdRing *ring = &XEmacPs_GetTxRing(&xemacps->emacps);
    xil_printf("MIC_GEM_TX_STATE stage=%s BASE=0x%08x PHYS=0x%08x HWHEAD=0x%08x HWTAIL=0x%08x PREHEAD=0x%08x POSTHEAD=0x%08x HWCNT=%u PRECNT=%u POSTCNT=%u FREECNT=%u ALLCNT=%u RUN=%u\r\n",
        stage, (unsigned)ring->BaseBdAddr, (unsigned)ring->PhysBaseAddr,
        (unsigned)ring->HwHead, (unsigned)ring->HwTail,
        (unsigned)ring->PreHead, (unsigned)ring->PostHead,
        (unsigned)ring->HwCnt, (unsigned)ring->PreCnt,
        (unsigned)ring->PostCnt, (unsigned)ring->FreeCnt,
        (unsigned)ring->AllCnt, (unsigned)ring->RunState);
}

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
    input_calls++;
    {
        int packets = xemacif_input(echo_netif);
        if (packets > 0) input_packets += (uint32_t)packets;
    }
}

static void print_rx_diag(const char *stage)
{
    struct xemac_s *xemac = (struct xemac_s *)echo_netif->state;
    xemacpsif_s *xemacps = (xemacpsif_s *)xemac->state;
    XEmacPs_BdRing *ring = &XEmacPs_GetRxRing(&xemacps->emacps);
    xil_printf("MIC_RX_DIAG stage=%s INPUT_CALLS=%u INPUT_PACKETS=%u RXSR=0x%08x ISR=0x%08x RXCNT=%u RX64=%u OCTRXL=%u HWCNT=%u FREECNT=%u\r\n",
        stage, (unsigned)input_calls, (unsigned)input_packets,
        (unsigned)XEmacPs_ReadReg(MIC_GEM_BASE, XEMACPS_RXSR_OFFSET),
        (unsigned)XEmacPs_ReadReg(MIC_GEM_BASE, XEMACPS_ISR_OFFSET),
        (unsigned)XEmacPs_ReadReg(MIC_GEM_BASE, XEMACPS_RXCNT_OFFSET),
        (unsigned)XEmacPs_ReadReg(MIC_GEM_BASE, XEMACPS_RX64CNT_OFFSET),
        (unsigned)XEmacPs_ReadReg(MIC_GEM_BASE, XEMACPS_OCTRXL_OFFSET),
        (unsigned)ring->HwCnt, (unsigned)ring->FreeCnt);
}

static void print_arp_entry(void)
{
    ip4_addr_t *ip = NULL;
    struct netif *netif = NULL;
    struct eth_addr *eth = NULL;
    int found = 0;
    for (size_t index = 0; index < 10U; ++index) {
        if (etharp_get_entry(index, &ip, &netif, &eth) > 0 && ip != NULL &&
            ip4_addr_cmp(ip, ip_2_ip4(&host_ip))) {
            xil_printf("MIC_ARP_ENTRY state=STABLE IP=%u.%u.%u.%u MAC=%02x:%02x:%02x:%02x:%02x:%02x\r\n",
                ip4_addr1(ip), ip4_addr2(ip), ip4_addr3(ip), ip4_addr4(ip),
                eth->addr[0], eth->addr[1], eth->addr[2], eth->addr[3],
                eth->addr[4], eth->addr[5]);
            found = 1;
        }
    }
    if (!found) xil_printf("MIC_ARP_ENTRY state=EMPTY IP=192.168.1.2\r\n");
}

static int send_bytes(const uint8_t *bytes, uint16_t length)
{
    struct pbuf *p = pbuf_alloc(PBUF_TRANSPORT, length, PBUF_RAM);
    err_t error;
    if (p == NULL) { udp_failures++; return 0; }
    memcpy(p->payload, bytes, length);
    if (send_trace_count < 3U) gem_tx_diag("UDP_BEFORE");
    error = udp_sendto(mic_udp, p, &host_ip, MIC_UDP_PORT);
    pbuf_free(p);
    if (send_trace_count < 3U || error != ERR_OK) {
        xil_printf("MIC_UDP_SEND_ERR index=%u err=%d length=%u\r\n",
            (unsigned)send_trace_count, (int)error, (unsigned)length);
        if (send_trace_count < 3U) gem_tx_diag("UDP_AFTER");
    }
    send_trace_count++;
    if (error == ERR_OK) udp_successes++; else udp_failures++;
    return error == ERR_OK;
}

static int send_raw_broadcast(void)
{
    static const uint8_t marker[] = "MIC_EXTERNAL_UNIQUE_100M_20260903";
    struct pbuf *p = pbuf_alloc(PBUF_RAW, 60U, PBUF_RAM);
    uint8_t *frame;
    err_t error;
    if (p == NULL) return 0;
    frame = (uint8_t *)p->payload;
    memset(frame, 0, 60U);
    memset(frame, 0xFF, 6U);
    memcpy(frame + 6U, echo_netif->hwaddr, 6U);
    frame[12] = 0x88U;
    frame[13] = 0xB5U;
    memcpy(frame + 14U, marker, sizeof(marker) - 1U);
    gem_tx_diag("RAW_BEFORE");
    error = echo_netif->linkoutput(echo_netif, p);
    xil_printf("MIC_RAW_L2_SEND_ERR err=%d length=60\r\n", (int)error);
    gem_tx_diag("RAW_AFTER");
    gem_tx_ring_state("RAW_AFTER");
    pbuf_free(p);
    return error == ERR_OK;
}

static int send_raw_arp_request(void)
{
    struct pbuf *p = pbuf_alloc(PBUF_RAW, 60U, PBUF_RAM);
    uint8_t *frame;
    err_t error;
    static const uint8_t board_ip[4] = {192U, 168U, 1U, 10U};
    static const uint8_t host_ip_bytes[4] = {192U, 168U, 1U, 2U};
    if (p == NULL) return 0;
    frame = (uint8_t *)p->payload;
    memset(frame, 0, 60U);
    memset(frame, 0xFF, 6U);
    memcpy(frame + 6U, echo_netif->hwaddr, 6U);
    frame[12] = 0x08U; frame[13] = 0x06U;
    frame[14] = 0x00U; frame[15] = 0x01U; /* Ethernet */
    frame[16] = 0x08U; frame[17] = 0x00U; /* IPv4 */
    frame[18] = 0x06U; frame[19] = 0x04U;
    frame[20] = 0x00U; frame[21] = 0x01U; /* request */
    memcpy(frame + 22U, echo_netif->hwaddr, 6U);
    memcpy(frame + 28U, board_ip, 4U);
    memcpy(frame + 38U, host_ip_bytes, 4U);
    gem_tx_diag("RAW_ARP_BEFORE");
    error = echo_netif->linkoutput(echo_netif, p);
    xil_printf("MIC_RAW_ARP_SEND_ERR err=%d length=60\r\n", (int)error);
    gem_tx_diag("RAW_ARP_AFTER");
    gem_tx_ring_state("RAW_ARP_AFTER");
    pbuf_free(p);
    return error == ERR_OK;
}

static uint16_t raw_checksum(const uint8_t *data, size_t length)
{
    uint32_t sum = 0U;
    while (length > 1U) {
        sum += ((uint16_t)data[0] << 8) | data[1];
        data += 2; length -= 2;
    }
    if (length) sum += (uint16_t)data[0] << 8;
    while (sum >> 16) sum = (sum & 0xFFFFU) + (sum >> 16);
    return (uint16_t)~sum;
}

static int send_raw_ipv4_udp(uint32_t index)
{
    static const uint8_t marker[] = "MIC_RAW_UDP_UNIQUE_20260903";
    const uint16_t udp_len = (uint16_t)(8U + sizeof(marker) - 1U);
    const uint16_t ip_len = (uint16_t)(20U + udp_len);
    const uint16_t frame_len = (uint16_t)(14U + ip_len < 60U ? 60U : 14U + ip_len);
    struct pbuf *p = pbuf_alloc(PBUF_RAW, frame_len, PBUF_RAM);
    uint8_t *frame;
    uint8_t *ip;
    uint8_t *udp;
    err_t error;
    static const uint8_t board_ip[4] = {192U,168U,1U,10U};
    static const uint8_t host_ip_bytes[4] = {192U,168U,1U,2U};
    if (p == NULL) return 0;
    frame = (uint8_t *)p->payload;
    memset(frame, 0, frame_len);
    frame[0] = MIC_HOST_MAC0; frame[1] = MIC_HOST_MAC1; frame[2] = MIC_HOST_MAC2;
    frame[3] = MIC_HOST_MAC3; frame[4] = MIC_HOST_MAC4; frame[5] = MIC_HOST_MAC5;
    memcpy(frame + 6U, echo_netif->hwaddr, 6U);
    frame[12] = 0x08U; frame[13] = 0x00U;
    ip = frame + 14U;
    ip[0] = 0x45U; ip[1] = 0U; ip[2] = (uint8_t)(ip_len >> 8); ip[3] = (uint8_t)ip_len;
    ip[4] = (uint8_t)(index >> 8); ip[5] = (uint8_t)index; ip[6] = 0x40U; ip[7] = 0U;
    ip[8] = 64U; ip[9] = 17U; memcpy(ip + 12U, board_ip, 4U); memcpy(ip + 16U, host_ip_bytes, 4U);
    ip[10] = 0U; ip[11] = 0U;
    { uint16_t checksum = raw_checksum(ip, 20U); ip[10] = (uint8_t)(checksum >> 8); ip[11] = (uint8_t)checksum; }
    udp = ip + 20U;
    udp[0] = 0xB0U; udp[1] = 0x01U; udp[2] = (uint8_t)(MIC_UDP_PORT >> 8); udp[3] = (uint8_t)MIC_UDP_PORT;
    udp[4] = (uint8_t)(udp_len >> 8); udp[5] = (uint8_t)udp_len; udp[6] = 0U; udp[7] = 0U;
    memcpy(udp + 8U, marker, sizeof(marker) - 1U);
    error = echo_netif->linkoutput(echo_netif, p);
    xil_printf("MIC_RAW_UDP_SEND index=%u err=%d length=%u\r\n", (unsigned)index, (int)error, (unsigned)frame_len);
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
    IP4_ADDR(&ipaddr, 192, 168, 1, 10);
    IP4_ADDR(&netmask, 255, 255, 255, 0);
    IP4_ADDR(&gateway, 192, 168, 1, 1);
    IP4_ADDR(&host_ip, 192, 168, 1, 2);
    lwip_init();
    if (!xemac_add(echo_netif, &ipaddr, &netmask, &gateway, mac,
                   PLATFORM_EMAC_BASEADDR)) {
        xil_printf("MIC_GEM0_INIT_FAIL\r\n");
        return 0;
    }
    {
        struct xemac_s *xemac = (struct xemac_s *)echo_netif->state;
        xemacpsif_s *xemacps = (xemacpsif_s *)xemac->state;
        ksz9031_configure_rgmii(&xemacps->emacps);
        force_100m_full_duplex(&xemacps->emacps);
        for (uint32_t phy_reg = 0U; phy_reg <= 10U; ++phy_reg) {
        uint16_t phy_value = 0U;
        if (XEmacPs_PhyRead(&xemacps->emacps, MIC_PHY_ADDR, phy_reg, &phy_value) == XST_SUCCESS) {
            xil_printf("MIC_PHY3_REG%u=0x%04x\r\n",
                (unsigned)phy_reg, (unsigned)phy_value);
        } else {
            xil_printf("MIC_PHY3_REG%u=READ_FAIL\r\n", (unsigned)phy_reg);
        }
        }
    }
    netif_set_default(echo_netif);
    platform_enable_interrupts();
    netif_set_up(echo_netif);
    netif_set_link_up(echo_netif);
    mic_udp = udp_new();
    if (mic_udp == NULL) {
        xil_printf("MIC_UDP_PCB_FAIL\r\n");
        return 0;
    }
    xil_printf("MIC_GEM0_IP=192.168.1.10 HOST=192.168.1.2 PORT=45123\r\n");
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
    xil_printf("MIC_SOURCE=PHYSICAL_I2S\r\n");
    xil_printf("MIC_SOURCE=PHYSICAL_I2S_BCK_HZ=3125000_WS_HZ=48828 SLOT_BITS=32 VALID_BITS=24 PCM_RIGHT_SHIFT=8\r\n");
    xil_printf("MIC_MAX_FRAMES=%u\r\n", (unsigned)MIC_MAX_FRAMES);
    init_platform();
    if (!network_init()) return XST_FAILURE;
    gem_tx_diag("POST_INIT");
    gem_tx_ring_state("POST_INIT");
    xil_printf("MIC_PHY_LOCAL_LOOPBACK_SKIPPED_STABLE_RUN\r\n");
    print_rx_diag("POST_INIT");
    {
        err_t arp_error = etharp_request(echo_netif,
            (const ip4_addr_t *)&host_ip);
        xil_printf("MIC_ARP_REQUEST_ERR err=%d\r\n", (int)arp_error);
        gem_tx_diag("ARP_AFTER");
        gem_tx_ring_state("ARP_AFTER");
    }
    if (!send_raw_arp_request())
        xil_printf("MIC_RAW_ARP_SEND_FAIL\r\n");
    if (!send_raw_broadcast()) {
        xil_printf("MIC_RAW_L2_SEND_FAIL\r\n");
    }
    xil_printf("MIC_DYNAMIC_ARP_WAIT_BEGIN\r\n");
    for (uint32_t warmup = 0; warmup < 3000U; ++warmup) {
        service_network();
        usleep(1000U);
    }
    print_rx_diag("DYNAMIC_ARP_WAIT");
    print_arp_entry();
    {
        struct eth_addr host_eth;
        err_t static_error;
        host_eth.addr[0] = MIC_HOST_MAC0; host_eth.addr[1] = MIC_HOST_MAC1;
        host_eth.addr[2] = MIC_HOST_MAC2; host_eth.addr[3] = MIC_HOST_MAC3;
        host_eth.addr[4] = MIC_HOST_MAC4; host_eth.addr[5] = MIC_HOST_MAC5;
        static_error = etharp_add_static_entry((const ip4_addr_t *)&host_ip, &host_eth);
        xil_printf("MIC_ARP_STATIC_ADD_ERR err=%d MAC=%02x:%02x:%02x:%02x:%02x:%02x\r\n",
            (int)static_error, host_eth.addr[0], host_eth.addr[1], host_eth.addr[2],
            host_eth.addr[3], host_eth.addr[4], host_eth.addr[5]);
        print_arp_entry();
    }
    for (uint32_t heartbeat = 0; heartbeat < 20U; ++heartbeat) {
        int ok = send_heartbeat();
        xil_printf("MIC_STATIC_HEARTBEAT index=%u ok=%u\r\n", (unsigned)heartbeat, (unsigned)ok);
        service_network();
        usleep(100000U);
    }
    print_rx_diag("STATIC_HEARTBEAT_DONE");
    for (uint32_t raw_index = 0; raw_index < 10U; ++raw_index) {
        (void)send_raw_ipv4_udp(raw_index);
        service_network();
        usleep(100000U);
    }
    print_rx_diag("RAW_UDP_DONE");
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
            dma_errors++;
            xil_printf("MIC_DMA_CAPTURE_FAIL frame=%lu\r\n", (unsigned long)frame);
            return XST_FAILURE;
        }
        dma_submissions++;
        for (timeout = 0; timeout < WAIT_LIMIT &&
             XAxiDma_Busy(&dma, XAXIDMA_DEVICE_TO_DMA); ++timeout) {
            service_network();
        }
        status = XAxiDma_ReadReg(dma.RegBase, XAXIDMA_RX_OFFSET + XAXIDMA_SR_OFFSET);
        if (timeout == WAIT_LIMIT || (status & XAXIDMA_ERR_ALL_MASK) != 0U) {
            if (timeout == WAIT_LIMIT) dma_timeouts++;
            if ((status & XAXIDMA_ERR_ALL_MASK) != 0U) dma_errors++;
            (void)recover_dma();
            xil_printf("MIC_DMA_CAPTURE_FAIL frame=%lu status=0x%08x\r\n",
                (unsigned long)frame, (unsigned)status);
            return XST_FAILURE;
        }
        dma_completions++;
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
    xil_printf("MIC_CONTINUOUS_STATS DMA_SUBMISSIONS=%u DMA_COMPLETIONS=%u DMA_TIMEOUTS=%u DMA_ERRORS=%u UDP_OK=%u UDP_FAIL=%u INPUT_CALLS=%u INPUT_PACKETS=%u\r\n",
        (unsigned)dma_submissions, (unsigned)dma_completions,
        (unsigned)dma_timeouts, (unsigned)dma_errors,
        (unsigned)udp_successes, (unsigned)udp_failures,
        (unsigned)input_calls, (unsigned)input_packets);
    print_capture_stats(&slots[0]);
    cleanup_platform();
    return XST_SUCCESS;
}
