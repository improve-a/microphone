from pathlib import Path
import csv

from model.microphone_model import DEFAULT_SEED, generate_frame
from model.udp_protocol import packetize_frame, write_packet_file


ROOT = Path(__file__).resolve().parents[1]
VECTOR_DIR = ROOT / "vectors"


def main() -> int:
    VECTOR_DIR.mkdir(exist_ok=True)
    frame = generate_frame(8, 128, mode="sine", seed=DEFAULT_SEED)
    with (VECTOR_DIR / "mic_expected_pcm.csv").open("w", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerows(frame.tolist())
    write_packet_file(
        VECTOR_DIR / "mic_udp_packets.bin",
        packetize_frame(frame, frame_index=0, starting_sequence=0),
    )
    print("MIC_VECTOR_GENERATION_PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

