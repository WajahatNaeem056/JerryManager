# Pixel Canary devices offered by the PIF device picker: "Model|product"
PIF_DEVICE_LIST="Pixel 6|oriole_beta
Pixel 6 Pro|raven_beta
Pixel 6a|bluejay_beta
Pixel 7|panther_beta
Pixel 7 Pro|cheetah_beta
Pixel 7a|lynx_beta
Pixel Fold|felix_beta
Pixel Tablet|tangorpro_beta
Pixel 8|shiba_beta
Pixel 8 Pro|husky_beta
Pixel 8a|akita_beta
Pixel 9|tokay_beta
Pixel 9 Pro|caiman_beta
Pixel 9 Pro XL|komodo_beta
Pixel 9 Pro Fold|comet_beta
Pixel 9a|tegu_beta
Pixel 10|frankel_beta
Pixel 10 Pro|blazer_beta
Pixel 10 Pro XL|mustang_beta
Pixel 10 Pro Fold|rango_beta
Pixel 10a|stallion_beta
Pixel 11|cubs_beta
Pixel 11 Pro|grizzly_beta
Pixel 11 Pro XL|kodiak_beta
Pixel 11 Pro Fold|yogi_beta"

# model name for a product (empty if unknown)
pif_model_of() {
  printf '%s\n' "$PIF_DEVICE_LIST" | awk -F'|' -v p="$1" '$2==p{print $1; exit}'
}
