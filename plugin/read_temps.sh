#!/bin/bash
# Reads CPU temp (k10temp for AMD, coretemp for Intel), GPU temp (nvidia-smi,
# best-effort), and the it87/it8688 chip's two fan tachs. All auto-detected
# by hwmon device name, not a hardcoded hwmon number.
cpuhw=""
fanhw=""
for d in /sys/class/hwmon/hwmon*; do
  name=$(cat "$d/name" 2>/dev/null)
  case "$name" in
    k10temp|coretemp) cpuhw="$d" ;;
    it86*|it87*) fanhw="$d" ;;
  esac
done

cpu="?"
if [ -n "$cpuhw" ] && [ -r "$cpuhw/temp1_input" ]; then
  cpu=$(( $(cat "$cpuhw/temp1_input") / 1000 ))
fi

fan1="?"
fan3="?"
if [ -n "$fanhw" ]; then
  [ -r "$fanhw/fan1_input" ] && fan1=$(cat "$fanhw/fan1_input")
  [ -r "$fanhw/fan3_input" ] && fan3=$(cat "$fanhw/fan3_input")
fi

gpu=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1)
[ -z "$gpu" ] && gpu="?"

profile=$(cat /run/fan-profile-current 2>/dev/null || echo "?")

echo "cpu=$cpu"
echo "gpu=$gpu"
echo "fan1=$fan1"
echo "fan3=$fan3"
echo "profile=$profile"
