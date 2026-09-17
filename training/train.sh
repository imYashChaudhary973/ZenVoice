#!/bin/bash
# Fine-tune, merge, and quantize the ZenVoice enhancement model with mlx-lm.
#
# Prereqs:
#   python3 -m pip install -r requirements.txt
#   python3 build_synthetic.py --seed 7 --corpus <your_corpus.txt...> --out data
#
# Environment knobs:
#   MODEL   base model (default: mlx-community/Qwen3-1.7B-4bit)
#   ITERS   training iterations (default: 12000)

set -euo pipefail
cd "$(dirname "$0")"

MODEL="${MODEL:-mlx-community/Qwen3-1.7B-4bit}"
ITERS="${ITERS:-12000}"
BATCH="${BATCH:-8}"
ADAPTERS="${ADAPTERS:-adapters}"
# RESUME=1 continues from $ADAPTERS/adapters.safetensors (adapter weights are
# restored; the iteration counter and LR schedule restart from zero).
RESUME_ARGS=()
if [ "${RESUME:-0}" = 1 ]; then
  ADAPTER_FILE="$ADAPTERS/adapters.safetensors"
  # A zero-byte or truncated file would silently restart from scratch or
  # crash mid-train; fail loudly before wasting the run.
  [ -s "$ADAPTER_FILE" ] || {
    echo "ERROR: RESUME=1 but $ADAPTER_FILE is missing or empty — set RESUME=0 or restore the adapter file" >&2
    exit 1
  }
  RESUME_ARGS=(--resume-adapter-file "$ADAPTER_FILE")
fi

[ -f data/synthetic_train.jsonl ] || { echo "data/synthetic_train.jsonl missing — run build_synthetic.py first"; exit 1; }
python3 -c "import mlx_lm" 2>/dev/null || { echo "mlx-lm missing — python3 -m pip install -r requirements.txt"; exit 1; }

# Compose the mlx-lm data files: frozen synthetic pairs + real decoded pairs.
touch data/real_train.jsonl data/real_valid.jsonl data/vox_train.jsonl
if ! [ -s data/real_train.jsonl ] && ! [ -s data/vox_train.jsonl ]; then
  echo "WARNING: data/real_train.jsonl and data/vox_train.jsonl are empty or missing — training will run SYNTHETIC-ONLY" >&2
fi
cat data/synthetic_train.jsonl data/real_train.jsonl data/vox_train.jsonl > data/train.jsonl
cat data/synthetic_valid.jsonl data/real_valid.jsonl > data/valid.jsonl
echo "train: $(wc -l < data/train.jsonl | tr -d ' ') rows, valid: $(wc -l < data/valid.jsonl | tr -d ' ') rows"

# 1. LoRA fine-tune (runs locally on Apple Silicon; mlx-lm prints periodic samples)
# ${arr[@]+...} guards the empty case: bash 3.2 (stock macOS) rejects "${arr[@]}"
# for an empty array under set -u.
python3 -m mlx_lm lora --train \
  --model "$MODEL" \
  --data data \
  --iters "$ITERS" \
  --batch-size "$BATCH" \
  ${RESUME_ARGS[@]+"${RESUME_ARGS[@]}"} \
  --adapter-path "$ADAPTERS"

# 2. Merge adapters into the base weights (keeps base quantization)
python3 -m mlx_lm fuse \
  --model "$MODEL" \
  --adapter-path "$ADAPTERS" \
  --save-path fused

# 3. Ship dir: fused keeps base quantization; convert only a bf16 base.
# Build into a temp dir first so a failed fuse/convert never destroys the
# previous zen-polish-4bit; swap only after a successful build.
rm -rf zen-polish-4bit.tmp
if grep -q '"quantization"' fused/config.json; then
  mv fused zen-polish-4bit.tmp
else
  python3 -m mlx_lm convert --hf-path fused --mlx-path zen-polish-4bit.tmp --quantize
fi
rm -rf zen-polish-4bit
mv zen-polish-4bit.tmp zen-polish-4bit

echo
echo "Done. Score with:"
echo "  python3 baseline.py --model zen-polish-4bit --eval data/eval.jsonl --out data/hyps_zpolish.txt --limit 300"
echo "  python3 evaluate.py --eval data/eval.jsonl --pred data/hyps_zpolish.txt --limit 300"
