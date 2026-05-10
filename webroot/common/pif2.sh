#!/system/bin/sh

getprop | grep -E "pihook|pixelprops" | sed -E "s/^\[(.*)\]:.*/\1/" | while IFS= read -r prop; do
  resetprop -p -d "$prop" 2>/dev/null || true
done